-- =====================================================================
-- CanariApp - Esquema SQL v7.1 (corrige el v7 según revision_fable/, SRS CanariApp v1.0)
-- Modelo: MER_canarios_v7_1.drawio
-- Motor: PostgreSQL 16+
--
-- Este script SOLO crea. No borra nada: para recrear la base en desarrollo
-- se ejecuta antes reset_dev_v7_1.sql (review v6, M6). Después de este script
-- se ejecuta permisos_v7_1.sql.
--
-- Cambios respecto al v6 (detalle en Cambios_v7_1.md):
--   1. Aislamiento por criadero declarativo: llaves foráneas compuestas en
--      pareja, solicitud_correccion y simulacion; id_criador no se puede
--      modificar en canario ni en jaula (SEG-001).
--   2. Ciclo de vida de la pareja: nace activa, una pareja cerrada no cambia
--      de estado y una pareja con cruces no se anula (SRS-RF017, SRS-RF031).
--   3. Genealogía: un ejemplar no puede ser cría de su propia pareja y no se
--      puede borrar la fila de cria de un ejemplar pendiente (SRS-RF022).
--   4. Anillo único sin contar ceros a la izquierda (SRS-RF003).
--   5. «Requiere revisión» lo calcula la base; variedad.sexo se deriva del
--      nombre (SRS-RF009, SRS-RF010, SRS-RF032).
--   6. Roles: solo un usuario criador tiene criadero y solo un administrador
--      activa modos o genera respaldos (SEG-001, SRS-RF026, SRS-RF028).
--   7. Auditoría inmutable (SEG-003).
--   8. Fechas con zona horaria (review v6, M1).
--   9. Restricciones menores: textos vacíos, fechas, resultados de simulación.
--
-- Correcciones de la v7.1 (hallazgos de revision_fable/Validacion_SQL_SRS_v7.md):
--   * SQL-01: cruce.id_pareja y nidada.id_cruce no se pueden modificar.
--   * SQL-02: cria.id_canario y cria.id_nidada no se pueden modificar.
--   * SQL-03: el diagnóstico exige texto y fecha juntos; cerrar una emergencia
--     exige además las acciones de recuperación (sección 2.5).
--   * SQL-04: criador.id_usuario no se puede modificar y no se borra el
--     criadero de un usuario criador.
--   * Misma clase de defecto: pareja.id_criador y titulo.id_canario inmutables.
-- =====================================================================

BEGIN;

-- ---------- Zona horaria (review v6, M1) ----------
-- Los CHECK con CURRENT_DATE usan la zona de la sesión. Se fija para esta
-- sesión y, si el usuario es dueño de la base, para todas las siguientes.
SET timezone = 'America/Santiago';
DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I SET timezone = %L', current_database(), 'America/Santiago');
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'No se pudo fijar la zona horaria de la base: pídalo a su dueño (ALTER DATABASE ... SET timezone)';
END $$;

-- =====================================================================
-- FUNCIONES GENERALES DE TRIGGER
-- =====================================================================

-- Rechaza el cambio de una columna. El trigger que la usa indica la columna
-- en su argumento y en su cláusula WHEN.
CREATE FUNCTION fn_inmutable() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'La columna % de % no se puede modificar', TG_ARGV[0], TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;

-- Exige que el usuario indicado en una columna tenga cierto rol.
-- Argumentos del trigger: rol exigido y nombre de la columna. NULL se acepta.
CREATE FUNCTION fn_exigir_rol() RETURNS trigger AS $$
DECLARE
    v_id  INT := (to_jsonb(NEW) ->> TG_ARGV[1])::INT;
    v_rol VARCHAR(15);
BEGIN
    IF v_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT rol INTO v_rol FROM usuario WHERE id_usuario = v_id;
    IF v_rol IS DISTINCT FROM TG_ARGV[0] THEN
        RAISE EXCEPTION 'El usuario % debe tener el rol % (%.%)', v_id, TG_ARGV[0], TG_TABLE_NAME, TG_ARGV[1];
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- CUENTAS (SRS-RF026, SEG-001, SEG-002)
-- =====================================================================
CREATE TABLE usuario (
    id_usuario     SERIAL PRIMARY KEY,
    nombre         VARCHAR(100) NOT NULL CHECK (btrim(nombre) <> ''),
    -- Único sin distinguir mayúsculas: índice uq_usuario_correo_lower
    correo         VARCHAR(150) NOT NULL CHECK (correo ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
    password_hash  VARCHAR(255) NOT NULL,          -- password_hash() de PHP (bcrypt/Argon2)
    rol            VARCHAR(15)  NOT NULL CHECK (rol IN ('criador','administrador')),
    fecha_creacion TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX uq_usuario_correo_lower ON usuario (lower(correo));

-- El rol no cambia: de él dependen el criadero y los permisos (SEG-001)
CREATE TRIGGER trg_usuario_rol_inmutable
    BEFORE UPDATE OF rol ON usuario
    FOR EACH ROW WHEN (OLD.rol IS DISTINCT FROM NEW.rol)
    EXECUTE FUNCTION fn_inmutable('rol');

CREATE TABLE criador (
    id_criador     SERIAL PRIMARY KEY,
    id_usuario     INT NOT NULL UNIQUE REFERENCES usuario(id_usuario),
    numero_socio   VARCHAR(5) NOT NULL CHECK (numero_socio ~ '^[0-9]{1,5}$'),
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Solo un usuario con rol criador tiene criadero (tabla de permisos, 2.4)
CREATE TRIGGER trg_criador_rol
    BEFORE INSERT ON criador
    FOR EACH ROW EXECUTE FUNCTION fn_exigir_rol('criador', 'id_usuario');

-- Un criadero no cambia de cuenta: así el usuario anterior no queda sin él
-- (revisión SQL-04)
CREATE TRIGGER trg_criador_usuario_inmutable
    BEFORE UPDATE OF id_usuario ON criador
    FOR EACH ROW WHEN (OLD.id_usuario IS DISTINCT FROM NEW.id_usuario)
    EXECUTE FUNCTION fn_inmutable('id_usuario');

-- Toda cuenta de criador se crea con su criadero (SRS-RF026). Es diferido:
-- se revisa al hacer COMMIT, cuando la fila de criador ya existe, así que
-- usuario y criador se insertan en la misma transacción.
CREATE FUNCTION fn_validar_criadero() RETURNS trigger AS $$
BEGIN
    IF NEW.rol = 'criador'
       AND NOT EXISTS (SELECT 1 FROM criador WHERE id_usuario = NEW.id_usuario) THEN
        RAISE EXCEPTION 'El usuario criador % debe crearse junto con su criadero', NEW.id_usuario;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_validar_criadero
    AFTER INSERT ON usuario
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_validar_criadero();

-- Tampoco se borra el criadero de un usuario que sigue siendo criador
-- (revisión SQL-04). Diferido, igual que el anterior.
CREATE FUNCTION fn_validar_baja_criador() RETURNS trigger AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM usuario WHERE id_usuario = OLD.id_usuario AND rol = 'criador')
       AND NOT EXISTS (SELECT 1 FROM criador WHERE id_usuario = OLD.id_usuario) THEN
        RAISE EXCEPTION 'El usuario criador % no puede quedar sin criadero', OLD.id_usuario;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_validar_baja_criador
    AFTER DELETE ON criador
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_validar_baja_criador();

-- =====================================================================
-- CATALOGOS (SRS-RF002, SRS-RF007, SRS-RF010, SRS-RF011, SRS-RF027)
-- =====================================================================
CREATE TABLE club (
    id_club SERIAL PRIMARY KEY,
    sigla   VARCHAR(6) NOT NULL UNIQUE CHECK (sigla ~ '^[A-Z]{2,6}$')
);

CREATE TABLE variedad (
    id_variedad SERIAL PRIMARY KEY,
    codigo      VARCHAR(10)  NOT NULL UNIQUE CHECK (btrim(codigo) <> ''),
    nombre      VARCHAR(150) NOT NULL CHECK (btrim(nombre) <> ''),
    tipo        CHAR(2)      NOT NULL CHECK (tipo IN ('CC','CP')),
    serie       VARCHAR(50),
    -- Sexo indicado en el nombre (palabra MACHO o HEMBRA); NULL si no indica
    -- sexo (SRS-RF009). Lo calcula la base, no la carga del nomenclador, así
    -- nunca contradice al nombre.
    sexo        CHAR(1) GENERATED ALWAYS AS (
                    CASE WHEN nombre ~* '\mMACHO\M'  THEN 'M'
                         WHEN nombre ~* '\mHEMBRA\M' THEN 'H'
                    END) STORED
);

CREATE TABLE mutacion (
    id_mutacion   SERIAL PRIMARY KEY,
    nombre        VARCHAR(100) NOT NULL CHECK (btrim(nombre) <> ''),
    tipo_herencia VARCHAR(30)  NOT NULL
                  CHECK (tipo_herencia IN ('autosómica recesiva','ligada al sexo recesiva'))
);

-- Nombre único sin distinguir mayúsculas (SRS-RF027)
CREATE UNIQUE INDEX uq_mutacion_nombre_lower ON mutacion (lower(nombre));

-- =====================================================================
-- JAULA Y CANARIO (EJEMPLAR)
-- =====================================================================
CREATE TABLE jaula (
    id_jaula     SERIAL PRIMARY KEY,
    numero_jaula INT NOT NULL CHECK (numero_jaula >= 1),   -- SRS-RF012 (1 a 2.147.483.647)
    id_criador   INT NOT NULL REFERENCES criador(id_criador),
    CONSTRAINT uq_jaula_criador UNIQUE (id_criador, numero_jaula),
    -- Destino de las llaves compuestas que exigen "mismo criadero" (SEG-001)
    CONSTRAINT uq_jaula_id_criador UNIQUE (id_jaula, id_criador)
);

CREATE TRIGGER trg_jaula_criador_inmutable
    BEFORE UPDATE OF id_criador ON jaula
    FOR EACH ROW WHEN (OLD.id_criador IS DISTINCT FROM NEW.id_criador)
    EXECUTE FUNCTION fn_inmutable('id_criador');

CREATE TABLE canario (
    id_canario        SERIAL PRIMARY KEY,
    -- Anillo formato Chile (SRS-RF001, POL-001)
    anillo            VARCHAR(6) NOT NULL CHECK (anillo ~ '^[0-9]{1,6}$'),
    id_club           INT        NOT NULL REFERENCES club(id_club),
    numero_socio      VARCHAR(5) NOT NULL CHECK (numero_socio ~ '^[0-9]{1,5}$'),
    temporada         SMALLINT   NOT NULL CHECK (temporada BETWEEN 1000 AND 9999),
    -- Sexo y variedad: obligatorios salvo en una cría (SRS-RF004, SRS-RF007,
    -- SRS-RF020). Lo valida el trigger diferido trg_validar_pendiente_cria.
    sexo              CHAR(1) CHECK (sexo IN ('M','H')),
    id_variedad       INT REFERENCES variedad(id_variedad),
    id_criador        INT NOT NULL REFERENCES criador(id_criador),
    -- Lo calcula trg_validar_sexo_variedad: TRUE mientras el sexo no coincida
    -- con el de la variedad (SRS-RF010, SRS-RF032). No se escribe a mano.
    requiere_revision BOOLEAN     NOT NULL DEFAULT FALSE,
    fecha_registro    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Destino de las llaves compuestas que exigen "mismo criadero" (SEG-001)
    CONSTRAINT uq_canario_criador UNIQUE (id_canario, id_criador)
);

-- Anillo único en todo el sistema, en cualquier criadero (SRS-RF003, DAT-004,
-- IF-002). Se compara como número: '0005' y '5' son el mismo anillo.
CREATE UNIQUE INDEX uq_anillo
    ON canario ((anillo::INT), id_club, (numero_socio::INT), temporada);

CREATE TRIGGER trg_canario_criador_inmutable
    BEFORE UPDATE OF id_criador ON canario
    FOR EACH ROW WHEN (OLD.id_criador IS DISTINCT FROM NEW.id_criador)
    EXECUTE FUNCTION fn_inmutable('id_criador');

-- =====================================================================
-- PAREJA, CRUCE, NIDADA Y CRIA
-- =====================================================================
CREATE TABLE pareja (
    id_pareja        SERIAL PRIMARY KEY,
    id_criador       INT NOT NULL REFERENCES criador(id_criador),
    id_macho         INT NOT NULL,
    id_hembra        INT NOT NULL,
    id_jaula         INT NOT NULL,
    fecha_formacion  DATE NOT NULL DEFAULT CURRENT_DATE CHECK (fecha_formacion <= CURRENT_DATE),
    estado           VARCHAR(15) NOT NULL DEFAULT 'activa'
                     CHECK (estado IN ('activa','finalizada','anulada')),   -- SRS-RF017, SRS-RF031
    fecha_fin        DATE,
    -- Macho, hembra y jaula del mismo criadero que la pareja (SEG-001)
    CONSTRAINT fk_pareja_macho  FOREIGN KEY (id_macho,  id_criador) REFERENCES canario (id_canario, id_criador),
    CONSTRAINT fk_pareja_hembra FOREIGN KEY (id_hembra, id_criador) REFERENCES canario (id_canario, id_criador),
    CONSTRAINT fk_pareja_jaula  FOREIGN KEY (id_jaula,  id_criador) REFERENCES jaula   (id_jaula,   id_criador),
    CONSTRAINT ck_pareja_distintos CHECK (id_macho <> id_hembra),
    CONSTRAINT ck_pareja_fin CHECK (
        (estado = 'activa' AND fecha_fin IS NULL) OR
        (estado <> 'activa' AND fecha_fin IS NOT NULL AND fecha_fin >= fecha_formacion))
);

-- Una hembra solo puede tener una pareja activa (SRS-RF015, DAT-004)
CREATE UNIQUE INDEX uq_pareja_hembra_activa ON pareja(id_hembra) WHERE estado = 'activa';
-- Una jaula solo puede tener una pareja activa (SRS-RF014, DAT-004)
CREATE UNIQUE INDEX uq_pareja_jaula_activa  ON pareja(id_jaula)  WHERE estado = 'activa';

-- Una pareja no cambia de criadero: arrastraría sus cruces, nidadas y crías
CREATE TRIGGER trg_pareja_criador_inmutable
    BEFORE UPDATE OF id_criador ON pareja
    FOR EACH ROW WHEN (OLD.id_criador IS DISTINCT FROM NEW.id_criador)
    EXECUTE FUNCTION fn_inmutable('id_criador');

CREATE TABLE cruce (
    id_cruce    SERIAL PRIMARY KEY,
    id_pareja   INT  NOT NULL REFERENCES pareja(id_pareja),
    fecha_cruce DATE NOT NULL CHECK (fecha_cruce <= CURRENT_DATE)       -- SRS-RF016
);

-- Un cruce no cambia de pareja: cambiaría el padre y la madre de sus crías
-- sin pasar por las validaciones de cria (revisión SQL-01). Para corregir
-- un progenitor se reasigna la pareja (SRS-RF031), no el cruce.
CREATE TRIGGER trg_cruce_pareja_inmutable
    BEFORE UPDATE OF id_pareja ON cruce
    FOR EACH ROW WHEN (OLD.id_pareja IS DISTINCT FROM NEW.id_pareja)
    EXECUTE FUNCTION fn_inmutable('id_pareja');

CREATE TABLE nidada (
    id_nidada        SERIAL PRIMARY KEY,
    id_cruce         INT  NOT NULL REFERENCES cruce(id_cruce),
    fecha_nacimiento DATE NOT NULL CHECK (fecha_nacimiento <= CURRENT_DATE)  -- SRS-RF018
);

-- Una nidada no cambia de cruce, por la misma razón (revisión SQL-01)
CREATE TRIGGER trg_nidada_cruce_inmutable
    BEFORE UPDATE OF id_cruce ON nidada
    FOR EACH ROW WHEN (OLD.id_cruce IS DISTINCT FROM NEW.id_cruce)
    EXECUTE FUNCTION fn_inmutable('id_cruce');

CREATE TABLE cria (
    id_cria         SERIAL PRIMARY KEY,
    id_canario      INT NOT NULL UNIQUE REFERENCES canario(id_canario),
    id_nidada       INT NOT NULL REFERENCES nidada(id_nidada),
    -- Factor del que es portadora; NULL = no es portadora (SRS-RF021)
    factor_genetico INT REFERENCES mutacion(id_mutacion),
    -- Marca de portadora: se deriva del factor, no se escribe a mano
    es_portadora    BOOLEAN GENERATED ALWAYS AS (factor_genetico IS NOT NULL) STORED,
    reservada       BOOLEAN NOT NULL DEFAULT FALSE                   -- SRS-RF021
);

-- Una fila de cria no cambia de ejemplar ni de nidada: el ejemplar anterior
-- quedaría sin sexo ni variedad y sin ser cría (revisión SQL-02), y la cría
-- cambiaría de padres sin validarse (revisión SQL-01)
CREATE TRIGGER trg_cria_canario_inmutable
    BEFORE UPDATE OF id_canario ON cria
    FOR EACH ROW WHEN (OLD.id_canario IS DISTINCT FROM NEW.id_canario)
    EXECUTE FUNCTION fn_inmutable('id_canario');

CREATE TRIGGER trg_cria_nidada_inmutable
    BEFORE UPDATE OF id_nidada ON cria
    FOR EACH ROW WHEN (OLD.id_nidada IS DISTINCT FROM NEW.id_nidada)
    EXECUTE FUNCTION fn_inmutable('id_nidada');

-- =====================================================================
-- TITULOS Y SOLICITUDES DE CORRECCION
-- =====================================================================
CREATE TABLE titulo (
    id_titulo  SERIAL PRIMARY KEY,
    id_canario INT          NOT NULL REFERENCES canario(id_canario),
    nombre     VARCHAR(100) NOT NULL CHECK (btrim(nombre) <> ''),    -- SRS-RF023
    fecha      DATE         NOT NULL CHECK (fecha <= CURRENT_DATE),
    CONSTRAINT uq_titulo UNIQUE (id_canario, nombre, fecha)
);

-- Un título no cambia de ejemplar (SRS-RF023)
CREATE TRIGGER trg_titulo_canario_inmutable
    BEFORE UPDATE OF id_canario ON titulo
    FOR EACH ROW WHEN (OLD.id_canario IS DISTINCT FROM NEW.id_canario)
    EXECUTE FUNCTION fn_inmutable('id_canario');

CREATE TABLE solicitud_correccion (
    id_solicitud    SERIAL PRIMARY KEY,
    id_canario      INT NOT NULL,
    id_criador      INT NOT NULL REFERENCES criador(id_criador),     -- quien solicita
    dato_a_corregir VARCHAR(10) NOT NULL CHECK (dato_a_corregir IN ('sexo','variedad')),
    motivo          TEXT NOT NULL CHECK (btrim(motivo) <> ''),       -- SRS-RF033
    estado          VARCHAR(15) NOT NULL DEFAULT 'pendiente'
                    CHECK (estado IN ('pendiente','aprobada','rechazada','cancelada')),
    fecha_solicitud TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_cierre    TIMESTAMPTZ,
    -- Solo el dueño del ejemplar puede pedir su corrección (SEG-001, SRS-RF033)
    CONSTRAINT fk_solicitud_canario FOREIGN KEY (id_canario, id_criador)
        REFERENCES canario (id_canario, id_criador),
    CONSTRAINT ck_solicitud_cierre CHECK ((estado = 'pendiente') = (fecha_cierre IS NULL)),
    CONSTRAINT ck_solicitud_fechas CHECK (fecha_cierre IS NULL OR fecha_cierre >= fecha_solicitud)
);

-- Una sola solicitud pendiente por ejemplar
CREATE UNIQUE INDEX uq_solicitud_pendiente ON solicitud_correccion(id_canario)
    WHERE estado = 'pendiente';

-- =====================================================================
-- SIMULACION GENETICA (SRS-RF025, DAT-006)
-- =====================================================================
CREATE TABLE simulacion (
    id_simulacion   SERIAL PRIMARY KEY,
    id_criador      INT NOT NULL REFERENCES criador(id_criador),
    id_macho        INT NOT NULL,
    id_hembra       INT NOT NULL,
    id_mutacion     INT NOT NULL REFERENCES mutacion(id_mutacion),
    genotipo_macho  VARCHAR(10) NOT NULL CHECK (genotipo_macho  IN ('visual','portador','sin factor')),
    genotipo_hembra VARCHAR(10) NOT NULL CHECK (genotipo_hembra IN ('visual','portador','sin factor')),
    fecha           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Macho y hembra del criadero que simula (SEG-001)
    CONSTRAINT fk_simulacion_macho  FOREIGN KEY (id_macho,  id_criador) REFERENCES canario (id_canario, id_criador),
    CONSTRAINT fk_simulacion_hembra FOREIGN KEY (id_hembra, id_criador) REFERENCES canario (id_canario, id_criador),
    CONSTRAINT ck_simulacion_distintos CHECK (id_macho <> id_hembra)
    -- Sexos y "portador" en hembra con mutación ligada al sexo: trg_validar_simulacion
);

CREATE TABLE simulacion_resultado (
    id_resultado       SERIAL PRIMARY KEY,
    id_simulacion      INT NOT NULL REFERENCES simulacion(id_simulacion) ON DELETE CASCADE,
    sexo_cria          CHAR(1) CHECK (sexo_cria IN ('M','H')),        -- NULL en autosómica
    genotipo_resultado VARCHAR(10) NOT NULL
                       CHECK (genotipo_resultado IN ('visual','portador','sin factor')),
    probabilidad       NUMERIC(6,5) NOT NULL CHECK (probabilidad BETWEEN 0 AND 1),
    -- Una fila por resultado; el NULL de sexo_cria también cuenta como valor
    CONSTRAINT uq_simulacion_resultado UNIQUE NULLS NOT DISTINCT (id_simulacion, sexo_cria, genotipo_resultado),
    -- Con sexo indicado la herencia es ligada al sexo: la hembra no es portadora (DAT-006)
    CONSTRAINT ck_resultado_hembra CHECK (NOT (sexo_cria = 'H' AND genotipo_resultado = 'portador'))
);

-- =====================================================================
-- ADMINISTRACION: AUDITORIA, RESPALDO Y MODO DE OPERACION
-- =====================================================================
CREATE TABLE auditoria (
    id_auditoria           BIGSERIAL PRIMARY KEY,
    id_usuario             INT REFERENCES usuario(id_usuario),      -- quien ejecuta
    fecha_hora             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    accion                 VARCHAR(50) NOT NULL CHECK (btrim(accion) <> ''),  -- login, logout, insert, update, correccion...
    entidad                VARCHAR(50),
    id_registro            INT,
    valor_anterior         TEXT,
    valor_nuevo            TEXT,
    motivo                 TEXT,
    id_criador_solicitante INT REFERENCES criador(id_criador),      -- corrección delegada (SRS-RF030)
    id_solicitud           INT REFERENCES solicitud_correccion(id_solicitud)
    -- Nunca se registran contraseñas (SEG-003)
);

-- La auditoría solo se agrega: no se modifica ni se borra (SEG-003)
CREATE FUNCTION fn_auditoria_inmutable() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'La auditoría no se puede modificar ni borrar';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auditoria_inmutable
    BEFORE UPDATE OR DELETE ON auditoria
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_inmutable();

CREATE TABLE respaldo (
    id_respaldo SERIAL PRIMARY KEY,
    fecha_hora  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    archivo     VARCHAR(255) NOT NULL UNIQUE CHECK (btrim(archivo) <> ''),
    id_usuario  INT REFERENCES usuario(id_usuario)                  -- NULL = respaldo automático
);

CREATE TRIGGER trg_respaldo_rol
    BEFORE INSERT OR UPDATE OF id_usuario ON respaldo
    FOR EACH ROW EXECUTE FUNCTION fn_exigir_rol('administrador', 'id_usuario');

-- Modo normal = no hay ningún modo activo (DAT-003, SRS-RF028, sección 2.5)
CREATE TABLE modo_operacion (
    id_modo               SERIAL PRIMARY KEY,
    modo                  VARCHAR(15) NOT NULL CHECK (modo IN ('mantenimiento','emergencia')),
    fecha_activacion      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_desactivacion   TIMESTAMPTZ,
    id_usuario            INT NOT NULL REFERENCES usuario(id_usuario),   -- quien lo activa
    id_usuario_cierre     INT REFERENCES usuario(id_usuario),            -- quien lo desactiva
    diagnostico           TEXT,
    fecha_diagnostico     TIMESTAMPTZ,                              -- plazo de 4 horas en emergencia
    acciones_recuperacion TEXT,
    CONSTRAINT ck_modo_fechas CHECK (fecha_desactivacion IS NULL OR fecha_desactivacion >= fecha_activacion),
    CONSTRAINT ck_modo_cierre CHECK ((fecha_desactivacion IS NULL) = (id_usuario_cierre IS NULL)),
    -- El diagnóstico va con su fecha, y no es anterior a la activación. Los
    -- IS NOT NULL son necesarios: un CHECK solo rechaza FALSE, y una
    -- comparación con NULL da NULL (revisión SQL-03).
    CONSTRAINT ck_modo_diagnostico CHECK (
        (diagnostico IS NULL AND fecha_diagnostico IS NULL) OR
        (diagnostico IS NOT NULL AND fecha_diagnostico IS NOT NULL
         AND btrim(diagnostico) <> '' AND fecha_diagnostico >= fecha_activacion)),
    CONSTRAINT ck_modo_acciones CHECK (acciones_recuperacion IS NULL OR btrim(acciones_recuperacion) <> ''),
    -- Una emergencia no vuelve a modo normal sin su diagnóstico ni sus
    -- acciones de recuperación (sección 2.5, DAT-003). No se exige el plazo
    -- de 4 horas: una evaluación tardía igual debe poder registrarse.
    CONSTRAINT ck_modo_emergencia CHECK (
        modo <> 'emergencia' OR fecha_desactivacion IS NULL
        OR (diagnostico IS NOT NULL AND acciones_recuperacion IS NOT NULL))
);

-- Solo un modo especial activo a la vez
CREATE UNIQUE INDEX uq_modo_activo ON modo_operacion ((TRUE)) WHERE fecha_desactivacion IS NULL;

-- Solo el administrador activa y desactiva los modos (SRS-RF028)
CREATE TRIGGER trg_modo_rol_activa
    BEFORE INSERT OR UPDATE OF id_usuario ON modo_operacion
    FOR EACH ROW EXECUTE FUNCTION fn_exigir_rol('administrador', 'id_usuario');

CREATE TRIGGER trg_modo_rol_cierra
    BEFORE INSERT OR UPDATE OF id_usuario_cierre ON modo_operacion
    FOR EACH ROW EXECUTE FUNCTION fn_exigir_rol('administrador', 'id_usuario_cierre');

-- =====================================================================
-- TRIGGERS DE REGLAS DE NEGOCIO
-- =====================================================================

-- Pareja, ciclo de vida: nace activa; una pareja finalizada o anulada no
-- cambia de estado; una pareja con cruces no se anula, se reasigna
-- (SRS-RF017, SRS-RF031).
CREATE FUNCTION fn_estado_pareja() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.estado <> 'activa' THEN
        RAISE EXCEPTION 'Toda pareja se crea en estado activa';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.estado <> 'activa' AND NEW.estado <> OLD.estado THEN
        RAISE EXCEPTION 'Una pareja % no puede cambiar de estado', OLD.estado;
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.estado = 'anulada' AND OLD.estado <> 'anulada'
       AND EXISTS (SELECT 1 FROM cruce WHERE id_pareja = NEW.id_pareja) THEN
        RAISE EXCEPTION 'Una pareja con cruces no se anula: se reasigna';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_estado_pareja
    BEFORE INSERT OR UPDATE OF estado ON pareja
    FOR EACH ROW EXECUTE FUNCTION fn_estado_pareja();

-- Pareja: macho y hembra con sexo correcto, máximo 6 parejas activas por
-- macho, y ninguno de los dos puede ser cría de esta misma pareja
-- (SRS-RF012, SRS-RF013, SRS-RF022). El "mismo criadero" lo garantizan las
-- llaves compuestas de la tabla.
CREATE FUNCTION fn_validar_pareja() RETURNS trigger AS $$
DECLARE
    v_sexo_m  CHAR(1);
    v_sexo_h  CHAR(1);
    v_activas INT;
BEGIN
    -- Bloquea al macho para evitar dos inserciones simultáneas que superen el máximo
    SELECT sexo INTO v_sexo_m FROM canario WHERE id_canario = NEW.id_macho FOR UPDATE;
    SELECT sexo INTO v_sexo_h FROM canario WHERE id_canario = NEW.id_hembra;

    IF v_sexo_m IS DISTINCT FROM 'M' THEN
        RAISE EXCEPTION 'El ejemplar % no está registrado como macho', NEW.id_macho;
    END IF;
    IF v_sexo_h IS DISTINCT FROM 'H' THEN
        RAISE EXCEPTION 'El ejemplar % no está registrado como hembra', NEW.id_hembra;
    END IF;

    IF NEW.estado = 'activa' THEN
        SELECT COUNT(*) INTO v_activas
          FROM pareja
         WHERE id_macho = NEW.id_macho
           AND estado = 'activa'
           AND id_pareja <> COALESCE(NEW.id_pareja, -1);
        IF v_activas >= 6 THEN
            RAISE EXCEPTION 'El macho ya tiene el máximo de 6 parejas activas';
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' AND EXISTS (
            SELECT 1
              FROM cruce  c
              JOIN nidada n  ON n.id_cruce   = c.id_cruce
              JOIN cria   cr ON cr.id_nidada = n.id_nidada
             WHERE c.id_pareja = NEW.id_pareja
               AND cr.id_canario IN (NEW.id_macho, NEW.id_hembra)) THEN
        RAISE EXCEPTION 'Un ejemplar no puede ser padre o madre en la pareja de la que es cría';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_pareja
    BEFORE INSERT OR UPDATE OF id_macho, id_hembra, id_jaula, estado ON pareja
    FOR EACH ROW EXECUTE FUNCTION fn_validar_pareja();

-- Cruce: solo sobre una pareja activa, y nunca posterior al nacimiento de
-- sus nidadas (SRS-RF016, SRS-RF018)
CREATE FUNCTION fn_validar_cruce() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT'
       AND NOT EXISTS (SELECT 1 FROM pareja WHERE id_pareja = NEW.id_pareja AND estado = 'activa') THEN
        RAISE EXCEPTION 'Solo se puede registrar un cruce en una pareja activa';
    END IF;
    IF TG_OP = 'UPDATE'
       AND EXISTS (SELECT 1 FROM nidada
                    WHERE id_cruce = NEW.id_cruce AND fecha_nacimiento < NEW.fecha_cruce) THEN
        RAISE EXCEPTION 'La fecha del cruce no puede ser posterior al nacimiento de sus nidadas';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_cruce
    BEFORE INSERT OR UPDATE OF fecha_cruce ON cruce
    FOR EACH ROW EXECUTE FUNCTION fn_validar_cruce();

-- Nidada: fecha de nacimiento no anterior a la fecha del cruce (SRS-RF018)
CREATE FUNCTION fn_validar_nidada() RETURNS trigger AS $$
DECLARE v_fecha_cruce DATE;
BEGIN
    SELECT fecha_cruce INTO v_fecha_cruce FROM cruce WHERE id_cruce = NEW.id_cruce;
    IF NEW.fecha_nacimiento < v_fecha_cruce THEN
        RAISE EXCEPTION 'La fecha de nacimiento (%) es anterior a la fecha del cruce (%)',
            NEW.fecha_nacimiento, v_fecha_cruce;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_nidada
    BEFORE INSERT OR UPDATE OF fecha_nacimiento ON nidada
    FOR EACH ROW EXECUTE FUNCTION fn_validar_nidada();

-- Canario: coherencia entre el sexo del ejemplar y el de su variedad
-- (SRS-RF009, SRS-RF010, SRS-RF032).
--   * Si se registra o cambia el sexo o la variedad, deben coincidir.
--   * Si no cambian (por ejemplo, un formulario que reescribe todas las
--     columnas), no se rechaza: el ejemplar puede estar en «Requiere revisión».
--   * requiere_revision se calcula aquí: TRUE mientras no coincidan. No se
--     puede retirar la marca a mano.
CREATE FUNCTION fn_validar_sexo_variedad() RETURNS trigger AS $$
DECLARE
    v_sexo_var  CHAR(1);
    v_coherente BOOLEAN;
    v_cambia    BOOLEAN;
BEGIN
    IF NEW.id_variedad IS NOT NULL THEN
        SELECT sexo INTO v_sexo_var FROM variedad WHERE id_variedad = NEW.id_variedad;
    END IF;
    v_coherente := NEW.sexo IS NULL OR v_sexo_var IS NULL OR v_sexo_var = NEW.sexo;
    v_cambia := TG_OP = 'INSERT'
             OR NEW.sexo IS DISTINCT FROM OLD.sexo
             OR NEW.id_variedad IS DISTINCT FROM OLD.id_variedad;

    IF v_cambia AND NOT v_coherente THEN
        RAISE EXCEPTION 'El sexo del ejemplar no coincide con el sexo de la variedad';
    END IF;
    IF NOT v_cambia AND NOT v_coherente AND NOT NEW.requiere_revision THEN
        RAISE EXCEPTION 'La marca «Requiere revisión» solo se retira cuando el sexo y la variedad coinciden';
    END IF;
    NEW.requiere_revision := NOT v_coherente;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_sexo_variedad
    BEFORE INSERT OR UPDATE OF sexo, id_variedad, requiere_revision ON canario
    FOR EACH ROW EXECUTE FUNCTION fn_validar_sexo_variedad();

-- Variedad: si la carga del nomenclador cambia el sexo indicado en el nombre,
-- los ejemplares que dejan de coincidir quedan en «Requiere revisión», sin
-- modificarse ni eliminarse (SRS-RF010). La carga informa cuántos quedaron
-- con: SELECT count(*) FROM canario WHERE requiere_revision.
CREATE FUNCTION fn_marcar_revision() RETURNS trigger AS $$
BEGIN
    IF NEW.sexo IS DISTINCT FROM OLD.sexo THEN
        UPDATE canario
           SET requiere_revision = (NEW.sexo IS NOT NULL AND sexo <> NEW.sexo)
         WHERE id_variedad = NEW.id_variedad
           AND sexo IS NOT NULL;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_marcar_revision
    AFTER UPDATE OF nombre ON variedad
    FOR EACH ROW EXECUTE FUNCTION fn_marcar_revision();

-- Canario: no se corrige el sexo mientras el ejemplar siga en una pareja no
-- anulada; el Modo de Corrección primero reasigna o anula sus parejas en la
-- misma transacción (SRS-RF031). Asignar el sexo por primera vez a una cría
-- (antes NULL) sí se permite (SRS-RF020).
CREATE FUNCTION fn_validar_cambio_sexo() RETURNS trigger AS $$
BEGIN
    IF OLD.sexo IS NOT NULL AND NEW.sexo IS DISTINCT FROM OLD.sexo
       AND EXISTS (SELECT 1 FROM pareja
                    WHERE (id_macho = NEW.id_canario OR id_hembra = NEW.id_canario)
                      AND estado <> 'anulada') THEN
        RAISE EXCEPTION 'El ejemplar % participa en parejas: reasígnelas o anúlelas antes de corregir el sexo',
            NEW.id_canario;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_cambio_sexo
    BEFORE UPDATE OF sexo ON canario
    FOR EACH ROW EXECUTE FUNCTION fn_validar_cambio_sexo();

-- Canario: solo una cría puede quedar sin sexo o sin variedad (SRS-RF004,
-- SRS-RF007, SRS-RF020). Es diferido: se revisa al hacer COMMIT, cuando la
-- fila de cria ya existe. También se revisa al borrar una fila de cria.
CREATE FUNCTION fn_validar_pendiente_cria() RETURNS trigger AS $$
DECLARE v_id INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_id := OLD.id_canario;
    ELSE
        v_id := NEW.id_canario;
    END IF;
    -- Se lee la fila vigente, que pudo cambiar después en la misma transacción
    IF EXISTS (SELECT 1 FROM canario c
                WHERE c.id_canario = v_id
                  AND (c.sexo IS NULL OR c.id_variedad IS NULL)
                  AND NOT EXISTS (SELECT 1 FROM cria WHERE cria.id_canario = c.id_canario)) THEN
        RAISE EXCEPTION 'Solo una cría puede quedar sin sexo o sin variedad (ejemplar %)', v_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_validar_pendiente_cria
    AFTER INSERT OR UPDATE OF sexo, id_variedad ON canario
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_validar_pendiente_cria();

CREATE CONSTRAINT TRIGGER trg_validar_baja_cria
    AFTER DELETE ON cria
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_validar_pendiente_cria();

-- Cría: debe ser del mismo criadero que la pareja de su nidada (SEG-001) y
-- no puede ser el macho ni la hembra de esa pareja (SRS-RF022)
CREATE FUNCTION fn_validar_cria() RETURNS trigger AS $$
DECLARE
    v_crit_cria INT;
    v_pareja    pareja%ROWTYPE;
BEGIN
    SELECT id_criador INTO v_crit_cria FROM canario WHERE id_canario = NEW.id_canario;
    SELECT p.* INTO v_pareja
      FROM nidada n
      JOIN cruce  c ON c.id_cruce  = n.id_cruce
      JOIN pareja p ON p.id_pareja = c.id_pareja
     WHERE n.id_nidada = NEW.id_nidada;
    IF v_crit_cria IS DISTINCT FROM v_pareja.id_criador THEN
        RAISE EXCEPTION 'La cría y la nidada deben pertenecer al mismo criadero';
    END IF;
    IF NEW.id_canario IN (v_pareja.id_macho, v_pareja.id_hembra) THEN
        RAISE EXCEPTION 'Un ejemplar no puede ser cría de su propia pareja';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_cria
    BEFORE INSERT ON cria
    FOR EACH ROW EXECUTE FUNCTION fn_validar_cria();

-- Simulación: un macho y una hembra; la hembra no puede ser portadora en
-- herencia ligada al sexo (SRS-RF025, DAT-006). El "mismo criadero" lo
-- garantizan las llaves compuestas de la tabla.
CREATE FUNCTION fn_validar_simulacion() RETURNS trigger AS $$
DECLARE
    v_sexo_m CHAR(1);
    v_sexo_h CHAR(1);
    v_tipo   VARCHAR(30);
BEGIN
    SELECT sexo INTO v_sexo_m FROM canario WHERE id_canario = NEW.id_macho;
    SELECT sexo INTO v_sexo_h FROM canario WHERE id_canario = NEW.id_hembra;
    SELECT tipo_herencia INTO v_tipo FROM mutacion WHERE id_mutacion = NEW.id_mutacion;

    IF v_sexo_m IS DISTINCT FROM 'M' OR v_sexo_h IS DISTINCT FROM 'H' THEN
        RAISE EXCEPTION 'La simulación requiere un macho y una hembra';
    END IF;
    IF v_tipo = 'ligada al sexo recesiva' AND NEW.genotipo_hembra = 'portador' THEN
        RAISE EXCEPTION 'Una hembra no puede ser portadora de una mutación ligada al sexo';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_simulacion
    BEFORE INSERT OR UPDATE ON simulacion
    FOR EACH ROW EXECUTE FUNCTION fn_validar_simulacion();

-- =====================================================================
-- VISTAS
-- =====================================================================

-- Genealogía: padre, madre y cuatro abuelos a partir de cría -> nidada ->
-- cruce -> pareja (SRS-RF022). NULL = "No registrado" en la interfaz.
-- NOT MATERIALIZED deja que el filtro por ejemplar use los índices en vez de
-- recorrer todas las crías del sistema en cada consulta.
CREATE VIEW v_genealogia AS
WITH padres AS NOT MATERIALIZED (
    SELECT cr.id_canario, p.id_macho AS id_padre, p.id_hembra AS id_madre
      FROM cria   cr
      JOIN nidada n ON n.id_nidada = cr.id_nidada
      JOIN cruce  c ON c.id_cruce  = n.id_cruce
      JOIN pareja p ON p.id_pareja = c.id_pareja
)
SELECT ca.id_canario,
       ca.id_criador,
       pa.id_padre,
       pa.id_madre,
       pp.id_padre AS id_abuelo_paterno,
       pp.id_madre AS id_abuela_paterna,
       pm.id_padre AS id_abuelo_materno,
       pm.id_madre AS id_abuela_materna
  FROM canario ca
  LEFT JOIN padres pa ON pa.id_canario = ca.id_canario
  LEFT JOIN padres pp ON pp.id_canario = pa.id_padre
  LEFT JOIN padres pm ON pm.id_canario = pa.id_madre;

-- =====================================================================
-- INDICES EN LLAVES FORANEAS
-- (las columnas con UNIQUE ya tienen índice y no se repiten)
-- =====================================================================
CREATE INDEX idx_jaula_criador            ON jaula(id_criador);
CREATE INDEX idx_canario_club             ON canario(id_club);
CREATE INDEX idx_canario_variedad         ON canario(id_variedad);
CREATE INDEX idx_canario_criador          ON canario(id_criador);
CREATE INDEX idx_pareja_criador           ON pareja(id_criador);
CREATE INDEX idx_pareja_macho             ON pareja(id_macho);
CREATE INDEX idx_pareja_jaula             ON pareja(id_jaula);
CREATE INDEX idx_pareja_hembra            ON pareja(id_hembra);
CREATE INDEX idx_cruce_pareja             ON cruce(id_pareja);
CREATE INDEX idx_nidada_cruce             ON nidada(id_cruce);
CREATE INDEX idx_cria_nidada              ON cria(id_nidada);
CREATE INDEX idx_cria_mutacion            ON cria(factor_genetico);
CREATE INDEX idx_solicitud_canario        ON solicitud_correccion(id_canario);
CREATE INDEX idx_solicitud_criador        ON solicitud_correccion(id_criador);
CREATE INDEX idx_simulacion_criador       ON simulacion(id_criador);
CREATE INDEX idx_simulacion_macho         ON simulacion(id_macho);
CREATE INDEX idx_simulacion_hembra        ON simulacion(id_hembra);
CREATE INDEX idx_simulacion_mutacion      ON simulacion(id_mutacion);
CREATE INDEX idx_auditoria_usuario        ON auditoria(id_usuario);
CREATE INDEX idx_auditoria_criador        ON auditoria(id_criador_solicitante);
CREATE INDEX idx_auditoria_solicitud      ON auditoria(id_solicitud);
CREATE INDEX idx_auditoria_fecha          ON auditoria(fecha_hora);
CREATE INDEX idx_respaldo_usuario         ON respaldo(id_usuario);
CREATE INDEX idx_modo_usuario             ON modo_operacion(id_usuario);
CREATE INDEX idx_modo_usuario_cierre      ON modo_operacion(id_usuario_cierre);

-- =====================================================================
-- DATOS SEMILLA
-- =====================================================================
-- Siglas iniciales de club (SRS-RF002)
INSERT INTO club (sigla) VALUES ('CON'), ('COV'), ('COR'), ('SOCH');

COMMIT;

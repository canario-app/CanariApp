-- Pruebas de reglas del esquema v7.1.
-- Se ejecutan sobre una base recién creada con reset_dev_v7_1.sql + canarios_v7_1.sql
-- (los datos base suponen ids nuevos: 1, 2, 3...). Un INSERT rechazado también
-- consume un id, así que las nidadas y los cruces se buscan con min()/max().
--
-- Cada caso imprime OK o FALLA. Al final el script termina con error si hubo
-- alguna FALLA, así que con -v ON_ERROR_STOP=1 el código de salida de psql sí
-- refleja el resultado (revisión SQL-05).
\set QUIET on
\set ON_ERROR_STOP on
SET client_min_messages = notice;

-- Datos base: 2 criadores y 1 administrador, variedades, mutaciones, jaulas, canarios.
-- Usuario y criador van en la misma transacción (trg_validar_criadero, SRS-RF026).
BEGIN;
INSERT INTO usuario (nombre, correo, password_hash, rol) VALUES
 ('Criador A','a@x.cl','h','criador'), ('Criador B','b@x.cl','h','criador'),
 ('Admin','admin@x.cl','h','administrador');                 -- ids 1, 2, 3
INSERT INTO criador (id_usuario, numero_socio) VALUES (1,'123'), (2,'456');
COMMIT;
-- El sexo de la variedad lo calcula la base a partir del nombre
INSERT INTO variedad (codigo,nombre,tipo) VALUES
 ('D.001','BLANCO','CC'), ('D.007','AMARILLO MOSAICO MACHO','CC');   -- ids 1, 2
INSERT INTO mutacion (nombre,tipo_herencia) VALUES
 ('Ágata','ligada al sexo recesiva'), ('Ópalo','autosómica recesiva'); -- ids 1, 2
INSERT INTO jaula (numero_jaula,id_criador) SELECT g,1 FROM generate_series(1,10) g;
INSERT INTO jaula (numero_jaula,id_criador) VALUES (1,2);   -- id_jaula 11, criador B
-- canarios criador A: 1 macho (id 1), 8 hembras (id 2..9)
INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador)
 VALUES ('1',4,'123',2026,'M',1,1);
INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador)
 SELECT (g+1)::text,4,'123',2026,'H',1,1 FROM generate_series(1,8) g;
-- canario criador B: hembra id 10
INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador)
 VALUES ('900',4,'456',2026,'H',1,2);
-- canario criador A: macho id 11 con una variedad que indica MACHO
INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador)
 VALUES ('50',4,'123',2026,'M',2,1);

-- ---------------------------------------------------------------------
-- t(nombre, espera, sql)
--   espera = 'OK'               el caso debe aceptarse
--   espera = 'SQLSTATE:texto'   el caso debe rechazarse con ese código de
--                               error y con ese texto en el mensaje (el
--                               nombre de la restricción o parte del mensaje
--                               del trigger). Así un rechazo por otra causa
--                               cuenta como FALLA.
-- Si un caso que debía rechazarse se acepta, se deshace para no alterar los
-- casos siguientes.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS t(text, text, text);
DROP TABLE IF EXISTS resultado_pruebas;
CREATE TABLE resultado_pruebas (n SERIAL PRIMARY KEY, nombre TEXT, ok BOOLEAN, detalle TEXT);

CREATE FUNCTION t(nombre text, espera text, sql text) RETURNS void AS $$
DECLARE
  v_estado text := split_part(espera, ':', 1);
  v_texto  text := substr(espera, length(v_estado) + 2);
  v_ok     boolean;
  v_det    text := '';
BEGIN
  BEGIN
    EXECUTE sql;
    -- Revisa ya los triggers diferidos para que su error quede dentro del caso
    SET CONSTRAINTS ALL IMMEDIATE;
    IF espera <> 'OK' THEN
      RAISE EXCEPTION USING ERRCODE = 'TEST0', MESSAGE = 'aceptado';   -- deshace el caso
    END IF;
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'TEST0' THEN
      v_ok := false; v_det := 'se aceptó y debía rechazarse con ' || espera;
    ELSIF espera = 'OK' THEN
      v_ok := false; v_det := 'se rechazó y debía aceptarse -> [' || SQLSTATE || '] ' || SQLERRM;
    ELSIF SQLSTATE = v_estado AND position(v_texto IN SQLERRM) > 0 THEN
      v_ok := true;  v_det := '-> [' || SQLSTATE || '] ' || SQLERRM;
    ELSE
      v_ok := false; v_det := 'se rechazó por otra causa (se esperaba ' || espera || ') -> [' || SQLSTATE || '] ' || SQLERRM;
    END IF;
  END;
  INSERT INTO resultado_pruebas (nombre, ok, detalle) VALUES (nombre, v_ok, v_det);
  RAISE NOTICE '%  % %', CASE WHEN v_ok THEN 'OK    ' ELSE 'FALLA ' END, nombre, v_det;
END $$ LANGUAGE plpgsql;

-- ---------- Anillo ----------
SELECT t('RF003 anillo duplicado', '23505:uq_anillo',
 $q$INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador) VALUES ('1',4,'123',2026,'M',1,1)$q$);
SELECT t('RF003 mismo anillo en otro criadero', '23505:uq_anillo',
 $q$INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador) VALUES ('1',4,'123',2026,'M',1,2)$q$);
SELECT t('RF003 mismo anillo con ceros a la izquierda', '23505:uq_anillo',
 $q$INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador) VALUES ('0001',4,'0123',2026,'M',1,1)$q$);
SELECT t('RF003 mismo número de anillo en otra temporada', 'OK',
 $q$INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador) VALUES ('1',4,'123',2025,'M',1,1)$q$);
SELECT t('RF001 anillo con letras', '23514:canario_anillo_check',
 $q$INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador) VALUES ('12A',4,'123',2026,'M',1,1)$q$);
SELECT t('RF001 anillo de 7 dígitos', '22001:',
 $q$INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador) VALUES ('1234567',4,'123',2026,'M',1,1)$q$);
SELECT t('RF001 socio con 6 dígitos', '22001:',
 $q$INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador) VALUES ('77',4,'123456',2026,'M',1,1)$q$);
SELECT t('RF001 temporada de 2 dígitos', '23514:canario_temporada_check',
 $q$INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador) VALUES ('77',4,'123',26,'M',1,1)$q$);
SELECT t('RF002 club inexistente', '23503:canario_id_club_fkey',
 $q$INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador) VALUES ('77',99,'123',2026,'M',1,1)$q$);
SELECT t('RF011 sigla en minúsculas', '23514:club_sigla_check', $q$INSERT INTO club (sigla) VALUES ('soch2')$q$);
SELECT t('RF011 sigla duplicada', '23505:club_sigla_key', $q$INSERT INTO club (sigla) VALUES ('SOCH')$q$);
SELECT t('SEG-001 cambiar el criadero de un ejemplar', 'P0001:id_criador de canario', $q$UPDATE canario SET id_criador=2 WHERE id_canario=3$q$);
SELECT t('SEG-001 cambiar el criadero de una jaula', 'P0001:id_criador de jaula', $q$UPDATE jaula SET id_criador=2, numero_jaula=99 WHERE id_jaula=5$q$);

-- ---------- Variedad / sexo ----------
SELECT t('RF009 el sexo de la variedad se deriva del nombre', 'OK',
 $q$DO $d$ BEGIN
      IF (SELECT sexo FROM variedad WHERE id_variedad=1) IS NOT NULL
         OR (SELECT sexo FROM variedad WHERE id_variedad=2) IS DISTINCT FROM 'M' THEN
        RAISE EXCEPTION 'sexo de variedad mal calculado';
      END IF; END $d$$q$);
SELECT t('RF009 escribir a mano el sexo de una variedad', '428C9:',
 $q$INSERT INTO variedad (codigo,nombre,tipo,sexo) VALUES ('X0','ROJO MOSAICO HEMBRA','CC','M')$q$);
SELECT t('RF009 variedad MACHO en hembra', 'P0001:no coincide con el sexo de la variedad',
 $q$INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador) VALUES ('78',4,'123',2026,'H',2,1)$q$);
SELECT t('RF009 variedad MACHO en macho', 'OK',
 $q$INSERT INTO canario (anillo,id_club,numero_socio,temporada,sexo,id_variedad,id_criador) VALUES ('79',4,'123',2026,'M',2,1)$q$);
SELECT t('RF010 tipo de variedad inválido', '23514:variedad_tipo_check', $q$INSERT INTO variedad (codigo,nombre,tipo) VALUES ('X1','X','ZZ')$q$);
SELECT t('RF010 variedad sin nombre', '23514:variedad_nombre_check', $q$INSERT INTO variedad (codigo,nombre,tipo) VALUES ('X2','  ','CC')$q$);
SELECT t('RF027 tipo de herencia inválido', '23514:mutacion_tipo_herencia_check', $q$INSERT INTO mutacion (nombre,tipo_herencia) VALUES ('X','dominante')$q$);
SELECT t('RF027 mutación repetida con otras mayúsculas', '23505:uq_mutacion_nombre_lower', $q$INSERT INTO mutacion (nombre,tipo_herencia) VALUES ('ágata','ligada al sexo recesiva')$q$);

-- ---------- Requiere revisión (RF010, RF032) ----------
SELECT t('RF010 el nomenclador cambia D.007 a HEMBRA (se aplica la carga)', 'OK',
 $q$UPDATE variedad SET nombre='AMARILLO MOSAICO HEMBRA' WHERE id_variedad=2$q$);
SELECT t('RF010 los machos con D.007 quedan en Requiere revisión', 'OK',
 $q$DO $d$ BEGIN
      IF (SELECT count(*) FROM canario WHERE requiere_revision) <> 2 THEN
        RAISE EXCEPTION 'se esperaban 2 ejemplares marcados (anillos 50 y 79)';
      END IF; END $d$$q$);
SELECT t('RF032 retirar la marca sin resolver la incoherencia', 'P0001:solo se retira cuando',
 $q$UPDATE canario SET requiere_revision=false WHERE id_canario=11$q$);
SELECT t('RF032 formulario que reescribe el sexo sin cambiarlo', 'OK',
 $q$UPDATE canario SET sexo=sexo, anillo=anillo WHERE id_canario=11$q$);
SELECT t('RF032 asignar una variedad coherente', 'OK',
 $q$UPDATE canario SET id_variedad=1 WHERE id_canario=11$q$);
SELECT t('RF032 la marca se retira sola al quedar coherente', 'OK',
 $q$DO $d$ BEGIN
      IF (SELECT requiere_revision FROM canario WHERE id_canario=11) THEN
        RAISE EXCEPTION 'la marca debía retirarse';
      END IF; END $d$$q$);
SELECT t('RF032 marcar a mano un ejemplar coherente no tiene efecto', 'OK',
 $q$DO $d$ BEGIN
      UPDATE canario SET requiere_revision=true WHERE id_canario=11;
      IF (SELECT requiere_revision FROM canario WHERE id_canario=11) THEN
        RAISE EXCEPTION 'la marca la calcula la base';
      END IF; END $d$$q$);
SELECT t('RF010 el nomenclador vuelve D.007 a MACHO y retira las marcas', 'OK',
 $q$DO $d$ BEGIN
      UPDATE variedad SET nombre='AMARILLO MOSAICO MACHO' WHERE id_variedad=2;
      IF EXISTS (SELECT 1 FROM canario WHERE requiere_revision) THEN
        RAISE EXCEPTION 'no debían quedar ejemplares marcados';
      END IF; END $d$$q$);

-- ---------- Parejas ----------
SELECT t('RF012 pareja válida (macho 1 + hembra 2, jaula 1)', 'OK', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula) VALUES (1,1,2,1)$q$);
SELECT t('RF012 pareja H x H', 'P0001:no está registrado como macho', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula) VALUES (1,3,4,2)$q$);
SELECT t('RF012 pareja M x M', 'P0001:no está registrado como hembra', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula) VALUES (1,1,11,2)$q$);
SELECT t('RF014 jaula ocupada', '23505:uq_pareja_jaula_activa', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula) VALUES (1,1,3,1)$q$);
SELECT t('RF015 hembra con pareja activa', '23505:uq_pareja_hembra_activa', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula) VALUES (1,11,2,2)$q$);
SELECT t('SEG-001 hembra de otro criadero', '23503:fk_pareja_hembra', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula) VALUES (1,1,10,2)$q$);
SELECT t('SEG-001 jaula de otro criadero', '23503:fk_pareja_jaula', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula) VALUES (1,1,3,11)$q$);
SELECT t('SEG-001 pareja a nombre de otro criador', '23503:fk_pareja_', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula) VALUES (2,1,3,2)$q$);
SELECT t('RF012 jaula número 0', '23514:jaula_numero_jaula_check', $q$INSERT INTO jaula (numero_jaula,id_criador) VALUES (0,1)$q$);
SELECT t('RF017 crear una pareja ya finalizada', 'P0001:se crea en estado activa', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula,estado,fecha_fin) VALUES (1,1,3,2,'finalizada',CURRENT_DATE)$q$);
SELECT t('RF012 pareja con fecha de formación futura', '23514:pareja_fecha_formacion_check', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula,fecha_formacion) VALUES (1,1,3,2,CURRENT_DATE+1)$q$);
-- Reactivar se prueba aquí, con la jaula 2 libre
SELECT t('RF017 pareja con hembra 3 en jaula 2', 'OK', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula) VALUES (1,1,3,2)$q$);
SELECT t('RF017 finalizar pareja sin fecha_fin', '23514:ck_pareja_fin', $q$UPDATE pareja SET estado='finalizada' WHERE id_hembra=3$q$);
SELECT t('RF017 finalizar la pareja de la hembra 3 (libera jaula 2)', 'OK', $q$UPDATE pareja SET estado='finalizada', fecha_fin=CURRENT_DATE WHERE id_hembra=3$q$);
SELECT t('RF017 reactivar pareja finalizada', 'P0001:finalizada no puede cambiar de estado', $q$UPDATE pareja SET estado='activa', fecha_fin=NULL WHERE id_hembra=3$q$);
SELECT t('RF017 pasar una pareja finalizada a anulada', 'P0001:finalizada no puede cambiar de estado', $q$UPDATE pareja SET estado='anulada' WHERE id_hembra=3$q$);
SELECT t('RF013 parejas 2 a 6 del macho', 'OK', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula) VALUES (1,1,4,2),(1,1,5,3),(1,1,6,4),(1,1,7,5),(1,1,8,6)$q$);
-- Sin límite de parejas activas por macho (se quitó el máximo de 6 de RF013)
SELECT t('RF013 séptima pareja activa del macho (sin límite)', 'OK', $q$INSERT INTO pareja (id_criador,id_macho,id_hembra,id_jaula) VALUES (1,1,9,7)$q$);
SELECT t('RF013 finalizar la pareja de la hembra 4', 'OK', $q$UPDATE pareja SET estado='finalizada', fecha_fin=CURRENT_DATE WHERE id_hembra=4$q$);
SELECT t('RF013 tras finalizar una, el macho queda con 6 parejas activas', 'OK',
 $q$DO $d$ BEGIN
      IF (SELECT count(*) FROM pareja WHERE id_macho = 1 AND estado = 'activa') <> 6 THEN
        RAISE EXCEPTION 'se esperaban 6 parejas activas del macho 1';
      END IF;
    END $d$$q$);
SELECT t('RF031 reasignar una pareja finalizada a otro macho', 'OK', $q$UPDATE pareja SET id_macho=11 WHERE id_hembra=4$q$);
SELECT t('SEG-001 cambiar el criadero de una pareja', 'P0001:id_criador de pareja', $q$UPDATE pareja SET id_criador=2 WHERE id_pareja=1$q$);

-- ---------- Cruce / nidada / cría ----------
SELECT t('RF016 cruce válido', 'OK', $q$INSERT INTO cruce (id_pareja,fecha_cruce) VALUES (1, CURRENT_DATE - 30)$q$);
SELECT t('RF016 cruce con fecha futura', '23514:cruce_fecha_cruce_check', $q$INSERT INTO cruce (id_pareja,fecha_cruce) VALUES (1, CURRENT_DATE + 1)$q$);
SELECT t('RF016 cruce sin fecha', '23502:fecha_cruce', $q$INSERT INTO cruce (id_pareja,fecha_cruce) VALUES (1, NULL)$q$);
SELECT t('RF016 cruce en pareja finalizada', 'P0001:en una pareja activa', $q$INSERT INTO cruce (id_pareja,fecha_cruce) SELECT id_pareja, CURRENT_DATE - 5 FROM pareja WHERE id_hembra=3$q$);
SELECT t('RF016 segundo cruce, en la pareja de la hembra 5', 'OK', $q$INSERT INTO cruce (id_pareja,fecha_cruce) SELECT id_pareja, CURRENT_DATE - 20 FROM pareja WHERE id_hembra=5$q$);
SELECT t('RF031 anular una pareja con cruces', 'P0001:con cruces no se anula', $q$UPDATE pareja SET estado='anulada', fecha_fin=CURRENT_DATE WHERE id_pareja=1$q$);
SELECT t('RF018 nidada anterior al cruce', 'P0001:es anterior a la fecha del cruce', $q$INSERT INTO nidada (id_cruce,fecha_nacimiento) VALUES (1, CURRENT_DATE - 40)$q$);
SELECT t('RF018 nidada válida', 'OK', $q$INSERT INTO nidada (id_cruce,fecha_nacimiento) VALUES (1, CURRENT_DATE - 10)$q$);
SELECT t('RF018 mover el cruce a después del nacimiento', 'P0001:posterior al nacimiento de sus nidadas', $q$UPDATE cruce SET fecha_cruce=CURRENT_DATE WHERE id_cruce=1$q$);
SELECT t('RF018 corregir la fecha del cruce dentro de lo válido', 'OK', $q$UPDATE cruce SET fecha_cruce=CURRENT_DATE - 25 WHERE id_cruce=1$q$);
SELECT t('RF020 cría sin sexo ni variedad (anillo 100)', 'OK',
 $q$WITH c AS (INSERT INTO canario (anillo,id_club,numero_socio,temporada,id_criador) VALUES ('100',4,'123',2026,1) RETURNING id_canario)
    INSERT INTO cria (id_canario,id_nidada) SELECT id_canario,(SELECT min(id_nidada) FROM nidada) FROM c$q$);
SELECT t('RF021 escribir a mano la marca de portadora', '428C9:',
 $q$UPDATE cria SET es_portadora = true WHERE id_cria = 1$q$);
SELECT t('RF021 indicar el factor marca a la cría como portadora', 'OK',
 $q$DO $d$ BEGIN
      UPDATE cria SET factor_genetico = 1 WHERE id_cria = 1;
      IF NOT (SELECT es_portadora FROM cria WHERE id_cria = 1) THEN RAISE EXCEPTION 'debía quedar portadora'; END IF;
    END $d$$q$);
SELECT t('RF021 retirar el factor retira la marca y conserva la cría', 'OK',
 $q$DO $d$ BEGIN
      UPDATE cria SET factor_genetico = NULL WHERE id_cria = 1;
      IF (SELECT es_portadora FROM cria WHERE id_cria = 1) THEN RAISE EXCEPTION 'no debía quedar portadora'; END IF;
    END $d$$q$);
SELECT t('SEG-001 cría de criador B en nidada de A', 'P0001:deben pertenecer al mismo criadero',
 $q$WITH c AS (INSERT INTO canario (anillo,id_club,numero_socio,temporada,id_criador) VALUES ('101',4,'456',2026,2) RETURNING id_canario)
    INSERT INTO cria (id_canario,id_nidada) SELECT id_canario,(SELECT min(id_nidada) FROM nidada) FROM c$q$);
SELECT t('RF004 adulto sin sexo (no es cría)', 'P0001:Solo una cría puede quedar sin sexo',
 $q$INSERT INTO canario (anillo,id_club,numero_socio,temporada,id_criador) VALUES ('102',4,'123',2026,1)$q$);
SELECT t('RF020 cría de criador A en su propia nidada (anillo 103)', 'OK',
 $q$WITH c AS (INSERT INTO canario (anillo,id_club,numero_socio,temporada,id_criador) VALUES ('103',4,'123',2026,1) RETURNING id_canario)
    INSERT INTO cria (id_canario,id_nidada) SELECT id_canario,(SELECT min(id_nidada) FROM nidada) FROM c$q$);
-- Se usa la hembra 10, que no tiene parejas, para que el rechazo sea por esta regla
SELECT t('RF004 quitar el sexo a un adulto', 'P0001:Solo una cría puede quedar sin sexo', $q$UPDATE canario SET sexo=NULL WHERE id_canario=10$q$);
SELECT t('RF020 asignar sexo y variedad a la cría pendiente', 'OK',
 $q$UPDATE canario SET sexo='M', id_variedad=1 WHERE anillo='103' AND temporada=2026$q$);
SELECT t('RF020 borrar la fila de cría de un ejemplar pendiente', 'P0001:Solo una cría puede quedar sin sexo',
 $q$DELETE FROM cria WHERE id_canario=(SELECT id_canario FROM canario WHERE anillo='100' AND temporada=2026)$q$);
SELECT t('RF022 un ejemplar como cría de su propia pareja', 'P0001:cría de su propia pareja',
 $q$INSERT INTO cria (id_canario,id_nidada) VALUES (1,(SELECT min(id_nidada) FROM nidada))$q$);
SELECT t('RF022 reasignar la pareja a una de sus propias crías', 'P0001:en la pareja de la que es cría',
 $q$UPDATE pareja SET id_macho=(SELECT id_canario FROM canario WHERE anillo='103' AND temporada=2026) WHERE id_pareja=1$q$);

-- Regresión de revision_fable (SQL-01, SQL-02): las relaciones de la cadena
-- pareja -> cruce -> nidada -> cría no se pueden redirigir con un UPDATE
SELECT t('SQL-01 mover un cruce a otra pareja activa', 'P0001:id_pareja de cruce',
 $q$UPDATE cruce SET id_pareja=(SELECT id_pareja FROM pareja WHERE id_hembra=5) WHERE id_cruce=1$q$);
SELECT t('SQL-01 mover un cruce a una pareja finalizada', 'P0001:id_pareja de cruce',
 $q$UPDATE cruce SET id_pareja=(SELECT id_pareja FROM pareja WHERE id_hembra=3) WHERE id_cruce=1$q$);
SELECT t('SQL-01 mover una nidada a otro cruce', 'P0001:id_cruce de nidada',
 $q$UPDATE nidada SET id_cruce=(SELECT max(id_cruce) FROM cruce) WHERE id_nidada=(SELECT min(id_nidada) FROM nidada)$q$);
SELECT t('SQL-01 mover una cría a otra nidada', 'P0001:id_nidada de cria',
 $q$WITH n AS (INSERT INTO nidada (id_cruce,fecha_nacimiento) SELECT max(id_cruce), CURRENT_DATE FROM cruce RETURNING id_nidada)
    UPDATE cria SET id_nidada=(SELECT id_nidada FROM n) WHERE id_cria=1$q$);
SELECT t('SQL-02 cambiar el ejemplar de una fila de cría', 'P0001:id_canario de cria',
 $q$UPDATE cria SET id_canario=6 WHERE id_cria=1$q$);
SELECT t('SQL-01 formulario que reescribe las llaves sin cambiarlas', 'OK',
 $q$UPDATE cruce SET id_pareja=id_pareja; UPDATE nidada SET id_cruce=id_cruce; UPDATE cria SET id_canario=id_canario, id_nidada=id_nidada$q$);

SELECT t('RF031 cambiar a H el sexo de un macho con parejas', 'P0001:participa en parejas',
 $q$UPDATE canario SET sexo='H' WHERE id_canario=1$q$);
SELECT t('RF031 anular la pareja sin cruces y luego corregir el sexo', 'OK',
 $q$UPDATE pareja SET estado='anulada', fecha_fin=CURRENT_DATE WHERE id_hembra=8 AND estado='activa';
    UPDATE canario SET sexo='M' WHERE id_canario=8$q$);
SELECT t('RF031 reactivar una pareja anulada', 'P0001:anulada no puede cambiar de estado', $q$UPDATE pareja SET estado='activa', fecha_fin=NULL WHERE id_hembra=8$q$);

-- ---------- Títulos ----------
SELECT t('RF023 título con fecha futura', '23514:titulo_fecha_check', $q$INSERT INTO titulo (id_canario,nombre,fecha) VALUES (1,'Campeón',CURRENT_DATE+1)$q$);
SELECT t('RF023 título sin nombre', '23514:titulo_nombre_check', $q$INSERT INTO titulo (id_canario,nombre,fecha) VALUES (1,'',CURRENT_DATE)$q$);
SELECT t('RF023 título con nombre de solo espacios', '23514:titulo_nombre_check', $q$INSERT INTO titulo (id_canario,nombre,fecha) VALUES (1,'   ',CURRENT_DATE)$q$);
SELECT t('RF023 título válido', 'OK', $q$INSERT INTO titulo (id_canario,nombre,fecha) VALUES (1,'Campeón Nacional',CURRENT_DATE)$q$);
SELECT t('RF023 el mismo título dos veces', '23505:uq_titulo', $q$INSERT INTO titulo (id_canario,nombre,fecha) VALUES (1,'Campeón Nacional',CURRENT_DATE)$q$);
SELECT t('RF023 pasar un título a otro ejemplar', 'P0001:id_canario de titulo', $q$UPDATE titulo SET id_canario=10$q$);

-- ---------- Solicitudes de corrección ----------
SELECT t('RF033 solicitud válida', 'OK', $q$INSERT INTO solicitud_correccion (id_canario,id_criador,dato_a_corregir,motivo) VALUES (2,1,'sexo','error de ingreso')$q$);
SELECT t('RF033 segunda solicitud pendiente', '23505:uq_solicitud_pendiente', $q$INSERT INTO solicitud_correccion (id_canario,id_criador,dato_a_corregir,motivo) VALUES (2,1,'variedad','otro')$q$);
SELECT t('RF033 dato a corregir inválido', '23514:solicitud_correccion_dato_a_corregir_check', $q$INSERT INTO solicitud_correccion (id_canario,id_criador,dato_a_corregir,motivo) VALUES (3,1,'anillo','x')$q$);
SELECT t('SEG-001 solicitud de B sobre canario de A', '23503:fk_solicitud_canario', $q$INSERT INTO solicitud_correccion (id_canario,id_criador,dato_a_corregir,motivo) VALUES (4,2,'sexo','x')$q$);
SELECT t('RF033 cerrar una solicitud antes de su fecha de creación', '23514:ck_solicitud_fechas', $q$UPDATE solicitud_correccion SET estado='cancelada', fecha_cierre=fecha_solicitud - interval '1 day' WHERE id_canario=2$q$);
SELECT t('RF033 cancelar la solicitud', 'OK', $q$UPDATE solicitud_correccion SET estado='cancelada', fecha_cierre=now() WHERE id_canario=2$q$);

-- ---------- Cuentas y roles ----------
SELECT t('SEG-001 criadero para un administrador', 'P0001:debe tener el rol criador', $q$INSERT INTO criador (id_usuario,numero_socio) VALUES (3,'1')$q$);
SELECT t('RF026 usuario criador sin criadero', 'P0001:debe crearse junto con su criadero', $q$INSERT INTO usuario (nombre,correo,password_hash,rol) VALUES ('Sin criadero','s@x.cl','h','criador')$q$);
SELECT t('RF026 cuenta de criador con su criadero', 'OK',
 $q$WITH u AS (INSERT INTO usuario (nombre,correo,password_hash,rol) VALUES ('Criador C','c@x.cl','h','criador') RETURNING id_usuario)
    INSERT INTO criador (id_usuario,numero_socio) SELECT id_usuario,'789' FROM u$q$);
SELECT t('SEG-001 cambiar el rol de un usuario', 'P0001:rol de usuario', $q$UPDATE usuario SET rol='administrador' WHERE id_usuario=1$q$);
-- Regresión de revision_fable (SQL-04)
SELECT t('SQL-04 pasar un criadero a otra cuenta', 'P0001:id_usuario de criador',
 $q$UPDATE criador SET id_usuario=(SELECT id_usuario FROM usuario WHERE correo='c@x.cl') WHERE id_usuario=1$q$);
SELECT t('SQL-04 borrar el criadero (vacío) de un usuario criador', 'P0001:no puede quedar sin criadero',
 $q$DELETE FROM criador WHERE id_usuario=(SELECT id_usuario FROM usuario WHERE correo='c@x.cl')$q$);
SELECT t('RF026 correo repetido con mayúsculas', '23505:uq_usuario_correo_lower', $q$INSERT INTO usuario (nombre,correo,password_hash,rol) VALUES ('X','ADMIN@x.cl','h','administrador')$q$);
SELECT t('RF026 nombre vacío', '23514:usuario_nombre_check', $q$INSERT INTO usuario (nombre,correo,password_hash,rol) VALUES (' ','n@x.cl','h','administrador')$q$);
SELECT t('RF026 correo sin formato', '23514:usuario_correo_check', $q$INSERT INTO usuario (nombre,correo,password_hash,rol) VALUES ('X','no-es-correo','h','administrador')$q$);

-- ---------- Modos y respaldos ----------
SELECT t('RF028 un criador activa el mantenimiento', 'P0001:debe tener el rol administrador', $q$INSERT INTO modo_operacion (modo,id_usuario) VALUES ('mantenimiento',1)$q$);
SELECT t('RF028 el administrador activa el mantenimiento', 'OK', $q$INSERT INTO modo_operacion (modo,id_usuario) VALUES ('mantenimiento',3)$q$);
SELECT t('RF028 dos modos activos a la vez', '23505:uq_modo_activo', $q$INSERT INTO modo_operacion (modo,id_usuario) VALUES ('emergencia',3)$q$);
SELECT t('RF028 desactivar sin indicar quién', '23514:ck_modo_cierre', $q$UPDATE modo_operacion SET fecha_desactivacion=now() WHERE fecha_desactivacion IS NULL$q$);
SELECT t('RF028 un criador desactiva el modo', 'P0001:debe tener el rol administrador', $q$UPDATE modo_operacion SET fecha_desactivacion=now(), id_usuario_cierre=1 WHERE fecha_desactivacion IS NULL$q$);
SELECT t('RF028 el mantenimiento se cierra sin diagnóstico', 'OK', $q$UPDATE modo_operacion SET fecha_desactivacion=now(), id_usuario_cierre=3 WHERE fecha_desactivacion IS NULL$q$);
SELECT t('RF028 el administrador activa la emergencia', 'OK', $q$INSERT INTO modo_operacion (modo,id_usuario) VALUES ('emergencia',3)$q$);
SELECT t('DAT-003 cerrar la emergencia sin diagnóstico', '23514:ck_modo_emergencia', $q$UPDATE modo_operacion SET fecha_desactivacion=now(), id_usuario_cierre=3 WHERE fecha_desactivacion IS NULL$q$);
-- Regresión de revision_fable (SQL-03): todas las combinaciones del diagnóstico
SELECT t('SQL-03 diagnóstico sin fecha', '23514:ck_modo_diagnostico', $q$UPDATE modo_operacion SET diagnostico='Disco lleno' WHERE fecha_desactivacion IS NULL$q$);
SELECT t('SQL-03 fecha de diagnóstico sin texto', '23514:ck_modo_diagnostico', $q$UPDATE modo_operacion SET fecha_diagnostico=now() WHERE fecha_desactivacion IS NULL$q$);
SELECT t('SQL-03 diagnóstico de solo espacios', '23514:ck_modo_diagnostico', $q$UPDATE modo_operacion SET diagnostico='  ', fecha_diagnostico=now() WHERE fecha_desactivacion IS NULL$q$);
SELECT t('SQL-03 diagnóstico fechado antes de la activación', '23514:ck_modo_diagnostico', $q$UPDATE modo_operacion SET diagnostico='x', fecha_diagnostico=fecha_activacion - interval '1 hour' WHERE fecha_desactivacion IS NULL$q$);
SELECT t('SQL-03 cerrar la emergencia con diagnóstico sin fecha', '23514:ck_modo_diagnostico',
 $q$UPDATE modo_operacion SET fecha_desactivacion=now(), id_usuario_cierre=3, diagnostico='Diagnosticado', acciones_recuperacion='x' WHERE fecha_desactivacion IS NULL$q$);
SELECT t('DAT-003 registrar el diagnóstico con su fecha', 'OK', $q$UPDATE modo_operacion SET diagnostico='Disco lleno', fecha_diagnostico=now() WHERE fecha_desactivacion IS NULL$q$);
SELECT t('2.5 cerrar la emergencia sin acciones de recuperación', '23514:ck_modo_emergencia', $q$UPDATE modo_operacion SET fecha_desactivacion=now(), id_usuario_cierre=3 WHERE fecha_desactivacion IS NULL$q$);
SELECT t('2.5 acciones de recuperación de solo espacios', '23514:ck_modo_acciones', $q$UPDATE modo_operacion SET acciones_recuperacion='   ' WHERE fecha_desactivacion IS NULL$q$);
SELECT t('DAT-003 cerrar la emergencia con diagnóstico y acciones', 'OK',
 $q$UPDATE modo_operacion SET acciones_recuperacion='Se restauró el respaldo', fecha_desactivacion=now(), id_usuario_cierre=3 WHERE fecha_desactivacion IS NULL$q$);
SELECT t('RF029 respaldo manual atribuido a un criador', 'P0001:debe tener el rol administrador', $q$INSERT INTO respaldo (archivo,id_usuario) VALUES ('manual_criador.dump',1)$q$);
SELECT t('RF029 respaldo manual del administrador', 'OK', $q$INSERT INTO respaldo (archivo,id_usuario) VALUES ('manual_admin.dump',3)$q$);
SELECT t('DAT-003 respaldo automático (sin usuario)', 'OK', $q$INSERT INTO respaldo (archivo) VALUES ('auto_1.dump')$q$);

-- ---------- Auditoría ----------
SELECT t('SEG-003 registrar un acceso', 'OK', $q$INSERT INTO auditoria (id_usuario,accion) VALUES (1,'login')$q$);
SELECT t('SEG-003 modificar la auditoría', 'P0001:no se puede modificar ni borrar', $q$UPDATE auditoria SET accion='otra'$q$);
SELECT t('SEG-003 borrar la auditoría', 'P0001:no se puede modificar ni borrar', $q$DELETE FROM auditoria$q$);

-- ---------- Simulación ----------
SELECT t('RF025 simulación válida (ligada al sexo, hembra sin factor)', 'OK',
 $q$INSERT INTO simulacion (id_criador,id_macho,id_hembra,id_mutacion,genotipo_macho,genotipo_hembra) VALUES (1,1,2,1,'visual','sin factor')$q$);
SELECT t('RF025 hembra portadora en mutación ligada al sexo', 'P0001:no puede ser portadora',
 $q$INSERT INTO simulacion (id_criador,id_macho,id_hembra,id_mutacion,genotipo_macho,genotipo_hembra) VALUES (1,1,2,1,'visual','portador')$q$);
SELECT t('RF025 hembra portadora en mutación autosómica', 'OK',
 $q$INSERT INTO simulacion (id_criador,id_macho,id_hembra,id_mutacion,genotipo_macho,genotipo_hembra) VALUES (1,1,2,2,'visual','portador')$q$);
SELECT t('SEG-001 simulación con macho de A y hembra de B', '23503:fk_simulacion_hembra',
 $q$INSERT INTO simulacion (id_criador,id_macho,id_hembra,id_mutacion,genotipo_macho,genotipo_hembra) VALUES (1,1,10,1,'visual','sin factor')$q$);
SELECT t('RF025 simulación con dos hembras', 'P0001:requiere un macho y una hembra',
 $q$INSERT INTO simulacion (id_criador,id_macho,id_hembra,id_mutacion,genotipo_macho,genotipo_hembra) VALUES (1,2,3,1,'visual','sin factor')$q$);
SELECT t('DAT-006 resultados de macho visual x hembra sin factor', 'OK',
 $q$INSERT INTO simulacion_resultado (id_simulacion,sexo_cria,genotipo_resultado,probabilidad) VALUES (1,'M','portador',0.5),(1,'H','visual',0.5)$q$);
SELECT t('DAT-006 resultado repetido', '23505:uq_simulacion_resultado',
 $q$INSERT INTO simulacion_resultado (id_simulacion,sexo_cria,genotipo_resultado,probabilidad) VALUES (1,'M','portador',0.5)$q$);
SELECT t('DAT-006 resultado de hembra portadora', '23514:ck_resultado_hembra',
 $q$INSERT INTO simulacion_resultado (id_simulacion,sexo_cria,genotipo_resultado,probabilidad) VALUES (1,'H','portador',0.5)$q$);
SELECT t('DAT-006 resultado autosómico repetido (sin sexo)', '23505:uq_simulacion_resultado',
 $q$INSERT INTO simulacion_resultado (id_simulacion,genotipo_resultado,probabilidad)
    SELECT max(id_simulacion),'portador',0.5 FROM simulacion UNION ALL SELECT max(id_simulacion),'portador',0.5 FROM simulacion$q$);

-- ---------- Genealogía ----------
SELECT t('RF022 genealogía de la cría 100: padre 1, madre 2, abuelos sin registrar', 'OK',
 $q$DO $d$ DECLARE g v_genealogia%ROWTYPE; BEGIN
      SELECT v.* INTO g FROM v_genealogia v JOIN canario c USING (id_canario) WHERE c.anillo='100' AND c.temporada=2026;
      IF g.id_padre IS DISTINCT FROM 1 OR g.id_madre IS DISTINCT FROM 2
         OR num_nonnulls(g.id_abuelo_paterno, g.id_abuela_paterna, g.id_abuelo_materno, g.id_abuela_materna) <> 0 THEN
        RAISE EXCEPTION 'genealogía inesperada: %', g;
      END IF; END $d$$q$);

-- ---------- Resumen ----------
\echo
SELECT count(*) AS casos, count(*) FILTER (WHERE ok) AS ok, count(*) FILTER (WHERE NOT ok) AS falla
  FROM resultado_pruebas;
SELECT n, nombre, detalle FROM resultado_pruebas WHERE NOT ok ORDER BY n;
DO $$
DECLARE v INT := (SELECT count(*) FROM resultado_pruebas WHERE NOT ok);
BEGIN
  IF v > 0 THEN
    RAISE EXCEPTION '% caso(s) de prueba con FALLA', v;
  END IF;
END $$;

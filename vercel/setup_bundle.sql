--
-- PostgreSQL database dump
--


-- Dumped from database version 16.16 (Debian 16.16-1.pgdg12+1)
-- Dumped by pg_dump version 16.16 (Debian 16.16-1.pgdg12+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--



--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--



--
-- Name: fn_auditoria_inmutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_auditoria_inmutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'La auditoría no se puede modificar ni borrar';
END;
$$;


--
-- Name: fn_estado_pareja(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_estado_pareja() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: fn_exigir_rol(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_exigir_rol() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: fn_inmutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_inmutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'La columna % de % no se puede modificar', TG_ARGV[0], TG_TABLE_NAME;
END;
$$;


--
-- Name: fn_marcar_revision(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_marcar_revision() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.sexo IS DISTINCT FROM OLD.sexo THEN
        UPDATE canario
           SET requiere_revision = (NEW.sexo IS NOT NULL AND sexo <> NEW.sexo)
         WHERE id_variedad = NEW.id_variedad
           AND sexo IS NOT NULL;
    END IF;
    RETURN NULL;
END;
$$;


--
-- Name: fn_validar_baja_criador(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_validar_baja_criador() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM usuario WHERE id_usuario = OLD.id_usuario AND rol = 'criador')
       AND NOT EXISTS (SELECT 1 FROM criador WHERE id_usuario = OLD.id_usuario) THEN
        RAISE EXCEPTION 'El usuario criador % no puede quedar sin criadero', OLD.id_usuario;
    END IF;
    RETURN NULL;
END;
$$;


--
-- Name: fn_validar_cambio_sexo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_validar_cambio_sexo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: fn_validar_cria(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_validar_cria() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: fn_validar_criadero(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_validar_criadero() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.rol = 'criador'
       AND NOT EXISTS (SELECT 1 FROM criador WHERE id_usuario = NEW.id_usuario) THEN
        RAISE EXCEPTION 'El usuario criador % debe crearse junto con su criadero', NEW.id_usuario;
    END IF;
    RETURN NULL;
END;
$$;


--
-- Name: fn_validar_cruce(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_validar_cruce() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: fn_validar_nidada(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_validar_nidada() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE v_fecha_cruce DATE;
BEGIN
    SELECT fecha_cruce INTO v_fecha_cruce FROM cruce WHERE id_cruce = NEW.id_cruce;
    IF NEW.fecha_nacimiento < v_fecha_cruce THEN
        RAISE EXCEPTION 'La fecha de nacimiento (%) es anterior a la fecha del cruce (%)',
            NEW.fecha_nacimiento, v_fecha_cruce;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: fn_validar_pareja(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_validar_pareja() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: fn_validar_pendiente_cria(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_validar_pendiente_cria() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: fn_validar_sexo_variedad(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_validar_sexo_variedad() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: fn_validar_simulacion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_validar_simulacion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: auditoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditoria (
    id_auditoria bigint NOT NULL,
    id_usuario integer,
    fecha_hora timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    accion character varying(50) NOT NULL,
    entidad character varying(50),
    id_registro integer,
    valor_anterior text,
    valor_nuevo text,
    motivo text,
    id_criador_solicitante integer,
    id_solicitud integer,
    CONSTRAINT auditoria_accion_check CHECK ((btrim((accion)::text) <> ''::text))
);


--
-- Name: auditoria_id_auditoria_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auditoria_id_auditoria_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auditoria_id_auditoria_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auditoria_id_auditoria_seq OWNED BY public.auditoria.id_auditoria;


--
-- Name: canario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.canario (
    id_canario integer NOT NULL,
    anillo character varying(6) NOT NULL,
    id_club integer NOT NULL,
    numero_socio character varying(5) NOT NULL,
    temporada smallint NOT NULL,
    sexo character(1),
    id_variedad integer,
    id_criador integer NOT NULL,
    requiere_revision boolean DEFAULT false NOT NULL,
    fecha_registro timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT canario_anillo_check CHECK (((anillo)::text ~ '^[0-9]{1,6}$'::text)),
    CONSTRAINT canario_numero_socio_check CHECK (((numero_socio)::text ~ '^[0-9]{1,5}$'::text)),
    CONSTRAINT canario_sexo_check CHECK ((sexo = ANY (ARRAY['M'::bpchar, 'H'::bpchar]))),
    CONSTRAINT canario_temporada_check CHECK (((temporada >= 1000) AND (temporada <= 9999)))
);


--
-- Name: canario_id_canario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.canario_id_canario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: canario_id_canario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.canario_id_canario_seq OWNED BY public.canario.id_canario;


--
-- Name: club; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.club (
    id_club integer NOT NULL,
    sigla character varying(6) NOT NULL,
    CONSTRAINT club_sigla_check CHECK (((sigla)::text ~ '^[A-Z]{2,6}$'::text))
);


--
-- Name: club_id_club_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.club_id_club_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: club_id_club_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.club_id_club_seq OWNED BY public.club.id_club;


--
-- Name: cria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cria (
    id_cria integer NOT NULL,
    id_canario integer NOT NULL,
    id_nidada integer NOT NULL,
    factor_genetico integer,
    es_portadora boolean GENERATED ALWAYS AS ((factor_genetico IS NOT NULL)) STORED,
    reservada boolean DEFAULT false NOT NULL
);


--
-- Name: cria_id_cria_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cria_id_cria_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cria_id_cria_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cria_id_cria_seq OWNED BY public.cria.id_cria;


--
-- Name: criador; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.criador (
    id_criador integer NOT NULL,
    id_usuario integer NOT NULL,
    numero_socio character varying(5) NOT NULL,
    fecha_creacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT criador_numero_socio_check CHECK (((numero_socio)::text ~ '^[0-9]{1,5}$'::text))
);


--
-- Name: criador_id_criador_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.criador_id_criador_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: criador_id_criador_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.criador_id_criador_seq OWNED BY public.criador.id_criador;


--
-- Name: cruce; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cruce (
    id_cruce integer NOT NULL,
    id_pareja integer NOT NULL,
    fecha_cruce date NOT NULL,
    CONSTRAINT cruce_fecha_cruce_check CHECK ((fecha_cruce <= CURRENT_DATE))
);


--
-- Name: cruce_id_cruce_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cruce_id_cruce_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cruce_id_cruce_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cruce_id_cruce_seq OWNED BY public.cruce.id_cruce;


--
-- Name: jaula; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jaula (
    id_jaula integer NOT NULL,
    numero_jaula integer NOT NULL,
    id_criador integer NOT NULL,
    CONSTRAINT jaula_numero_jaula_check CHECK ((numero_jaula >= 1))
);


--
-- Name: jaula_id_jaula_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.jaula_id_jaula_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jaula_id_jaula_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.jaula_id_jaula_seq OWNED BY public.jaula.id_jaula;


--
-- Name: modo_operacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.modo_operacion (
    id_modo integer NOT NULL,
    modo character varying(15) NOT NULL,
    fecha_activacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_desactivacion timestamp with time zone,
    id_usuario integer NOT NULL,
    id_usuario_cierre integer,
    diagnostico text,
    fecha_diagnostico timestamp with time zone,
    acciones_recuperacion text,
    CONSTRAINT ck_modo_acciones CHECK (((acciones_recuperacion IS NULL) OR (btrim(acciones_recuperacion) <> ''::text))),
    CONSTRAINT ck_modo_cierre CHECK (((fecha_desactivacion IS NULL) = (id_usuario_cierre IS NULL))),
    CONSTRAINT ck_modo_diagnostico CHECK ((((diagnostico IS NULL) AND (fecha_diagnostico IS NULL)) OR ((diagnostico IS NOT NULL) AND (fecha_diagnostico IS NOT NULL) AND (btrim(diagnostico) <> ''::text) AND (fecha_diagnostico >= fecha_activacion)))),
    CONSTRAINT ck_modo_emergencia CHECK ((((modo)::text <> 'emergencia'::text) OR (fecha_desactivacion IS NULL) OR ((diagnostico IS NOT NULL) AND (acciones_recuperacion IS NOT NULL)))),
    CONSTRAINT ck_modo_fechas CHECK (((fecha_desactivacion IS NULL) OR (fecha_desactivacion >= fecha_activacion))),
    CONSTRAINT modo_operacion_modo_check CHECK (((modo)::text = ANY ((ARRAY['mantenimiento'::character varying, 'emergencia'::character varying])::text[])))
);


--
-- Name: modo_operacion_id_modo_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.modo_operacion_id_modo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: modo_operacion_id_modo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.modo_operacion_id_modo_seq OWNED BY public.modo_operacion.id_modo;


--
-- Name: mutacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mutacion (
    id_mutacion integer NOT NULL,
    nombre character varying(100) NOT NULL,
    tipo_herencia character varying(30) NOT NULL,
    CONSTRAINT mutacion_nombre_check CHECK ((btrim((nombre)::text) <> ''::text)),
    CONSTRAINT mutacion_tipo_herencia_check CHECK (((tipo_herencia)::text = ANY ((ARRAY['autosómica recesiva'::character varying, 'ligada al sexo recesiva'::character varying])::text[])))
);


--
-- Name: mutacion_id_mutacion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mutacion_id_mutacion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mutacion_id_mutacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mutacion_id_mutacion_seq OWNED BY public.mutacion.id_mutacion;


--
-- Name: nidada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nidada (
    id_nidada integer NOT NULL,
    id_cruce integer NOT NULL,
    fecha_nacimiento date NOT NULL,
    CONSTRAINT nidada_fecha_nacimiento_check CHECK ((fecha_nacimiento <= CURRENT_DATE))
);


--
-- Name: nidada_id_nidada_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.nidada_id_nidada_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: nidada_id_nidada_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.nidada_id_nidada_seq OWNED BY public.nidada.id_nidada;


--
-- Name: pareja; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pareja (
    id_pareja integer NOT NULL,
    id_criador integer NOT NULL,
    id_macho integer NOT NULL,
    id_hembra integer NOT NULL,
    id_jaula integer NOT NULL,
    fecha_formacion date DEFAULT CURRENT_DATE NOT NULL,
    estado character varying(15) DEFAULT 'activa'::character varying NOT NULL,
    fecha_fin date,
    CONSTRAINT ck_pareja_distintos CHECK ((id_macho <> id_hembra)),
    CONSTRAINT ck_pareja_fin CHECK (((((estado)::text = 'activa'::text) AND (fecha_fin IS NULL)) OR (((estado)::text <> 'activa'::text) AND (fecha_fin IS NOT NULL) AND (fecha_fin >= fecha_formacion)))),
    CONSTRAINT pareja_estado_check CHECK (((estado)::text = ANY ((ARRAY['activa'::character varying, 'finalizada'::character varying, 'anulada'::character varying])::text[]))),
    CONSTRAINT pareja_fecha_formacion_check CHECK ((fecha_formacion <= CURRENT_DATE))
);


--
-- Name: pareja_id_pareja_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pareja_id_pareja_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pareja_id_pareja_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pareja_id_pareja_seq OWNED BY public.pareja.id_pareja;


--
-- Name: php_sesion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.php_sesion (
    id character varying(128) NOT NULL,
    data text NOT NULL,
    actualizado timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: respaldo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.respaldo (
    id_respaldo integer NOT NULL,
    fecha_hora timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    archivo character varying(255) NOT NULL,
    id_usuario integer,
    CONSTRAINT respaldo_archivo_check CHECK ((btrim((archivo)::text) <> ''::text))
);


--
-- Name: respaldo_id_respaldo_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.respaldo_id_respaldo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: respaldo_id_respaldo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.respaldo_id_respaldo_seq OWNED BY public.respaldo.id_respaldo;


--
-- Name: simulacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.simulacion (
    id_simulacion integer NOT NULL,
    id_criador integer NOT NULL,
    id_macho integer NOT NULL,
    id_hembra integer NOT NULL,
    id_mutacion integer NOT NULL,
    genotipo_macho character varying(10) NOT NULL,
    genotipo_hembra character varying(10) NOT NULL,
    fecha timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_simulacion_distintos CHECK ((id_macho <> id_hembra)),
    CONSTRAINT simulacion_genotipo_hembra_check CHECK (((genotipo_hembra)::text = ANY ((ARRAY['visual'::character varying, 'portador'::character varying, 'sin factor'::character varying])::text[]))),
    CONSTRAINT simulacion_genotipo_macho_check CHECK (((genotipo_macho)::text = ANY ((ARRAY['visual'::character varying, 'portador'::character varying, 'sin factor'::character varying])::text[])))
);


--
-- Name: simulacion_id_simulacion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.simulacion_id_simulacion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: simulacion_id_simulacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.simulacion_id_simulacion_seq OWNED BY public.simulacion.id_simulacion;


--
-- Name: simulacion_resultado; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.simulacion_resultado (
    id_resultado integer NOT NULL,
    id_simulacion integer NOT NULL,
    sexo_cria character(1),
    genotipo_resultado character varying(10) NOT NULL,
    probabilidad numeric(6,5) NOT NULL,
    CONSTRAINT ck_resultado_hembra CHECK ((NOT ((sexo_cria = 'H'::bpchar) AND ((genotipo_resultado)::text = 'portador'::text)))),
    CONSTRAINT simulacion_resultado_genotipo_resultado_check CHECK (((genotipo_resultado)::text = ANY ((ARRAY['visual'::character varying, 'portador'::character varying, 'sin factor'::character varying])::text[]))),
    CONSTRAINT simulacion_resultado_probabilidad_check CHECK (((probabilidad >= (0)::numeric) AND (probabilidad <= (1)::numeric))),
    CONSTRAINT simulacion_resultado_sexo_cria_check CHECK ((sexo_cria = ANY (ARRAY['M'::bpchar, 'H'::bpchar])))
);


--
-- Name: simulacion_resultado_id_resultado_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.simulacion_resultado_id_resultado_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: simulacion_resultado_id_resultado_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.simulacion_resultado_id_resultado_seq OWNED BY public.simulacion_resultado.id_resultado;


--
-- Name: solicitud_correccion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solicitud_correccion (
    id_solicitud integer NOT NULL,
    id_canario integer NOT NULL,
    id_criador integer NOT NULL,
    dato_a_corregir character varying(10) NOT NULL,
    motivo text NOT NULL,
    estado character varying(15) DEFAULT 'pendiente'::character varying NOT NULL,
    fecha_solicitud timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_cierre timestamp with time zone,
    CONSTRAINT ck_solicitud_cierre CHECK ((((estado)::text = 'pendiente'::text) = (fecha_cierre IS NULL))),
    CONSTRAINT ck_solicitud_fechas CHECK (((fecha_cierre IS NULL) OR (fecha_cierre >= fecha_solicitud))),
    CONSTRAINT solicitud_correccion_dato_a_corregir_check CHECK (((dato_a_corregir)::text = ANY ((ARRAY['sexo'::character varying, 'variedad'::character varying])::text[]))),
    CONSTRAINT solicitud_correccion_estado_check CHECK (((estado)::text = ANY ((ARRAY['pendiente'::character varying, 'aprobada'::character varying, 'rechazada'::character varying, 'cancelada'::character varying])::text[]))),
    CONSTRAINT solicitud_correccion_motivo_check CHECK ((btrim(motivo) <> ''::text))
);


--
-- Name: solicitud_correccion_id_solicitud_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solicitud_correccion_id_solicitud_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solicitud_correccion_id_solicitud_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solicitud_correccion_id_solicitud_seq OWNED BY public.solicitud_correccion.id_solicitud;


--
-- Name: titulo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.titulo (
    id_titulo integer NOT NULL,
    id_canario integer NOT NULL,
    nombre character varying(100) NOT NULL,
    fecha date NOT NULL,
    CONSTRAINT titulo_fecha_check CHECK ((fecha <= CURRENT_DATE)),
    CONSTRAINT titulo_nombre_check CHECK ((btrim((nombre)::text) <> ''::text))
);


--
-- Name: titulo_id_titulo_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.titulo_id_titulo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: titulo_id_titulo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.titulo_id_titulo_seq OWNED BY public.titulo.id_titulo;


--
-- Name: usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario (
    id_usuario integer NOT NULL,
    nombre character varying(100) NOT NULL,
    correo character varying(150) NOT NULL,
    password_hash character varying(255) NOT NULL,
    rol character varying(15) NOT NULL,
    fecha_creacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT usuario_correo_check CHECK (((correo)::text ~ '^[^@[:space:]]+@[^@[:space:]]+$'::text)),
    CONSTRAINT usuario_nombre_check CHECK ((btrim((nombre)::text) <> ''::text)),
    CONSTRAINT usuario_rol_check CHECK (((rol)::text = ANY ((ARRAY['criador'::character varying, 'administrador'::character varying])::text[])))
);


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.usuario_id_usuario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.usuario_id_usuario_seq OWNED BY public.usuario.id_usuario;


--
-- Name: v_genealogia; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_genealogia AS
 WITH padres AS NOT MATERIALIZED (
         SELECT cr.id_canario,
            p.id_macho AS id_padre,
            p.id_hembra AS id_madre
           FROM (((public.cria cr
             JOIN public.nidada n ON ((n.id_nidada = cr.id_nidada)))
             JOIN public.cruce c ON ((c.id_cruce = n.id_cruce)))
             JOIN public.pareja p ON ((p.id_pareja = c.id_pareja)))
        )
 SELECT ca.id_canario,
    ca.id_criador,
    pa.id_padre,
    pa.id_madre,
    pp.id_padre AS id_abuelo_paterno,
    pp.id_madre AS id_abuela_paterna,
    pm.id_padre AS id_abuelo_materno,
    pm.id_madre AS id_abuela_materna
   FROM (((public.canario ca
     LEFT JOIN padres pa ON ((pa.id_canario = ca.id_canario)))
     LEFT JOIN padres pp ON ((pp.id_canario = pa.id_padre)))
     LEFT JOIN padres pm ON ((pm.id_canario = pa.id_madre)));


--
-- Name: variedad; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.variedad (
    id_variedad integer NOT NULL,
    codigo character varying(10) NOT NULL,
    nombre character varying(150) NOT NULL,
    tipo character(2) NOT NULL,
    serie character varying(50),
    sexo character(1) GENERATED ALWAYS AS (
CASE
    WHEN ((nombre)::text ~* '\mMACHO\M'::text) THEN 'M'::text
    WHEN ((nombre)::text ~* '\mHEMBRA\M'::text) THEN 'H'::text
    ELSE NULL::text
END) STORED,
    CONSTRAINT variedad_codigo_check CHECK ((btrim((codigo)::text) <> ''::text)),
    CONSTRAINT variedad_nombre_check CHECK ((btrim((nombre)::text) <> ''::text)),
    CONSTRAINT variedad_tipo_check CHECK ((tipo = ANY (ARRAY['CC'::bpchar, 'CP'::bpchar])))
);


--
-- Name: variedad_id_variedad_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.variedad_id_variedad_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: variedad_id_variedad_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.variedad_id_variedad_seq OWNED BY public.variedad.id_variedad;


--
-- Name: auditoria id_auditoria; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria ALTER COLUMN id_auditoria SET DEFAULT nextval('public.auditoria_id_auditoria_seq'::regclass);


--
-- Name: canario id_canario; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.canario ALTER COLUMN id_canario SET DEFAULT nextval('public.canario_id_canario_seq'::regclass);


--
-- Name: club id_club; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club ALTER COLUMN id_club SET DEFAULT nextval('public.club_id_club_seq'::regclass);


--
-- Name: cria id_cria; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cria ALTER COLUMN id_cria SET DEFAULT nextval('public.cria_id_cria_seq'::regclass);


--
-- Name: criador id_criador; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.criador ALTER COLUMN id_criador SET DEFAULT nextval('public.criador_id_criador_seq'::regclass);


--
-- Name: cruce id_cruce; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cruce ALTER COLUMN id_cruce SET DEFAULT nextval('public.cruce_id_cruce_seq'::regclass);


--
-- Name: jaula id_jaula; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jaula ALTER COLUMN id_jaula SET DEFAULT nextval('public.jaula_id_jaula_seq'::regclass);


--
-- Name: modo_operacion id_modo; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modo_operacion ALTER COLUMN id_modo SET DEFAULT nextval('public.modo_operacion_id_modo_seq'::regclass);


--
-- Name: mutacion id_mutacion; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mutacion ALTER COLUMN id_mutacion SET DEFAULT nextval('public.mutacion_id_mutacion_seq'::regclass);


--
-- Name: nidada id_nidada; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nidada ALTER COLUMN id_nidada SET DEFAULT nextval('public.nidada_id_nidada_seq'::regclass);


--
-- Name: pareja id_pareja; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pareja ALTER COLUMN id_pareja SET DEFAULT nextval('public.pareja_id_pareja_seq'::regclass);


--
-- Name: respaldo id_respaldo; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.respaldo ALTER COLUMN id_respaldo SET DEFAULT nextval('public.respaldo_id_respaldo_seq'::regclass);


--
-- Name: simulacion id_simulacion; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulacion ALTER COLUMN id_simulacion SET DEFAULT nextval('public.simulacion_id_simulacion_seq'::regclass);


--
-- Name: simulacion_resultado id_resultado; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulacion_resultado ALTER COLUMN id_resultado SET DEFAULT nextval('public.simulacion_resultado_id_resultado_seq'::regclass);


--
-- Name: solicitud_correccion id_solicitud; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solicitud_correccion ALTER COLUMN id_solicitud SET DEFAULT nextval('public.solicitud_correccion_id_solicitud_seq'::regclass);


--
-- Name: titulo id_titulo; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.titulo ALTER COLUMN id_titulo SET DEFAULT nextval('public.titulo_id_titulo_seq'::regclass);


--
-- Name: usuario id_usuario; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario ALTER COLUMN id_usuario SET DEFAULT nextval('public.usuario_id_usuario_seq'::regclass);


--
-- Name: variedad id_variedad; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variedad ALTER COLUMN id_variedad SET DEFAULT nextval('public.variedad_id_variedad_seq'::regclass);


--
-- Data for Name: auditoria; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: canario; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: club; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.club VALUES (1, 'CON');
INSERT INTO public.club VALUES (2, 'COV');
INSERT INTO public.club VALUES (3, 'COR');
INSERT INTO public.club VALUES (4, 'SOCH');


--
-- Data for Name: cria; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: criador; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: cruce; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: jaula; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: modo_operacion; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: mutacion; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.mutacion VALUES (1, 'Pastel', 'ligada al sexo recesiva');
INSERT INTO public.mutacion VALUES (2, 'Satiné', 'ligada al sexo recesiva');
INSERT INTO public.mutacion VALUES (3, 'Opal', 'autosómica recesiva');
INSERT INTO public.mutacion VALUES (4, 'Ino', 'autosómica recesiva');
INSERT INTO public.mutacion VALUES (5, 'Topacio', 'autosómica recesiva');
INSERT INTO public.mutacion VALUES (6, 'Eumo', 'autosómica recesiva');
INSERT INTO public.mutacion VALUES (7, 'Cobalto', 'autosómica recesiva');


--
-- Data for Name: nidada; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: pareja; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: php_sesion; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: respaldo; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: simulacion; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: simulacion_resultado; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: solicitud_correccion; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: titulo; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: usuario; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: variedad; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.variedad VALUES (1, 'D.001', 'BLANCO', 'CC', 'Serie Lipocrómicos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (2, 'D.002', 'BLANCO DOMINANTE', 'CC', 'Serie Lipocrómicos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (3, 'D.003', 'AMARILLO INTENSO', 'CC', 'Serie Lipocrómicos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (4, 'D.004', 'AMARILLO NEVADO', 'CC', 'Serie Lipocrómicos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (5, 'D.005', 'AMARILLO MARFIL INTENSO', 'CC', 'Serie Lipocrómicos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (6, 'D.006', 'AMARILLO MARFIL NEVADO', 'CC', 'Serie Lipocrómicos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (7, 'D.007', 'AMARILLO MOSAICO MACHO', 'CC', 'Serie Lipocrómicos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (8, 'D.008', 'AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Lipocrómicos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (9, 'D.009', 'AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Lipocrómicos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (10, 'D.010', 'AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Lipocrómicos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (11, 'D.011', 'ALBINO', 'CC', 'Serie Lipocrómicos Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (12, 'D.012', 'ALBINO DOMINANTE', 'CC', 'Serie Lipocrómicos Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (13, 'D.013', 'LUTINO INTENSO', 'CC', 'Serie Lipocrómicos Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (14, 'D.014', 'LUTINO NEVADO', 'CC', 'Serie Lipocrómicos Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (15, 'D.015', 'LUTINO MARFIL INTENSO', 'CC', 'Serie Lipocrómicos Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (16, 'D.016', 'LUTINO MARFIL NEVADO', 'CC', 'Serie Lipocrómicos Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (17, 'D.017', 'LUTINO MOSAICO MACHO', 'CC', 'Serie Lipocrómicos Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (18, 'D.018', 'LUTINO MOSAICO HEMBRA', 'CC', 'Serie Lipocrómicos Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (19, 'D.019', 'LUTINO MARFIL MOSAICO MACHO', 'CC', 'Serie Lipocrómicos Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (20, 'D.020', 'LUTINO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Lipocrómicos Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (21, 'D.021', 'AMARILLO INTENSO ALA BLANCA', 'CC', 'Serie Lipocrómicos Alas Blancas sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (22, 'D.022', 'AMARILLO NEVADO ALA BLANCA', 'CC', 'Serie Lipocrómicos Alas Blancas sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (23, 'D.023', 'AMARILLO INTENSO ALA BLANCA MARFIL', 'CC', 'Serie Lipocrómicos Alas Blancas sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (24, 'D.024', 'AMARILLO NEVADO ALA BLANCA MARFIL', 'CC', 'Serie Lipocrómicos Alas Blancas sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (25, 'D.025', 'AMARILLO MOSAICO ALA BLANCA MACHO', 'CC', 'Serie Lipocrómicos Alas Blancas sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (26, 'D.026', 'AMARILLO MOSAICO ALA BLANCA HEMBRA', 'CC', 'Serie Lipocrómicos Alas Blancas sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (27, 'D.027', 'AMARILLO MOSAICO ALA BLANCA MARFIL MACHO', 'CC', 'Serie Lipocrómicos Alas Blancas sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (28, 'D.028', 'AMARILLO MOSAICO ALA BLANCA MARFIL HEMBRA', 'CC', 'Serie Lipocrómicos Alas Blancas sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (29, 'D.029', 'LUTINO INTENSO ALA BLANCA', 'CC', 'Serie Lipocrómicos Alas Blancas Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (30, 'D.030', 'LUTINO NEVADO ALA BLANCA', 'CC', 'Serie Lipocrómicos Alas Blancas Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (31, 'D.031', 'LUTINO INTENSO ALA BLANCA MARFIL', 'CC', 'Serie Lipocrómicos Alas Blancas Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (32, 'D.032', 'LUTINO NEVADO ALA BLANCA MARFIL', 'CC', 'Serie Lipocrómicos Alas Blancas Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (33, 'D.033', 'LUTINO MOSAICO ALA BLANCA MACHO', 'CC', 'Serie Lipocrómicos Alas Blancas Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (34, 'D.034', 'LUTINO MOSAICO ALA BLANCA HEMBRA', 'CC', 'Serie Lipocrómicos Alas Blancas Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (35, 'D.035', 'LUTINO MOSAICO ALA BLANCA MARFIL MACHO', 'CC', 'Serie Lipocrómicos Alas Blancas Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (36, 'D.036', 'LUTINO MOSAICO ALA BLANCA MARFIL HEMBRA', 'CC', 'Serie Lipocrómicos Alas Blancas Inos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (37, 'D.037', 'AMARILLO INTENSO PICO AMARILLO', 'CC', 'Serie Lipocrómicos Pico Amarillo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (38, 'D.038', 'AMARILLO NEVADO PICO AMARILLO', 'CC', 'Serie Lipocrómicos Pico Amarillo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (39, 'D.039', 'LUTINO INTENSO PICO AMARILLO', 'CC', 'Serie Lipocrómicos Pico Amarillo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (40, 'D.040', 'LUTINO NEVADO PICO AMARILLO', 'CC', 'Serie Lipocrómicos Pico Amarillo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (41, 'D.041', 'AMARILLO MARFIL INTENSO PICO AMARILLO', 'CC', 'Serie Lipocrómicos Pico Amarillo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (42, 'D.042', 'AMARILLO MARFIL NEVADO PICO AMARILLO', 'CC', 'Serie Lipocrómicos Pico Amarillo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (43, 'D.043', 'LUTINO MARFIL INTENSO PICO AMARILLO', 'CC', 'Serie Lipocrómicos Pico Amarillo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (44, 'D.044', 'LUTINO MARFIL NEVADO PICO AMARILLO', 'CC', 'Serie Lipocrómicos Pico Amarillo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (45, 'D.045', 'AMARILLO MOSAICO MACHO PICO AMARILLO', 'CC', 'Serie Lipocrómicos Pico Amarillo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (46, 'D.046', 'AMARILLO MOSAICO HEMBRA PICO AMARILLO', 'CC', 'Serie Lipocrómicos Pico Amarillo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (47, 'D.047', 'LUTINO MOSAICO MACHO PICO AMARILLO', 'CC', 'Serie Lipocrómicos Pico Amarillo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (48, 'D.048', 'LUTINO MOSAICO HEMBRA PICO AMARILLO', 'CC', 'Serie Lipocrómicos Pico Amarillo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (49, 'D.049', 'ROJO INTENSO', 'CC', 'Serie Lipocrómicos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (50, 'D.050', 'ROJO NEVADO', 'CC', 'Serie Lipocrómicos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (51, 'D.051', 'ROJO MARFIL INTENSO', 'CC', 'Serie Lipocrómicos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (52, 'D.052', 'ROJO MARFIL NEVADO', 'CC', 'Serie Lipocrómicos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (53, 'D.053', 'ROJO MOSAICO MACHO', 'CC', 'Serie Lipocrómicos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (54, 'D.054', 'ROJO MOSAICO HEMBRA', 'CC', 'Serie Lipocrómicos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (55, 'D.055', 'ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Lipocrómicos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (56, 'D.056', 'ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Lipocrómicos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (57, 'D.057', 'RUBINO INTENSO', 'CC', 'Serie Lipocrómicos Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (58, 'D.058', 'RUBINO NEVADO', 'CC', 'Serie Lipocrómicos Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (59, 'D.059', 'RUBINO MARFIL INTENSO', 'CC', 'Serie Lipocrómicos Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (60, 'D.060', 'RUBINO MARFIL NEVADO', 'CC', 'Serie Lipocrómicos Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (61, 'D.061', 'RUBINO MOSAICO MACHO', 'CC', 'Serie Lipocrómicos Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (62, 'D.062', 'RUBINO MOSAICO HEMBRA', 'CC', 'Serie Lipocrómicos Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (63, 'D.063', 'RUBINO MARFIL MOSAICO MACHO', 'CC', 'Serie Lipocrómicos Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (64, 'D.064', 'RUBINO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Lipocrómicos Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (65, 'D.065', 'ROJO INTENSO ALA BLANCA', 'CC', 'Serie Lipocrómicos Alas Blancas con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (66, 'D.066', 'ROJO NEVADO ALA BLANCA', 'CC', 'Serie Lipocrómicos Alas Blancas con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (67, 'D.067', 'ROJO INTENSO ALA BLANCA MARFIL', 'CC', 'Serie Lipocrómicos Alas Blancas con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (68, 'D.068', 'ROJO NEVADO ALA BLANCA MARFIL', 'CC', 'Serie Lipocrómicos Alas Blancas con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (69, 'D.069', 'ROJO MOSAICO ALA BLANCA MACHO', 'CC', 'Serie Lipocrómicos Alas Blancas con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (70, 'D.070', 'ROJO MOSAICO ALA BLANCA HEMBRA', 'CC', 'Serie Lipocrómicos Alas Blancas con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (71, 'D.071', 'ROJO MOSAICO ALA BLANCA MARFIL MACHO', 'CC', 'Serie Lipocrómicos Alas Blancas con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (72, 'D.072', 'ROJO MOSAICO ALA BLANCA MARFIL HEMBRA', 'CC', 'Serie Lipocrómicos Alas Blancas con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (73, 'D.073', 'RUBINO INTENSO ALA BLANCA', 'CC', 'Serie Lipocrómicos Alas Blancas Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (74, 'D.074', 'RUBINO NEVADO ALA BLANCA', 'CC', 'Serie Lipocrómicos Alas Blancas Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (75, 'D.075', 'RUBINO INTENSO ALA BLANCA MARFIL', 'CC', 'Serie Lipocrómicos Alas Blancas Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (76, 'D.076', 'RUBINO NEVADO ALA BLANCA MARFIL', 'CC', 'Serie Lipocrómicos Alas Blancas Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (77, 'D.077', 'RUBINO MOSAICO ALA BLANCA MACHO', 'CC', 'Serie Lipocrómicos Alas Blancas Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (78, 'D.078', 'RUBINO MOSAICO ALA BLANCA HEMBRA', 'CC', 'Serie Lipocrómicos Alas Blancas Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (79, 'D.079', 'RUBINO MOSAICO ALA BLANCA MARFIL MACHO', 'CC', 'Serie Lipocrómicos Alas Blancas Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (80, 'D.080', 'RUBINO MOSAICO ALA BLANCA MARFIL HEMBRA', 'CC', 'Serie Lipocrómicos Alas Blancas Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (81, 'D.081', 'ROJO INTENSO ÚRUCUM', 'CC', 'Serie Lipocrómicos Úrucum con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (82, 'D.082', 'ROJO NEVADO ÚRUCUM', 'CC', 'Serie Lipocrómicos Úrucum con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (83, 'D.083', 'ROJO INTENSO ÚRUCUM MARFIL', 'CC', 'Serie Lipocrómicos Úrucum con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (84, 'D.084', 'ROJO NEVADO ÚRUCUM MARFIL', 'CC', 'Serie Lipocrómicos Úrucum con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (85, 'D.085', 'ROJO MOSAICO ÚRUCUM MACHO', 'CC', 'Serie Lipocrómicos Úrucum con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (86, 'D.086', 'ROJO MOSAICO ÚRUCUM HEMBRA', 'CC', 'Serie Lipocrómicos Úrucum con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (87, 'D.087', 'ROJO MOSAICO ÚRUCUM MARFIL MACHO', 'CC', 'Serie Lipocrómicos Úrucum con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (88, 'D.088', 'ROJO MOSAICO ÚRUCUM MARFIL HEMBRA', 'CC', 'Serie Lipocrómicos Úrucum con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (89, 'D.089', 'RUBINO INTENSO ÚRUCUM', 'CC', 'Serie Lipocrómicos Úrucum Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (90, 'D.090', 'RUBINO NEVADO ÚRUCUM', 'CC', 'Serie Lipocrómicos Úrucum Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (91, 'D.091', 'RUBINO INTENSO ÚRUCUM MARFIL', 'CC', 'Serie Lipocrómicos Úrucum Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (92, 'D.092', 'RUBINO NEVADO ÚRUCUM MARFIL', 'CC', 'Serie Lipocrómicos Úrucum Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (93, 'D.093', 'RUBINO MOSAICO ÚRUCUM MACHO', 'CC', 'Serie Lipocrómicos Úrucum Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (94, 'D.094', 'RUBINO MOSAICO ÚRUCUM HEMBRA', 'CC', 'Serie Lipocrómicos Úrucum Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (95, 'D.095', 'RUBINO MOSAICO ÚRUCUM MARFIL MACHO', 'CC', 'Serie Lipocrómicos Úrucum Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (96, 'D.096', 'RUBINO MOSAICO ÚRUCUM MARFIL HEMBRA', 'CC', 'Serie Lipocrómicos Úrucum Inos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (97, 'D.097', 'NEGRO BLANCO', 'CC', 'Serie Negro sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (98, 'D.098', 'NEGRO BLANCO DOMINANTE', 'CC', 'Serie Negro sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (99, 'D.099', 'NEGRO AMARILLO INTENSO', 'CC', 'Serie Negro sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (100, 'D.100', 'NEGRO AMARILLO NEVADO', 'CC', 'Serie Negro sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (101, 'D.101', 'NEGRO AMARILLO MARFIL INTENSO', 'CC', 'Serie Negro sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (102, 'D.102', 'NEGRO AMARILLO MARFIL NEVADO', 'CC', 'Serie Negro sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (103, 'D.103', 'NEGRO AMARILLO MOSAICO MACHO', 'CC', 'Serie Negro sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (104, 'D.104', 'NEGRO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Negro sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (105, 'D.105', 'NEGRO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (106, 'D.106', 'NEGRO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (107, 'D.107', 'NEGRO ROJO INTENSO', 'CC', 'Serie Negro con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (108, 'D.108', 'NEGRO ROJO NEVADO', 'CC', 'Serie Negro con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (109, 'D.109', 'NEGRO ROJO MARFIL INTENSO', 'CC', 'Serie Negro con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (110, 'D.110', 'NEGRO ROJO MARFIL NEVADO', 'CC', 'Serie Negro con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (111, 'D.111', 'NEGRO ROJO MOSAICO MACHO', 'CC', 'Serie Negro con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (112, 'D.112', 'NEGRO ROJO MOSAICO HEMBRA', 'CC', 'Serie Negro con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (113, 'D.113', 'NEGRO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (114, 'D.114', 'NEGRO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (115, 'D.115', 'BRUNO BLANCO', 'CC', 'Serie Bruno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (116, 'D.116', 'BRUNO BLANCO DOMINANTE', 'CC', 'Serie Bruno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (117, 'D.117', 'BRUNO AMARILLO INTENSO', 'CC', 'Serie Bruno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (118, 'D.118', 'BRUNO AMARILLO NEVADO', 'CC', 'Serie Bruno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (119, 'D.119', 'BRUNO AMARILLO MARFIL INTENSO', 'CC', 'Serie Bruno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (120, 'D.120', 'BRUNO AMARILLO MARFIL NEVADO', 'CC', 'Serie Bruno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (121, 'D.121', 'BRUNO AMARILLO MOSAICO MACHO', 'CC', 'Serie Bruno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (122, 'D.122', 'BRUNO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Bruno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (123, 'D.123', 'BRUNO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (124, 'D.124', 'BRUNO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (125, 'D.125', 'BRUNO ROJO INTENSO', 'CC', 'Serie Bruno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (126, 'D.126', 'BRUNO ROJO NEVADO', 'CC', 'Serie Bruno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (127, 'D.127', 'BRUNO ROJO MARFIL INTENSO', 'CC', 'Serie Bruno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (128, 'D.128', 'BRUNO ROJO MARFIL NEVADO', 'CC', 'Serie Bruno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (129, 'D.129', 'BRUNO ROJO MOSAICO MACHO', 'CC', 'Serie Bruno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (130, 'D.130', 'BRUNO ROJO MOSAICO HEMBRA', 'CC', 'Serie Bruno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (131, 'D.131', 'BRUNO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (132, 'D.132', 'BRUNO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (133, 'D.133', 'ÁGATA BLANCO', 'CC', 'Serie Ágata sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (134, 'D.134', 'ÁGATA BLANCO DOMINANTE', 'CC', 'Serie Ágata sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (135, 'D.135', 'ÁGATA AMARILLO INTENSO', 'CC', 'Serie Ágata sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (136, 'D.136', 'ÁGATA AMARILLO NEVADO', 'CC', 'Serie Ágata sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (137, 'D.137', 'ÁGATA AMARILLO MARFIL INTENSO', 'CC', 'Serie Ágata sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (138, 'D.138', 'ÁGATA AMARILLO MARFIL NEVADO', 'CC', 'Serie Ágata sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (139, 'D.139', 'ÁGATA AMARILLO MOSAICO MACHO', 'CC', 'Serie Ágata sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (140, 'D.140', 'ÁGATA AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Ágata sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (141, 'D.141', 'ÁGATA AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (142, 'D.142', 'ÁGATA AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (143, 'D.143', 'ÁGATA ROJO INTENSO', 'CC', 'Serie Ágata con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (144, 'D.144', 'ÁGATA ROJO NEVADO', 'CC', 'Serie Ágata con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (145, 'D.145', 'ÁGATA ROJO MARFIL INTENSO', 'CC', 'Serie Ágata con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (146, 'D.146', 'ÁGATA ROJO MARFIL NEVADO', 'CC', 'Serie Ágata con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (147, 'D.147', 'ÁGATA ROJO MOSAICO MACHO', 'CC', 'Serie Ágata con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (148, 'D.148', 'ÁGATA ROJO MOSAICO HEMBRA', 'CC', 'Serie Ágata con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (149, 'D.149', 'ÁGATA ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (150, 'D.150', 'ÁGATA ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (151, 'D.151', 'ISABEL BLANCO', 'CC', 'Serie Isabel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (152, 'D.152', 'ISABEL BLANCO DOMINANTE', 'CC', 'Serie Isabel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (153, 'D.153', 'ISABEL AMARILLO INTENSO', 'CC', 'Serie Isabel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (154, 'D.154', 'ISABEL AMARILLO NEVADO', 'CC', 'Serie Isabel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (155, 'D.155', 'ISABEL AMARILLO MARFIL INTENSO', 'CC', 'Serie Isabel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (156, 'D.156', 'ISABEL AMARILLO MARFIL NEVADO', 'CC', 'Serie Isabel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (157, 'D.157', 'ISABEL AMARILLO MOSAICO MACHO', 'CC', 'Serie Isabel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (158, 'D.158', 'ISABEL AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Isabel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (159, 'D.159', 'ISABEL AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (160, 'D.160', 'ISABEL AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (161, 'D.161', 'ISABEL ROJO INTENSO', 'CC', 'Serie Isabel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (162, 'D.162', 'ISABEL ROJO NEVADO', 'CC', 'Serie Isabel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (163, 'D.163', 'ISABEL ROJO MARFIL INTENSO', 'CC', 'Serie Isabel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (164, 'D.164', 'ISABEL ROJO MARFIL NEVADO', 'CC', 'Serie Isabel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (165, 'D.165', 'ISABEL ROJO MOSAICO MACHO', 'CC', 'Serie Isabel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (166, 'D.166', 'ISABEL ROJO MOSAICO HEMBRA', 'CC', 'Serie Isabel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (167, 'D.167', 'ISABEL ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (168, 'D.168', 'ISABEL ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (169, 'D.169', 'NEGRO PASTEL BLANCO', 'CC', 'Serie Negro Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (170, 'D.170', 'NEGRO PASTEL BLANCO DOMINANTE', 'CC', 'Serie Negro Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (171, 'D.171', 'NEGRO PASTEL AMARILLO INTENSO', 'CC', 'Serie Negro Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (172, 'D.172', 'NEGRO PASTEL AMARILLO NEVADO', 'CC', 'Serie Negro Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (173, 'D.173', 'NEGRO PASTEL AMARILLO MARFIL INTENSO', 'CC', 'Serie Negro Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (174, 'D.174', 'NEGRO PASTEL AMARILLO MARFIL NEVADO', 'CC', 'Serie Negro Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (175, 'D.175', 'NEGRO PASTEL AMARILLO MOSAICO MACHO', 'CC', 'Serie Negro Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (176, 'D.176', 'NEGRO PASTEL AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Negro Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (177, 'D.177', 'NEGRO PASTEL AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (178, 'D.178', 'NEGRO PASTEL AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (179, 'D.179', 'NEGRO PASTEL ROJO INTENSO', 'CC', 'Serie Negro Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (180, 'D.180', 'NEGRO PASTEL ROJO NEVADO', 'CC', 'Serie Negro Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (181, 'D.181', 'NEGRO PASTEL ROJO MARFIL INTENSO', 'CC', 'Serie Negro Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (182, 'D.182', 'NEGRO PASTEL ROJO MARFIL NEVADO', 'CC', 'Serie Negro Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (183, 'D.183', 'NEGRO PASTEL ROJO MOSAICO MACHO', 'CC', 'Serie Negro Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (184, 'D.184', 'NEGRO PASTEL ROJO MOSAICO HEMBRA', 'CC', 'Serie Negro Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (185, 'D.185', 'NEGRO PASTEL ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (186, 'D.186', 'NEGRO PASTEL ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (187, 'D.187', 'BRUNO PASTEL BLANCO', 'CC', 'Serie Bruno Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (188, 'D.188', 'BRUNO PASTEL BLANCO DOMINANTE', 'CC', 'Serie Bruno Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (189, 'D.189', 'BRUNO PASTEL AMARILLO INTENSO', 'CC', 'Serie Bruno Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (190, 'D.190', 'BRUNO PASTEL AMARILLO NEVADO', 'CC', 'Serie Bruno Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (191, 'D.191', 'BRUNO PASTEL AMARILLO MARFIL INTENSO', 'CC', 'Serie Bruno Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (192, 'D.192', 'BRUNO PASTEL AMARILLO MARFIL NEVADO', 'CC', 'Serie Bruno Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (193, 'D.193', 'BRUNO PASTEL AMARILLO MOSAICO MACHO', 'CC', 'Serie Bruno Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (194, 'D.194', 'BRUNO PASTEL AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Bruno Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (195, 'D.195', 'BRUNO PASTEL AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (196, 'D.196', 'BRUNO PASTEL AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (197, 'D.197', 'BRUNO PASTEL ROJO INTENSO', 'CC', 'Serie Bruno Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (198, 'D.198', 'BRUNO PASTEL ROJO NEVADO', 'CC', 'Serie Bruno Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (199, 'D.199', 'BRUNO PASTEL ROJO MARFIL INTENSO', 'CC', 'Serie Bruno Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (200, 'D.200', 'BRUNO PASTEL ROJO MARFIL NEVADO', 'CC', 'Serie Bruno Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (201, 'D.201', 'BRUNO PASTEL ROJO MOSAICO MACHO', 'CC', 'Serie Bruno Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (202, 'D.202', 'BRUNO PASTEL ROJO MOSAICO HEMBRA', 'CC', 'Serie Bruno Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (203, 'D.203', 'BRUNO PASTEL ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (204, 'D.204', 'BRUNO PASTEL ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (205, 'D.205', 'ÁGATA PASTEL BLANCO', 'CC', 'Serie Ágata Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (206, 'D.206', 'ÁGATA PASTEL BLANCO DOMINANTE', 'CC', 'Serie Ágata Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (207, 'D.207', 'ÁGATA PASTEL AMARILLO INTENSO', 'CC', 'Serie Ágata Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (208, 'D.208', 'ÁGATA PASTEL AMARILLO NEVADO', 'CC', 'Serie Ágata Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (209, 'D.209', 'ÁGATA PASTEL AMARILLO MARFIL INTENSO', 'CC', 'Serie Ágata Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (210, 'D.210', 'ÁGATA PASTEL AMARILLO MARFIL NEVADO', 'CC', 'Serie Ágata Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (211, 'D.211', 'ÁGATA PASTEL AMARILLO MOSAICO MACHO', 'CC', 'Serie Ágata Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (212, 'D.212', 'ÁGATA PASTEL AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Ágata Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (213, 'D.213', 'ÁGATA PASTEL AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (214, 'D.214', 'ÁGATA PASTEL AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (215, 'D.215', 'ÁGATA PASTEL ROJO INTENSO', 'CC', 'Serie Ágata Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (216, 'D.216', 'ÁGATA PASTEL ROJO NEVADO', 'CC', 'Serie Ágata Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (217, 'D.217', 'ÁGATA PASTEL ROJO MARFIL INTENSO', 'CC', 'Serie Ágata Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (218, 'D.218', 'ÁGATA PASTEL ROJO MARFIL NEVADO', 'CC', 'Serie Ágata Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (219, 'D.219', 'ÁGATA PASTEL ROJO MOSAICO MACHO', 'CC', 'Serie Ágata Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (220, 'D.220', 'ÁGATA PASTEL ROJO MOSAICO HEMBRA', 'CC', 'Serie Ágata Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (221, 'D.221', 'ÁGATA PASTEL ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (222, 'D.222', 'ÁGATA PASTEL ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (223, 'D.223', 'ISABEL PASTEL BLANCO', 'CC', 'Serie Isabel Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (224, 'D.224', 'ISABEL PASTEL BLANCO DOMINANTE', 'CC', 'Serie Isabel Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (225, 'D.225', 'ISABEL PASTEL AMARILLO INTENSO', 'CC', 'Serie Isabel Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (226, 'D.226', 'ISABEL PASTEL AMARILLO NEVADO', 'CC', 'Serie Isabel Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (227, 'D.227', 'ISABEL PASTEL AMARILLO MARFIL INTENSO', 'CC', 'Serie Isabel Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (228, 'D.228', 'ISABEL PASTEL AMARILLO MARFIL NEVADO', 'CC', 'Serie Isabel Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (229, 'D.229', 'ISABEL PASTEL AMARILLO MOSAICO MACHO', 'CC', 'Serie Isabel Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (230, 'D.230', 'ISABEL PASTEL AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Isabel Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (231, 'D.231', 'ISABEL PASTEL AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (232, 'D.232', 'ISABEL PASTEL AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Pastel sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (233, 'D.233', 'ISABEL PASTEL ROJO INTENSO', 'CC', 'Serie Isabel Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (234, 'D.234', 'ISABEL PASTEL ROJO NEVADO', 'CC', 'Serie Isabel Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (235, 'D.235', 'ISABEL PASTEL ROJO MARFIL INTENSO', 'CC', 'Serie Isabel Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (236, 'D.236', 'ISABEL PASTEL ROJO MARFIL NEVADO', 'CC', 'Serie Isabel Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (237, 'D.237', 'ISABEL PASTEL ROJO MOSAICO MACHO', 'CC', 'Serie Isabel Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (238, 'D.238', 'ISABEL PASTEL ROJO MOSAICO HEMBRA', 'CC', 'Serie Isabel Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (239, 'D.239', 'ISABEL PASTEL ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (240, 'D.240', 'ISABEL PASTEL ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Pastel con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (241, 'D.241', 'NEGRO OPALO BLANCO', 'CC', 'Serie Negro Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (242, 'D.242', 'NEGRO OPALO BLANCO DOMINANTE', 'CC', 'Serie Negro Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (243, 'D.243', 'NEGRO OPALO AMARILLO INTENSO', 'CC', 'Serie Negro Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (244, 'D.244', 'NEGRO OPALO AMARILLO NEVADO', 'CC', 'Serie Negro Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (245, 'D.245', 'NEGRO OPALO AMARILLO MARFIL INTENSO', 'CC', 'Serie Negro Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (246, 'D.246', 'NEGRO OPALO AMARILLO MARFIL NEVADO', 'CC', 'Serie Negro Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (247, 'D.247', 'NEGRO OPALO AMARILLO MOSAICO MACHO', 'CC', 'Serie Negro Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (248, 'D.248', 'NEGRO OPALO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Negro Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (249, 'D.249', 'NEGRO OPALO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (250, 'D.250', 'NEGRO OPALO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (251, 'D.251', 'NEGRO OPALO ROJO INTENSO', 'CC', 'Serie Negros Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (252, 'D.252', 'NEGRO OPALO ROJO NEVADO', 'CC', 'Serie Negros Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (253, 'D.253', 'NEGRO OPALO ROJO MARFIL INTENSO', 'CC', 'Serie Negros Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (254, 'D.254', 'NEGRO OPALO ROJO MARFIL NEVADO', 'CC', 'Serie Negros Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (255, 'D.255', 'NEGRO OPALO ROJO MOSAICO MACHO', 'CC', 'Serie Negros Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (256, 'D.256', 'NEGRO OPALO ROJO MOSAICO HEMBRA', 'CC', 'Serie Negros Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (257, 'D.257', 'NEGRO OPALO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Negros Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (258, 'D.258', 'NEGRO OPALO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negros Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (259, 'D.259', 'BRUNO OPALO BLANCO', 'CC', 'Serie Bruno Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (260, 'D.260', 'BRUNO OPALO BLANCO DOMINANTE', 'CC', 'Serie Bruno Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (261, 'D.261', 'BRUNO OPALO AMARILLO INTENSO', 'CC', 'Serie Bruno Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (262, 'D.262', 'BRUNO OPALO AMARILLO NEVADO', 'CC', 'Serie Bruno Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (263, 'D.263', 'BRUNO OPALO AMARILLO MARFIL INTENSO', 'CC', 'Serie Bruno Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (264, 'D.264', 'BRUNO OPALO AMARILLO MARFIL NEVADO', 'CC', 'Serie Bruno Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (265, 'D.265', 'BRUNO OPALO AMARILLO MOSAICO MACHO', 'CC', 'Serie Bruno Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (266, 'D.266', 'BRUNO OPALO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Bruno Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (267, 'D.267', 'BRUNO OPALO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (268, 'D.268', 'BRUNO OPALO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (269, 'D.269', 'BRUNO OPALO ROJO INTENSO', 'CC', 'Serie Bruno Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (270, 'D.270', 'BRUNO OPALO ROJO NEVADO', 'CC', 'Serie Bruno Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (271, 'D.271', 'BRUNO OPALO ROJO MARFIL INTENSO', 'CC', 'Serie Bruno Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (272, 'D.272', 'BRUNO OPALO ROJO MARFIL NEVADO', 'CC', 'Serie Bruno Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (273, 'D.273', 'BRUNO OPALO ROJO MOSAICO MACHO', 'CC', 'Serie Bruno Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (274, 'D.274', 'BRUNO OPALO ROJO MOSAICO HEMBRA', 'CC', 'Serie Bruno Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (275, 'D.275', 'BRUNO OPALO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (276, 'D.276', 'BRUNO OPALO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (277, 'D.277', 'ÁGATA OPALO BLANCO', 'CC', 'Serie Ágata Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (278, 'D.278', 'ÁGATA OPALO BLANCO DOMINANTE', 'CC', 'Serie Ágata Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (279, 'D.279', 'ÁGATA OPALO AMARILLO INTENSO', 'CC', 'Serie Ágata Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (280, 'D.280', 'ÁGATA OPALO AMARILLO NEVADO', 'CC', 'Serie Ágata Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (281, 'D.281', 'ÁGATA OPALO AMARILLO MARFIL INTENSO', 'CC', 'Serie Ágata Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (282, 'D.282', 'ÁGATA OPALO AMARILLO MARFIL NEVADO', 'CC', 'Serie Ágata Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (283, 'D.283', 'ÁGATA OPALO AMARILLO MOSAICO MACHO', 'CC', 'Serie Ágata Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (284, 'D.284', 'ÁGATA OPALO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Ágata Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (285, 'D.285', 'ÁGATA OPALO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (286, 'D.286', 'ÁGATA OPALO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (287, 'D.287', 'ÁGATA OPALO ROJO INTENSO', 'CC', 'Serie Ágata Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (288, 'D.288', 'ÁGATA OPALO ROJO NEVADO', 'CC', 'Serie Ágata Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (289, 'D.289', 'ÁGATA OPALO ROJO MARFIL INTENSO', 'CC', 'Serie Ágata Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (290, 'D.290', 'ÁGATA OPALO ROJO MARFIL NEVADO', 'CC', 'Serie Ágata Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (291, 'D.291', 'ÁGATA OPALO ROJO MOSAICO MACHO', 'CC', 'Serie Ágata Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (292, 'D.292', 'ÁGATA OPALO ROJO MOSAICO HEMBRA', 'CC', 'Serie Ágata Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (293, 'D.293', 'ÁGATA OPALO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (294, 'D.294', 'ÁGATA OPALO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (295, 'D.295', 'ISABEL OPALO BLANCO', 'CC', 'Serie Isabel Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (296, 'D.296', 'ISABEL OPALO BLANCO DOMINANTE', 'CC', 'Serie Isabel Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (297, 'D.297', 'ISABEL OPALO AMARILLO INTENSO', 'CC', 'Serie Isabel Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (298, 'D.298', 'ISABEL OPALO AMARILLO NEVADO', 'CC', 'Serie Isabel Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (299, 'D.299', 'ISABEL OPALO AMARILLO MARFIL INTENSO', 'CC', 'Serie Isabel Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (300, 'D.300', 'ISABEL OPALO AMARILLO MARFIL NEVADO', 'CC', 'Serie Isabel Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (301, 'D.301', 'ISABEL OPALO AMARILLO MOSAICO MACHO', 'CC', 'Serie Isabel Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (302, 'D.302', 'ISABEL OPALO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Isabel Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (303, 'D.303', 'ISABEL OPALO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (304, 'D.304', 'ISABEL OPALO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Opalo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (305, 'D.305', 'ISABEL OPALO ROJO INTENSO', 'CC', 'Serie Isabel Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (306, 'D.306', 'ISABEL OPALO ROJO NEVADO', 'CC', 'Serie Isabel Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (307, 'D.307', 'ISABEL OPALO ROJO MARFIL INTENSO', 'CC', 'Serie Isabel Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (308, 'D.308', 'ISABEL OPALO ROJO MARFIL NEVADO', 'CC', 'Serie Isabel Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (309, 'D.309', 'ISABEL OPALO ROJO MOSAICO MACHO', 'CC', 'Serie Isabel Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (310, 'D.310', 'ISABEL OPALO ROJO MOSAICO HEMBRA', 'CC', 'Serie Isabel Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (311, 'D.311', 'ISABEL OPALO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (312, 'D.312', 'ISABEL OPALO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Opalo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (313, 'D.313', 'FEO ALBINO MACHO', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (314, 'D.314', 'FEO ALBINO DOMINANTE MACHO', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (315, 'D.315', 'FEO ALBINO HEMBRA', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (316, 'D.316', 'FEO ALBINO DOMINANTE HEMBRA', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (317, 'D.317', 'FEO LUTINO INTENSO MACHO', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (318, 'D.318', 'FEO LUTINO NEVADO MACHO', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (319, 'D.319', 'FEO LUTINO INTENSO HEMBRA', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (320, 'D.320', 'FEO LUTINO NEVADO HEMBRA', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (321, 'D.321', 'FEO LUTINO MARFIL INTENSO MACHO', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (322, 'D.322', 'FEO LUTINO MARFIL NEVADO MACHO', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (323, 'D.323', 'FEO LUTINO MARFIL INTENSO HEMBRA', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (324, 'D.324', 'FEO LUTINO MARFIL NEVADO HEMBRA', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (325, 'D.325', 'FEO LUTINO MOSAICO MACHO', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (326, 'D.326', 'FEO LUTINO MOSAICO HEMBRA', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (327, 'D.327', 'FEO LUTINO MARFIL MOSAICO MACHO', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (328, 'D.328', 'FEO LUTINO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Feos sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (329, 'D.329', 'FEO RUBINO INTENSO MACHO', 'CC', 'Serie Feos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (330, 'D.330', 'FEO RUBINO NEVADO MACHO', 'CC', 'Serie Feos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (331, 'D.331', 'FEO RUBINO INTENSO HEMBRA', 'CC', 'Serie Feos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (332, 'D.332', 'FEO RUBINO NEVADO HEMBRA', 'CC', 'Serie Feos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (333, 'D.333', 'FEO RUBINO MARFIL INTENSO MACHO', 'CC', 'Serie Feos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (334, 'D.334', 'FEO RUBINO MARFIL NEVADO MACHO', 'CC', 'Serie Feos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (335, 'D.335', 'FEO RUBINO MARFIL INTENSO HEMBRA', 'CC', 'Serie Feos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (336, 'D.336', 'FEO RUBINO MARFIL NEVADO HEMBRA', 'CC', 'Serie Feos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (337, 'D.337', 'FEO RUBINO MOSAICO MACHO', 'CC', 'Serie Feos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (338, 'D.338', 'FEO RUBINO MOSAICO HEMBRA', 'CC', 'Serie Feos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (339, 'D.339', 'FEO RUBINO MARFIL MOSAICO MACHO', 'CC', 'Serie Feos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (340, 'D.340', 'FEO RUBINO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Feos con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (341, 'D.341', 'BRUNO SATINÉ BLANCO', 'CC', 'Serie Bruno Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (342, 'D.342', 'BRUNO SATINÉ BLANCO DOMINANTE', 'CC', 'Serie Bruno Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (343, 'D.343', 'BRUNO SATINÉ AMARILLO INTENSO', 'CC', 'Serie Bruno Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (344, 'D.344', 'BRUNO SATINÉ AMARILLO NEVADO', 'CC', 'Serie Bruno Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (345, 'D.345', 'BRUNO SATINÉ AMARILLO MARFIL INTENSO', 'CC', 'Serie Bruno Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (346, 'D.346', 'BRUNO SATINÉ AMARILLO MARFIL NEVADO', 'CC', 'Serie Bruno Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (347, 'D.347', 'BRUNO SATINÉ AMARILLO MOSAICO MACHO', 'CC', 'Serie Bruno Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (348, 'D.348', 'BRUNO SATINÉ AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Bruno Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (349, 'D.349', 'BRUNO SATINÉ AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (350, 'D.350', 'BRUNO SATINÉ AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (351, 'D.351', 'BRUNO SATINÉ ROJO INTENSO', 'CC', 'Serie Bruno Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (352, 'D.352', 'BRUNO SATINÉ ROJO NEVADO', 'CC', 'Serie Bruno Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (353, 'D.353', 'BRUNO SATINÉ ROJO MARFIL INTENSO', 'CC', 'Serie Bruno Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (354, 'D.354', 'BRUNO SATINÉ ROJO MARFIL NEVADO', 'CC', 'Serie Bruno Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (355, 'D.355', 'BRUNO SATINÉ ROJO MOSAICO MACHO', 'CC', 'Serie Bruno Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (356, 'D.356', 'BRUNO SATINÉ ROJO MOSAICO HEMBRA', 'CC', 'Serie Bruno Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (357, 'D.357', 'BRUNO SATINÉ ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (358, 'D.358', 'BRUNO SATINÉ ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (359, 'D.359', 'ISABEL SATINÉ BLANCO', 'CC', 'Serie Isabel Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (360, 'D.360', 'ISABEL SATINÉ BLANCO DOMINANTE', 'CC', 'Serie Isabel Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (361, 'D.361', 'ISABEL SATINÉ AMARILLO INTENSO', 'CC', 'Serie Isabel Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (362, 'D.362', 'ISABEL SATINÉ AMARILLO NEVADO', 'CC', 'Serie Isabel Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (363, 'D.363', 'ISABEL SATINÉ AMARILLO MARFIL INTENSO', 'CC', 'Serie Isabel Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (364, 'D.364', 'ISABEL SATINÉ AMARILLO MARFIL NEVADO', 'CC', 'Serie Isabel Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (365, 'D.365', 'ISABEL SATINÉ AMARILLO MOSAICO MACHO', 'CC', 'Serie Isabel Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (366, 'D.366', 'ISABEL SATINÉ AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Isabel Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (367, 'D.367', 'ISABEL SATINÉ AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (368, 'D.368', 'ISABEL SATINÉ AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Satiné sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (369, 'D.369', 'ISABEL SATINÉ ROJO INTENSO', 'CC', 'Serie Isabel Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (370, 'D.370', 'ISABEL SATINÉ ROJO NEVADO', 'CC', 'Serie Isabel Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (371, 'D.371', 'ISABEL SATINÉ ROJO MARFIL INTENSO', 'CC', 'Serie Isabel Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (372, 'D.372', 'ISABEL SATINÉ ROJO MARFIL NEVADO', 'CC', 'Serie Isabel Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (373, 'D.373', 'ISABEL SATINÉ ROJO MOSAICO MACHO', 'CC', 'Serie Isabel Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (374, 'D.374', 'ISABEL SATINÉ ROJO MOSAICO HEMBRA', 'CC', 'Serie Isabel Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (375, 'D.375', 'ISABEL SATINÉ ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (376, 'D.376', 'ISABEL SATINÉ ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Satiné con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (377, 'D.377', 'NEGRO ALAS GRISES BLANCO', 'CC', 'Serie Negro Alas Grises sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (378, 'D.378', 'NEGRO ALAS GRISES BLANCO DOMINANTE', 'CC', 'Serie Negro Alas Grises sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (379, 'D.379', 'NEGRO ALAS GRISES AMARILLO INTENSO', 'CC', 'Serie Negro Alas Grises sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (380, 'D.380', 'NEGRO ALAS GRISES AMARILLO NEVADO', 'CC', 'Serie Negro Alas Grises sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (381, 'D.381', 'NEGRO ALAS GRISES AMARILLO MARFIL INTENSO', 'CC', 'Serie Negro Alas Grises sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (382, 'D.382', 'NEGRO ALAS GRISES AMARILLO MARFIL NEVADO', 'CC', 'Serie Negro Alas Grises sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (383, 'D.383', 'NEGRO ALAS GRISES AMARILLO MOSAICO MACHO', 'CC', 'Serie Negro Alas Grises sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (384, 'D.384', 'NEGRO ALAS GRISES AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Negro Alas Grises sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (385, 'D.385', 'NEGRO ALAS GRISES AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Alas Grises sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (386, 'D.386', 'NEGRO ALAS GRISES AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Alas Grises sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (387, 'D.387', 'NEGRO ALAS GRISES ROJO INTENSO', 'CC', 'Serie Negro Alas Grises con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (388, 'D.388', 'NEGRO ALAS GRISES ROJO NEVADO', 'CC', 'Serie Negro Alas Grises con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (389, 'D.389', 'NEGRO ALAS GRISES ROJO MARFIL INTENSO', 'CC', 'Serie Negro Alas Grises con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (390, 'D.390', 'NEGRO ALAS GRISES ROJO MARFIL NEVADO', 'CC', 'Serie Negro Alas Grises con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (391, 'D.391', 'NEGRO ALAS GRISES ROJO MOSAICO MACHO', 'CC', 'Serie Negro Alas Grises con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (392, 'D.392', 'NEGRO ALAS GRISES ROJO MOSAICO HEMBRA', 'CC', 'Serie Negro Alas Grises con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (393, 'D.393', 'NEGRO ALAS GRISES ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Alas Grises con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (394, 'D.394', 'NEGRO ALAS GRISES ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Alas Grises con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (395, 'D.395', 'NEGRO TOPACIO BLANCO', 'CC', 'Serie Negro Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (396, 'D.396', 'NEGRO TOPACIO BLANCO DOMINANTE', 'CC', 'Serie Negro Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (397, 'D.397', 'NEGRO TOPACIO AMARILLO INTENSO', 'CC', 'Serie Negro Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (398, 'D.398', 'NEGRO TOPACIO AMARILLO NEVADO', 'CC', 'Serie Negro Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (399, 'D.399', 'NEGRO TOPACIO AMARILLO MARFIL INTENSO', 'CC', 'Serie Negro Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (400, 'D.400', 'NEGRO TOPACIO AMARILLO MARFIL NEVADO', 'CC', 'Serie Negro Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (401, 'D.401', 'NEGRO TOPACIO AMARILLO MOSAICO MACHO', 'CC', 'Serie Negro Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (402, 'D.402', 'NEGRO TOPACIO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Negro Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (403, 'D.403', 'NEGRO TOPACIO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (404, 'D.404', 'NEGRO TOPACIO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (405, 'D.405', 'NEGRO TOPACIO ROJO INTENSO', 'CC', 'Serie Negro Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (406, 'D.406', 'NEGRO TOPACIO ROJO NEVADO', 'CC', 'Serie Negro Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (407, 'D.407', 'NEGRO TOPACIO ROJO MARFIL INTENSO', 'CC', 'Serie Negro Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (408, 'D.408', 'NEGRO TOPACIO ROJO MARFIL NEVADO', 'CC', 'Serie Negro Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (409, 'D.409', 'NEGRO TOPACIO ROJO MOSAICO MACHO', 'CC', 'Serie Negro Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (410, 'D.410', 'NEGRO TOPACIO ROJO MOSAICO HEMBRA', 'CC', 'Serie Negro Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (411, 'D.411', 'NEGRO TOPACIO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (412, 'D.412', 'NEGRO TOPACIO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (413, 'D.413', 'BRUNO TOPACIO BLANCO', 'CC', 'Serie Bruno Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (414, 'D.414', 'BRUNO TOPACIO BLANCO DOMINANTE', 'CC', 'Serie Bruno Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (415, 'D.415', 'BRUNO TOPACIO AMARILLO INTENSO', 'CC', 'Serie Bruno Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (416, 'D.416', 'BRUNO TOPACIO AMARILLO NEVADO', 'CC', 'Serie Bruno Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (417, 'D.417', 'BRUNO TOPACIO AMARILLO MARFIL INTENSO', 'CC', 'Serie Bruno Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (418, 'D.418', 'BRUNO TOPACIO AMARILLO MARFIL NEVADO', 'CC', 'Serie Bruno Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (419, 'D.419', 'BRUNO TOPACIO AMARILLO MOSAICO MACHO', 'CC', 'Serie Bruno Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (420, 'D.420', 'BRUNO TOPACIO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Bruno Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (421, 'D.421', 'BRUNO TOPACIO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (422, 'D.422', 'BRUNO TOPACIO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (423, 'D.423', 'BRUNO TOPACIO ROJO INTENSO', 'CC', 'Serie Bruno Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (424, 'D.424', 'BRUNO TOPACIO ROJO NEVADO', 'CC', 'Serie Bruno Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (425, 'D.425', 'BRUNO TOPACIO ROJO MARFIL INTENSO', 'CC', 'Serie Bruno Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (426, 'D.426', 'BRUNO TOPACIO ROJO MARFIL NEVADO', 'CC', 'Serie Bruno Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (427, 'D.427', 'BRUNO TOPACIO ROJO MOSAICO MACHO', 'CC', 'Serie Bruno Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (428, 'D.428', 'BRUNO TOPACIO ROJO MOSAICO HEMBRA', 'CC', 'Serie Bruno Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (429, 'D.429', 'BRUNO TOPACIO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (430, 'D.430', 'BRUNO TOPACIO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (431, 'D.431', 'ÁGATA TOPACIO BLANCO', 'CC', 'Serie Ágata Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (432, 'D.432', 'ÁGATA TOPACIO BLANCO DOMINANTE', 'CC', 'Serie Ágata Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (433, 'D.433', 'ÁGATA TOPACIO AMARILLO INTENSO', 'CC', 'Serie Ágata Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (434, 'D.434', 'ÁGATA TOPACIO AMARILLO NEVADO', 'CC', 'Serie Ágata Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (435, 'D.435', 'ÁGATA TOPACIO AMARILLO MARFIL INTENSO', 'CC', 'Serie Ágata Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (436, 'D.436', 'ÁGATA TOPACIO AMARILLO MARFIL NEVADO', 'CC', 'Serie Ágata Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (437, 'D.437', 'ÁGATA TOPACIO AMARILLO MOSAICO MACHO', 'CC', 'Serie Ágata Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (438, 'D.438', 'ÁGATA TOPACIO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Ágata Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (439, 'D.439', 'ÁGATA TOPACIO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (440, 'D.440', 'ÁGATA TOPACIO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (441, 'D.441', 'ÁGATA TOPACIO ROJO INTENSO', 'CC', 'Serie Ágata Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (442, 'D.442', 'ÁGATA TOPACIO ROJO NEVADO', 'CC', 'Serie Ágata Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (443, 'D.443', 'ÁGATA TOPACIO ROJO MARFIL INTENSO', 'CC', 'Serie Ágata Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (444, 'D.444', 'ÁGATA TOPACIO ROJO MARFIL NEVADO', 'CC', 'Serie Ágata Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (445, 'D.445', 'ÁGATA TOPACIO ROJO MOSAICO MACHO', 'CC', 'Serie Ágata Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (446, 'D.446', 'ÁGATA TOPACIO ROJO MOSAICO HEMBRA', 'CC', 'Serie Ágata Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (447, 'D.447', 'ÁGATA TOPACIO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (448, 'D.448', 'ÁGATA TOPACIO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (449, 'D.449', 'ISABEL TOPACIO BLANCO', 'CC', 'Serie Isabel Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (450, 'D.450', 'ISABEL TOPACIO BLANCO DOMINANTE', 'CC', 'Serie Isabel Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (451, 'D.451', 'ISABEL TOPACIO AMARILLO INTENSO', 'CC', 'Serie Isabel Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (452, 'D.452', 'ISABEL TOPACIO AMARILLO NEVADO', 'CC', 'Serie Isabel Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (453, 'D.453', 'ISABEL TOPACIO AMARILLO MARFIL INTENSO', 'CC', 'Serie Isabel Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (454, 'D.454', 'ISABEL TOPACIO AMARILLO MARFIL NEVADO', 'CC', 'Serie Isabel Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (455, 'D.455', 'ISABEL TOPACIO AMARILLO MOSAICO MACHO', 'CC', 'Serie Isabel Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (456, 'D.456', 'ISABEL TOPACIO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Isabel Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (457, 'D.457', 'ISABEL TOPACIO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (458, 'D.458', 'ISABEL TOPACIO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Topacio sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (459, 'D.459', 'ISABEL TOPACIO ROJO INTENSO', 'CC', 'Serie Isabel Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (460, 'D.460', 'ISABEL TOPACIO ROJO NEVADO', 'CC', 'Serie Isabel Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (461, 'D.461', 'ISABEL TOPACIO ROJO MARFIL INTENSO', 'CC', 'Serie Isabel Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (462, 'D.462', 'ISABEL TOPACIO ROJO MARFIL NEVADO', 'CC', 'Serie Isabel Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (463, 'D.463', 'ISABEL TOPACIO ROJO MOSAICO MACHO', 'CC', 'Serie Isabel Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (464, 'D.464', 'ISABEL TOPACIO ROJO MOSAICO HEMBRA', 'CC', 'Serie Isabel Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (465, 'D.465', 'ISABEL TOPACIO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (466, 'D.466', 'ISABEL TOPACIO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Topacio con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (467, 'D.467', 'NEGRO EUMO BLANCO', 'CC', 'Serie Negro Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (468, 'D.468', 'NEGRO EUMO BLANCO DOMINANTE', 'CC', 'Serie Negro Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (469, 'D.469', 'NEGRO EUMO AMARILLO INTENSO', 'CC', 'Serie Negro Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (470, 'D.470', 'NEGRO EUMO AMARILLO NEVADO', 'CC', 'Serie Negro Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (471, 'D.471', 'NEGRO EUMO AMARILLO MARFIL INTENSO', 'CC', 'Serie Negro Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (472, 'D.472', 'NEGRO EUMO AMARILLO MARFIL NEVADO', 'CC', 'Serie Negro Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (473, 'D.473', 'NEGRO EUMO AMARILLO MOSAICO MACHO', 'CC', 'Serie Negro Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (474, 'D.474', 'NEGRO EUMO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Negro Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (475, 'D.475', 'NEGRO EUMO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (476, 'D.476', 'NEGRO EUMO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (477, 'D.477', 'NEGRO EUMO ROJO INTENSO', 'CC', 'Serie Negro Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (478, 'D.478', 'NEGRO EUMO ROJO NEVADO', 'CC', 'Serie Negro Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (479, 'D.479', 'NEGRO EUMO ROJO MARFIL INTENSO', 'CC', 'Serie Negro Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (480, 'D.480', 'NEGRO EUMO ROJO MARFIL NEVADO', 'CC', 'Serie Negro Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (481, 'D.481', 'NEGRO EUMO ROJO MOSAICO MACHO', 'CC', 'Serie Negro Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (482, 'D.482', 'NEGRO EUMO ROJO MOSAICO HEMBRA', 'CC', 'Serie Negro Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (483, 'D.483', 'NEGRO EUMO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (484, 'D.484', 'NEGRO EUMO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (485, 'D.485', 'BRUNO EUMO BLANCO', 'CC', 'Serie Bruno Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (486, 'D.486', 'BRUNO EUMO BLANCO DOMINANTE', 'CC', 'Serie Bruno Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (487, 'D.487', 'BRUNO EUMO AMARILLO INTENSO', 'CC', 'Serie Bruno Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (488, 'D.488', 'BRUNO EUMO AMARILLO NEVADO', 'CC', 'Serie Bruno Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (489, 'D.489', 'BRUNO EUMO AMARILLO MARFIL INTENSO', 'CC', 'Serie Bruno Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (490, 'D.490', 'BRUNO EUMO AMARILLO MARFIL NEVADO', 'CC', 'Serie Bruno Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (491, 'D.491', 'BRUNO EUMO AMARILLO MOSAICO MACHO', 'CC', 'Serie Bruno Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (492, 'D.492', 'BRUNO EUMO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Bruno Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (493, 'D.493', 'BRUNO EUMO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (494, 'D.494', 'BRUNO EUMO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (495, 'D.495', 'BRUNO EUMO ROJO INTENSO', 'CC', 'Serie Bruno Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (496, 'D.496', 'BRUNO EUMO ROJO NEVADO', 'CC', 'Serie Bruno Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (497, 'D.497', 'BRUNO EUMO ROJO MARFIL INTENSO', 'CC', 'Serie Bruno Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (498, 'D.498', 'BRUNO EUMO ROJO MARFIL NEVADO', 'CC', 'Serie Bruno Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (499, 'D.499', 'BRUNO EUMO ROJO MOSAICO MACHO', 'CC', 'Serie Bruno Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (500, 'D.500', 'BRUNO EUMO ROJO MOSAICO HEMBRA', 'CC', 'Serie Bruno Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (501, 'D.501', 'BRUNO EUMO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (502, 'D.502', 'BRUNO EUMO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (503, 'D.503', 'ÁGATA EUMO BLANCO', 'CC', 'Serie Ágata Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (504, 'D.504', 'ÁGATA EUMO BLANCO DOMINANTE', 'CC', 'Serie Ágata Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (505, 'D.505', 'ÁGATA EUMO AMARILLO INTENSO', 'CC', 'Serie Ágata Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (506, 'D.506', 'ÁGATA EUMO AMARILLO NEVADO', 'CC', 'Serie Ágata Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (507, 'D.507', 'ÁGATA EUMO AMARILLO MARFIL INTENSO', 'CC', 'Serie Ágata Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (508, 'D.508', 'ÁGATA EUMO AMARILLO MARFIL NEVADO', 'CC', 'Serie Ágata Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (509, 'D.509', 'ÁGATA EUMO AMARILLO MOSAICO MACHO', 'CC', 'Serie Ágata Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (510, 'D.510', 'ÁGATA EUMO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Ágata Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (511, 'D.511', 'ÁGATA EUMO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (512, 'D.512', 'ÁGATA EUMO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Eumo sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (513, 'D.513', 'ÁGATA EUMO ROJO INTENSO', 'CC', 'Serie Ágata Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (514, 'D.514', 'ÁGATA EUMO ROJO NEVADO', 'CC', 'Serie Ágata Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (515, 'D.515', 'ÁGATA EUMO ROJO MARFIL INTENSO', 'CC', 'Serie Ágata Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (516, 'D.516', 'ÁGATA EUMO ROJO MARFIL NEVADO', 'CC', 'Serie Ágata Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (517, 'D.517', 'ÁGATA EUMO ROJO MOSAICO MACHO', 'CC', 'Serie Ágata Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (518, 'D.518', 'ÁGATA EUMO ROJO MOSAICO HEMBRA', 'CC', 'Serie Ágata Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (519, 'D.519', 'ÁGATA EUMO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (520, 'D.520', 'ÁGATA EUMO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Eumo con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (521, 'D.521', 'NEGRO ÓNIX BLANCO', 'CC', 'Serie Negro Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (522, 'D.522', 'NEGRO ÓNIX BLANCO DOMINANTE', 'CC', 'Serie Negro Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (523, 'D.523', 'NEGRO ÓNIX AMARILLO INTENSO', 'CC', 'Serie Negro Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (524, 'D.524', 'NEGRO ÓNIX AMARILLO NEVADO', 'CC', 'Serie Negro Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (525, 'D.525', 'NEGRO ÓNIX AMARILLO MARFIL INTENSO', 'CC', 'Serie Negro Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (526, 'D.526', 'NEGRO ÓNIX AMARILLO MARFIL NEVADO', 'CC', 'Serie Negro Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (527, 'D.527', 'NEGRO ÓNIX AMARILLO MOSAICO MACHO', 'CC', 'Serie Negro Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (528, 'D.528', 'NEGRO ÓNIX AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Negro Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (529, 'D.529', 'NEGRO ÓNIX AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (530, 'D.530', 'NEGRO ÓNIX AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (531, 'D.531', 'NEGRO ÓNIX ROJO INTENSO', 'CC', 'Serie Negros Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (532, 'D.532', 'NEGRO ÓNIX ROJO NEVADO', 'CC', 'Serie Negros Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (533, 'D.533', 'NEGRO ÓNIX ROJO MARFIL INTENSO', 'CC', 'Serie Negros Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (534, 'D.534', 'NEGRO ÓNIX ROJO MARFIL NEVADO', 'CC', 'Serie Negros Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (535, 'D.535', 'NEGRO ÓNIX ROJO MOSAICO MACHO', 'CC', 'Serie Negros Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (536, 'D.536', 'NEGRO ÓNIX ROJO MOSAICO HEMBRA', 'CC', 'Serie Negros Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (537, 'D.537', 'NEGRO ÓNIX ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Negros Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (538, 'D.538', 'NEGRO ÓNIX ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negros Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (539, 'D.539', 'BRUNO ÓNIX BLANCO', 'CC', 'Serie Bruno Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (540, 'D.540', 'BRUNO ÓNIX BLANCO DOMINANTE', 'CC', 'Serie Bruno Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (541, 'D.541', 'BRUNO ÓNIX AMARILLO INTENSO', 'CC', 'Serie Bruno Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (542, 'D.542', 'BRUNO ÓNIX AMARILLO NEVADO', 'CC', 'Serie Bruno Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (543, 'D.543', 'BRUNO ÓNIX AMARILLO MARFIL INTENSO', 'CC', 'Serie Bruno Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (544, 'D.544', 'BRUNO ÓNIX AMARILLO MARFIL NEVADO', 'CC', 'Serie Bruno Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (545, 'D.545', 'BRUNO ÓNIX AMARILLO MOSAICO MACHO', 'CC', 'Serie Bruno Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (546, 'D.546', 'BRUNO ÓNIX AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Bruno Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (547, 'D.547', 'BRUNO ÓNIX AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (548, 'D.548', 'BRUNO ÓNIX AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (549, 'D.549', 'BRUNO ÓNIX ROJO INTENSO', 'CC', 'Serie Bruno Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (550, 'D.550', 'BRUNO ÓNIX ROJO NEVADO', 'CC', 'Serie Bruno Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (551, 'D.551', 'BRUNO ÓNIX ROJO MARFIL INTENSO', 'CC', 'Serie Bruno Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (552, 'D.552', 'BRUNO ÓNIX ROJO MARFIL NEVADO', 'CC', 'Serie Bruno Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (553, 'D.553', 'BRUNO ÓNIX ROJO MOSAICO MACHO', 'CC', 'Serie Bruno Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (554, 'D.554', 'BRUNO ÓNIX ROJO MOSAICO HEMBRA', 'CC', 'Serie Bruno Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (555, 'D.555', 'BRUNO ÓNIX ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (556, 'D.556', 'BRUNO ÓNIX ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (557, 'D.557', 'ÁGATA ÓNIX BLANCO', 'CC', 'Serie Ágata Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (558, 'D.558', 'ÁGATA ÓNIX BLANCO DOMINANTE', 'CC', 'Serie Ágata Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (559, 'D.559', 'ÁGATA ÓNIX AMARILLO INTENSO', 'CC', 'Serie Ágata Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (560, 'D.560', 'ÁGATA ÓNIX AMARILLO NEVADO', 'CC', 'Serie Ágata Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (561, 'D.561', 'ÁGATA ÓNIX AMARILLO MARFIL INTENSO', 'CC', 'Serie Ágata Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (562, 'D.562', 'ÁGATA ÓNIX AMARILLO MARFIL NEVADO', 'CC', 'Serie Ágata Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (563, 'D.563', 'ÁGATA ÓNIX AMARILLO MOSAICO MACHO', 'CC', 'Serie Ágata Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (564, 'D.564', 'ÁGATA ÓNIX AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Ágata Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (565, 'D.565', 'ÁGATA ÓNIX AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (566, 'D.566', 'ÁGATA ÓNIX AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (567, 'D.567', 'ÁGATA ÓNIX ROJO INTENSO', 'CC', 'Serie Ágata Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (568, 'D.568', 'ÁGATA ÓNIX ROJO NEVADO', 'CC', 'Serie Ágata Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (569, 'D.569', 'ÁGATA ÓNIX ROJO MARFIL INTENSO', 'CC', 'Serie Ágata Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (570, 'D.570', 'ÁGATA ÓNIX ROJO MARFIL NEVADO', 'CC', 'Serie Ágata Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (571, 'D.571', 'ÁGATA ÓNIX ROJO MOSAICO MACHO', 'CC', 'Serie Ágata Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (572, 'D.572', 'ÁGATA ÓNIX ROJO MOSAICO HEMBRA', 'CC', 'Serie Ágata Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (573, 'D.573', 'ÁGATA ÓNIX ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (574, 'D.574', 'ÁGATA ÓNIX ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (575, 'D.575', 'ISABEL ÓNIX BLANCO', 'CC', 'Serie Isabel Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (576, 'D.576', 'ISABEL ÓNIX BLANCO DOMINANTE', 'CC', 'Serie Isabel Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (577, 'D.577', 'ISABEL ÓNIX AMARILLO INTENSO', 'CC', 'Serie Isabel Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (578, 'D.578', 'ISABEL ÓNIX AMARILLO NEVADO', 'CC', 'Serie Isabel Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (579, 'D.579', 'ISABEL ÓNIX AMARILLO MARFIL INTENSO', 'CC', 'Serie Isabel Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (580, 'D.580', 'ISABEL ÓNIX AMARILLO MARFIL NEVADO', 'CC', 'Serie Isabel Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (581, 'D.581', 'ISABEL ÓNIX AMARILLO MOSAICO MACHO', 'CC', 'Serie Isabel Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (582, 'D.582', 'ISABEL ÓNIX AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Isabel Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (583, 'D.583', 'ISABEL ÓNIX AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (584, 'D.584', 'ISABEL ÓNIX AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Ónix sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (585, 'D.585', 'ISABEL ÓNIX ROJO INTENSO', 'CC', 'Serie Isabel Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (586, 'D.586', 'ISABEL ÓNIX ROJO NEVADO', 'CC', 'Serie Isabel Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (587, 'D.587', 'ISABEL ÓNIX ROJO MARFIL INTENSO', 'CC', 'Serie Isabel Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (588, 'D.588', 'ISABEL ÓNIX ROJO MARFIL NEVADO', 'CC', 'Serie Isabel Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (589, 'D.589', 'ISABEL ÓNIX ROJO MOSAICO MACHO', 'CC', 'Serie Isabel Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (590, 'D.590', 'ISABEL ÓNIX ROJO MOSAICO HEMBRA', 'CC', 'Serie Isabel Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (591, 'D.591', 'ISABEL ÓNIX ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (592, 'D.592', 'ISABEL ÓNIX ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Ónix con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (593, 'D.593', 'NEGRO COBALTO BLANCO', 'CC', 'Serie Negro Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (594, 'D.594', 'NEGRO COBALTO BLANCO DOMINANTE', 'CC', 'Serie Negro Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (595, 'D.595', 'NEGRO COBALTO AMARILLO INTENSO', 'CC', 'Serie Negro Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (596, 'D.596', 'NEGRO COBALTO AMARILLO NEVADO', 'CC', 'Serie Negro Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (597, 'D.597', 'NEGRO COBALTO AMARILLO MARFIL INTENSO', 'CC', 'Serie Negro Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (598, 'D.598', 'NEGRO COBALTO AMARILLO MARFIL NEVADO', 'CC', 'Serie Negro Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (599, 'D.599', 'NEGRO COBALTO AMARILLO MOSAICO MACHO', 'CC', 'Serie Negro Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (600, 'D.600', 'NEGRO COBALTO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Negro Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (601, 'D.601', 'NEGRO COBALTO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (602, 'D.602', 'NEGRO COBALTO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (603, 'D.603', 'NEGRO COBALTO ROJO INTENSO', 'CC', 'Serie Negros Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (604, 'D.604', 'NEGRO COBALTO ROJO NEVADO', 'CC', 'Serie Negros Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (605, 'D.605', 'NEGRO COBALTO ROJO MARFIL INTENSO', 'CC', 'Serie Negros Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (606, 'D.606', 'NEGRO COBALTO ROJO MARFIL NEVADO', 'CC', 'Serie Negros Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (607, 'D.607', 'NEGRO COBALTO ROJO MOSAICO MACHO', 'CC', 'Serie Negros Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (608, 'D.608', 'NEGRO COBALTO ROJO MOSAICO HEMBRA', 'CC', 'Serie Negros Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (609, 'D.609', 'NEGRO COBALTO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Negros Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (610, 'D.610', 'NEGRO COBALTO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negros Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (611, 'D.611', 'BRUNO COBALTO BLANCO', 'CC', 'Serie Bruno Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (612, 'D.612', 'BRUNO COBALTO BLANCO DOMINANTE', 'CC', 'Serie Bruno Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (613, 'D.613', 'BRUNO COBALTO AMARILLO INTENSO', 'CC', 'Serie Bruno Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (614, 'D.614', 'BRUNO COBALTO AMARILLO NEVADO', 'CC', 'Serie Bruno Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (615, 'D.615', 'BRUNO COBALTO AMARILLO MARFIL INTENSO', 'CC', 'Serie Bruno Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (616, 'D.616', 'BRUNO COBALTO AMARILLO MARFIL NEVADO', 'CC', 'Serie Bruno Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (617, 'D.617', 'BRUNO COBALTO AMARILLO MOSAICO MACHO', 'CC', 'Serie Bruno Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (618, 'D.618', 'BRUNO COBALTO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Bruno Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (619, 'D.619', 'BRUNO COBALTO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (620, 'D.620', 'BRUNO COBALTO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (621, 'D.621', 'BRUNO COBALTO ROJO INTENSO', 'CC', 'Serie Bruno Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (622, 'D.622', 'BRUNO COBALTO ROJO NEVADO', 'CC', 'Serie Bruno Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (623, 'D.623', 'BRUNO COBALTO ROJO MARFIL INTENSO', 'CC', 'Serie Bruno Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (624, 'D.624', 'BRUNO COBALTO ROJO MARFIL NEVADO', 'CC', 'Serie Bruno Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (625, 'D.625', 'BRUNO COBALTO ROJO MOSAICO MACHO', 'CC', 'Serie Bruno Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (626, 'D.626', 'BRUNO COBALTO ROJO MOSAICO HEMBRA', 'CC', 'Serie Bruno Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (627, 'D.627', 'BRUNO COBALTO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (628, 'D.628', 'BRUNO COBALTO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (629, 'D.629', 'ÁGATA COBALTO BLANCO', 'CC', 'Serie Ágata Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (630, 'D.630', 'ÁGATA COBALTO BLANCO DOMINANTE', 'CC', 'Serie Ágata Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (631, 'D.631', 'ÁGATA COBALTO AMARILLO INTENSO', 'CC', 'Serie Ágata Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (632, 'D.632', 'ÁGATA COBALTO AMARILLO NEVADO', 'CC', 'Serie Ágata Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (633, 'D.633', 'ÁGATA COBALTO AMARILLO MARFIL INTENSO', 'CC', 'Serie Ágata Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (634, 'D.634', 'ÁGATA COBALTO AMARILLO MARFIL NEVADO', 'CC', 'Serie Ágata Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (635, 'D.635', 'ÁGATA COBALTO AMARILLO MOSAICO MACHO', 'CC', 'Serie Ágata Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (636, 'D.636', 'ÁGATA COBALTO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Ágata Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (637, 'D.637', 'ÁGATA COBALTO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (638, 'D.638', 'ÁGATA COBALTO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (639, 'D.639', 'ÁGATA COBALTO ROJO INTENSO', 'CC', 'Serie Ágata Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (640, 'D.640', 'ÁGATA COBALTO ROJO NEVADO', 'CC', 'Serie Ágata Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (641, 'D.641', 'ÁGATA COBALTO ROJO MARFIL INTENSO', 'CC', 'Serie Ágata Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (642, 'D.642', 'ÁGATA COBALTO ROJO MARFIL NEVADO', 'CC', 'Serie Ágata Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (643, 'D.643', 'ÁGATA COBALTO ROJO MOSAICO MACHO', 'CC', 'Serie Ágata Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (644, 'D.644', 'ÁGATA COBALTO ROJO MOSAICO HEMBRA', 'CC', 'Serie Ágata Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (645, 'D.645', 'ÁGATA COBALTO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (646, 'D.646', 'ÁGATA COBALTO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (647, 'D.647', 'ISABEL COBALTO BLANCO', 'CC', 'Serie Isabel Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (648, 'D.648', 'ISABEL COBALTO BLANCO DOMINANTE', 'CC', 'Serie Isabel Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (649, 'D.649', 'ISABEL COBALTO AMARILLO INTENSO', 'CC', 'Serie Isabel Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (650, 'D.650', 'ISABEL COBALTO AMARILLO NEVADO', 'CC', 'Serie Isabel Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (651, 'D.651', 'ISABEL COBALTO AMARILLO MARFIL INTENSO', 'CC', 'Serie Isabel Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (652, 'D.652', 'ISABEL COBALTO AMARILLO MARFIL NEVADO', 'CC', 'Serie Isabel Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (653, 'D.653', 'ISABEL COBALTO AMARILLO MOSAICO MACHO', 'CC', 'Serie Isabel Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (654, 'D.654', 'ISABEL COBALTO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Isabel Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (655, 'D.655', 'ISABEL COBALTO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (656, 'D.656', 'ISABEL COBALTO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Cobalto sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (657, 'D.657', 'ISABEL COBALTO ROJO INTENSO', 'CC', 'Serie Isabel Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (658, 'D.658', 'ISABEL COBALTO ROJO NEVADO', 'CC', 'Serie Isabel Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (659, 'D.659', 'ISABEL COBALTO ROJO MARFIL INTENSO', 'CC', 'Serie Isabel Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (660, 'D.660', 'ISABEL COBALTO ROJO MARFIL NEVADO', 'CC', 'Serie Isabel Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (661, 'D.661', 'ISABEL COBALTO ROJO MOSAICO MACHO', 'CC', 'Serie Isabel Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (662, 'D.662', 'ISABEL COBALTO ROJO MOSAICO HEMBRA', 'CC', 'Serie Isabel Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (663, 'D.663', 'ISABEL COBALTO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (664, 'D.664', 'ISABEL COBALTO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Cobalto con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (665, 'D.665', 'NEGRO JASPE SD BLANCO', 'CC', 'Serie Negro Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (666, 'D.666', 'NEGRO JASPE SD BLANCO DOMINANTE', 'CC', 'Serie Negro Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (667, 'D.667', 'NEGRO JASPE SD AMARILLO INTENSO', 'CC', 'Serie Negro Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (668, 'D.668', 'NEGRO JASPE SD AMARILLO NEVADO', 'CC', 'Serie Negro Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (669, 'D.669', 'NEGRO JASPE SD AMARILLO MARFIL INTENSO', 'CC', 'Serie Negro Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (670, 'D.670', 'NEGRO JASPE SD AMARILLO MARFIL NEVADO', 'CC', 'Serie Negro Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (671, 'D.671', 'NEGRO JASPE SD AMARILLO MOSAICO MACHO', 'CC', 'Serie Negro Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (672, 'D.672', 'NEGRO JASPE SD AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Negro Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (673, 'D.673', 'NEGRO JASPE SD AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (674, 'D.674', 'NEGRO JASPE SD AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (675, 'D.675', 'NEGRO JASPE SD ROJO INTENSO', 'CC', 'Serie Negro Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (676, 'D.676', 'NEGRO JASPE SD ROJO NEVADO', 'CC', 'Serie Negro Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (677, 'D.677', 'NEGRO JASPE SD ROJO MARFIL INTENSO', 'CC', 'Serie Negro Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (678, 'D.678', 'NEGRO JASPE SD ROJO MARFIL NEVADO', 'CC', 'Serie Negro Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (679, 'D.679', 'NEGRO JASPE SD ROJO MOSAICO MACHO', 'CC', 'Serie Negro Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (680, 'D.680', 'NEGRO JASPE SD ROJO MOSAICO HEMBRA', 'CC', 'Serie Negro Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (681, 'D.681', 'NEGRO JASPE SD ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (682, 'D.682', 'NEGRO JASPE SD ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (683, 'D.683', 'BRUNO JASPE SD BLANCO', 'CC', 'Serie Bruno Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (684, 'D.684', 'BRUNO JASPE SD BLANCO DOMINANTE', 'CC', 'Serie Bruno Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (685, 'D.685', 'BRUNO JASPE SD AMARILLO INTENSO', 'CC', 'Serie Bruno Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (686, 'D.686', 'BRUNO JASPE SD AMARILLO NEVADO', 'CC', 'Serie Bruno Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (687, 'D.687', 'BRUNO JASPE SD AMARILLO MARFIL INTENSO', 'CC', 'Serie Bruno Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (688, 'D.688', 'BRUNO JASPE SD AMARILLO MARFIL NEVADO', 'CC', 'Serie Bruno Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (689, 'D.689', 'BRUNO JASPE SD AMARILLO MOSAICO MACHO', 'CC', 'Serie Bruno Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (690, 'D.690', 'BRUNO JASPE SD AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Bruno Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (691, 'D.691', 'BRUNO JASPE SD AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (692, 'D.692', 'BRUNO JASPE SD AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (693, 'D.693', 'BRUNO JASPE SD ROJO INTENSO', 'CC', 'Serie Bruno Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (694, 'D.694', 'BRUNO JASPE SD ROJO NEVADO', 'CC', 'Serie Bruno Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (695, 'D.695', 'BRUNO JASPE SD ROJO MARFIL INTENSO', 'CC', 'Serie Bruno Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (696, 'D.696', 'BRUNO JASPE SD ROJO MARFIL NEVADO', 'CC', 'Serie Bruno Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (697, 'D.697', 'BRUNO JASPE SD ROJO MOSAICO MACHO', 'CC', 'Serie Bruno Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (698, 'D.698', 'BRUNO JASPE SD ROJO MOSAICO HEMBRA', 'CC', 'Serie Bruno Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (699, 'D.699', 'BRUNO JASPE SD ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (700, 'D.700', 'BRUNO JASPE SD ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (701, 'D.701', 'ÁGATA JASPE SD BLANCO', 'CC', 'Serie Ágata Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (702, 'D.702', 'ÁGATA JASPE SD BLANCO DOMINANTE', 'CC', 'Serie Ágata Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (703, 'D.703', 'ÁGATA JASPE SD AMARILLO INTENSO', 'CC', 'Serie Ágata Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (704, 'D.704', 'ÁGATA JASPE SD AMARILLO NEVADO', 'CC', 'Serie Ágata Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (705, 'D.705', 'ÁGATA JASPE SD AMARILLO MARFIL INTENSO', 'CC', 'Serie Ágata Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (706, 'D.706', 'ÁGATA JASPE SD AMARILLO MARFIL NEVADO', 'CC', 'Serie Ágata Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (707, 'D.707', 'ÁGATA JASPE SD AMARILLO MOSAICO MACHO', 'CC', 'Serie Ágata Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (708, 'D.708', 'ÁGATA JASPE SD AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Ágata Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (709, 'D.709', 'ÁGATA JASPE SD AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (710, 'D.710', 'ÁGATA JASPE SD AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (711, 'D.711', 'ÁGATA JASPE SD ROJO INTENSO', 'CC', 'Serie Ágata Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (712, 'D.712', 'ÁGATA JASPE SD ROJO NEVADO', 'CC', 'Serie Ágata Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (713, 'D.713', 'ÁGATA JASPE SD ROJO MARFIL INTENSO', 'CC', 'Serie Ágata Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (714, 'D.714', 'ÁGATA JASPE SD ROJO MARFIL NEVADO', 'CC', 'Serie Ágata Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (715, 'D.715', 'ÁGATA JASPE SD ROJO MOSAICO MACHO', 'CC', 'Serie Ágata Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (716, 'D.716', 'ÁGATA JASPE SD ROJO MOSAICO HEMBRA', 'CC', 'Serie Ágata Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (717, 'D.717', 'ÁGATA JASPE SD ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (718, 'D.718', 'ÁGATA JASPE SD ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (719, 'D.719', 'ISABEL JASPE SD BLANCO', 'CC', 'Serie Isabel Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (720, 'D.720', 'ISABEL JASPE SD BLANCO DOMINANTE', 'CC', 'Serie Isabel Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (721, 'D.721', 'ISABEL JASPE SD AMARILLO INTENSO', 'CC', 'Serie Isabel Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (722, 'D.722', 'ISABEL JASPE SD AMARILLO NEVADO', 'CC', 'Serie Isabel Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (723, 'D.723', 'ISABEL JASPE SD AMARILLO MARFIL INTENSO', 'CC', 'Serie Isabel Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (724, 'D.724', 'ISABEL JASPE SD AMARILLO MARFIL NEVADO', 'CC', 'Serie Isabel Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (725, 'D.725', 'ISABEL JASPE SD AMARILLO MOSAICO MACHO', 'CC', 'Serie Isabel Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (726, 'D.726', 'ISABEL JASPE SD AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Isabel Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (727, 'D.727', 'ISABEL JASPE SD AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (728, 'D.728', 'ISABEL JASPE SD AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Jaspe SD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (729, 'D.729', 'ISABEL JASPE SD ROJO INTENSO', 'CC', 'Serie Isabel Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (730, 'D.730', 'ISABEL JASPE SD ROJO NEVADO', 'CC', 'Serie Isabel Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (731, 'D.731', 'ISABEL JASPE SD ROJO MARFIL INTENSO', 'CC', 'Serie Isabel Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (732, 'D.732', 'ISABEL JASPE SD ROJO MARFIL NEVADO', 'CC', 'Serie Isabel Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (733, 'D.733', 'ISABEL JASPE SD ROJO MOSAICO MACHO', 'CC', 'Serie Isabel Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (734, 'D.734', 'ISABEL JASPE SD ROJO MOSAICO HEMBRA', 'CC', 'Serie Isabel Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (735, 'D.735', 'ISABEL JASPE SD ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (736, 'D.736', 'ISABEL JASPE SD ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Jaspe SD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (737, 'D.737', 'NEGRO JASPE DD BLANCO', 'CC', 'Serie Negro Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (738, 'D.738', 'NEGRO JASPE DD BLANCO DOMINANTE', 'CC', 'Serie Negro Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (739, 'D.739', 'NEGRO JASPE DD AMARILLO INTENSO', 'CC', 'Serie Negro Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (740, 'D.740', 'NEGRO JASPE DD AMARILLO NEVADO', 'CC', 'Serie Negro Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (741, 'D.741', 'NEGRO JASPE DD AMARILLO MARFIL INTENSO', 'CC', 'Serie Negro Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (742, 'D.742', 'NEGRO JASPE DD AMARILLO MARFIL NEVADO', 'CC', 'Serie Negro Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (743, 'D.743', 'NEGRO JASPE DD AMARILLO MOSAICO MACHO', 'CC', 'Serie Negro Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (744, 'D.744', 'NEGRO JASPE DD AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Negro Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (745, 'D.745', 'NEGRO JASPE DD AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (746, 'D.746', 'NEGRO JASPE DD AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (747, 'D.747', 'NEGRO JASPE DD ROJO INTENSO', 'CC', 'Serie Negro Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (748, 'D.748', 'NEGRO JASPE DD ROJO NEVADO', 'CC', 'Serie Negro Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (749, 'D.749', 'NEGRO JASPE DD ROJO MARFIL INTENSO', 'CC', 'Serie Negro Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (750, 'D.750', 'NEGRO JASPE DD ROJO MARFIL NEVADO', 'CC', 'Serie Negro Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (751, 'D.751', 'NEGRO JASPE DD ROJO MOSAICO MACHO', 'CC', 'Serie Negro Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (752, 'D.752', 'NEGRO JASPE DD ROJO MOSAICO HEMBRA', 'CC', 'Serie Negro Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (753, 'D.753', 'NEGRO JASPE DD ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (754, 'D.754', 'NEGRO JASPE DD ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (755, 'D.755', 'BRUNO JASPE DD BLANCO', 'CC', 'Serie Bruno Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (756, 'D.756', 'BRUNO JASPE DD BLANCO DOMINANTE', 'CC', 'Serie Bruno Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (757, 'D.757', 'BRUNO JASPE DD AMARILLO INTENSO', 'CC', 'Serie Bruno Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (758, 'D.758', 'BRUNO JASPE DD AMARILLO NEVADO', 'CC', 'Serie Bruno Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (759, 'D.759', 'BRUNO JASPE DD AMARILLO MARFIL INTENSO', 'CC', 'Serie Bruno Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (760, 'D.760', 'BRUNO JASPE DD AMARILLO MARFIL NEVADO', 'CC', 'Serie Bruno Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (761, 'D.761', 'BRUNO JASPE DD AMARILLO MOSAICO MACHO', 'CC', 'Serie Bruno Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (762, 'D.762', 'BRUNO JASPE DD AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Bruno Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (763, 'D.763', 'BRUNO JASPE DD AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (764, 'D.764', 'BRUNO JASPE DD AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (765, 'D.765', 'BRUNO JASPE DD ROJO INTENSO', 'CC', 'Serie Bruno Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (766, 'D.766', 'BRUNO JASPE DD ROJO NEVADO', 'CC', 'Serie Bruno Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (767, 'D.767', 'BRUNO JASPE DD ROJO MARFIL INTENSO', 'CC', 'Serie Bruno Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (768, 'D.768', 'BRUNO JASPE DD ROJO MARFIL NEVADO', 'CC', 'Serie Bruno Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (769, 'D.769', 'BRUNO JASPE DD ROJO MOSAICO MACHO', 'CC', 'Serie Bruno Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (770, 'D.770', 'BRUNO JASPE DD ROJO MOSAICO HEMBRA', 'CC', 'Serie Bruno Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (771, 'D.771', 'BRUNO JASPE DD ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (772, 'D.772', 'BRUNO JASPE DD ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (773, 'D.773', 'ÁGATA JASPE DD BLANCO', 'CC', 'Serie Ágata Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (774, 'D.774', 'ÁGATA JASPE DD BLANCO DOMINANTE', 'CC', 'Serie Ágata Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (775, 'D.775', 'ÁGATA JASPE DD AMARILLO INTENSO', 'CC', 'Serie Ágata Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (776, 'D.776', 'ÁGATA JASPE DD AMARILLO NEVADO', 'CC', 'Serie Ágata Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (777, 'D.777', 'ÁGATA JASPE DD AMARILLO MARFIL INTENSO', 'CC', 'Serie Ágata Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (778, 'D.778', 'ÁGATA JASPE DD AMARILLO MARFIL NEVADO', 'CC', 'Serie Ágata Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (779, 'D.779', 'ÁGATA JASPE DD AMARILLO MOSAICO MACHO', 'CC', 'Serie Ágata Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (780, 'D.780', 'ÁGATA JASPE DD AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Ágata Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (781, 'D.781', 'ÁGATA JASPE DD AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (782, 'D.782', 'ÁGATA JASPE DD AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Jaspe DD sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (783, 'D.783', 'ÁGATA JASPE DD ROJO INTENSO', 'CC', 'Serie Ágata Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (784, 'D.784', 'ÁGATA JASPE DD ROJO NEVADO', 'CC', 'Serie Ágata Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (785, 'D.785', 'ÁGATA JASPE DD ROJO MARFIL INTENSO', 'CC', 'Serie Ágata Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (786, 'D.786', 'ÁGATA JASPE DD ROJO MARFIL NEVADO', 'CC', 'Serie Ágata Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (787, 'D.787', 'ÁGATA JASPE DD ROJO MOSAICO MACHO', 'CC', 'Serie Ágata Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (788, 'D.788', 'ÁGATA JASPE DD ROJO MOSAICO HEMBRA', 'CC', 'Serie Ágata Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (789, 'D.789', 'ÁGATA JASPE DD ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (790, 'D.790', 'ÁGATA JASPE DD ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Jaspe DD con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (791, 'D.791', 'NEGRO MOGNO BLANCO', 'CC', 'Serie Negro Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (792, 'D.792', 'NEGRO MOGNO BLANCO DOMINANTE', 'CC', 'Serie Negro Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (793, 'D.793', 'NEGRO MOGNO AMARILLO INTENSO', 'CC', 'Serie Negro Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (794, 'D.794', 'NEGRO MOGNO AMARILLO NEVADO', 'CC', 'Serie Negro Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (795, 'D.795', 'NEGRO MOGNO AMARILLO MARFIL INTENSO', 'CC', 'Serie Negro Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (796, 'D.796', 'NEGRO MOGNO AMARILLO MARFIL NEVADO', 'CC', 'Serie Negro Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (797, 'D.797', 'NEGRO MOGNO AMARILLO MOSAICO MACHO', 'CC', 'Serie Negro Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (798, 'D.798', 'NEGRO MOGNO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Negro Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (799, 'D.799', 'NEGRO MOGNO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (800, 'D.800', 'NEGRO MOGNO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (801, 'D.801', 'NEGRO MOGNO ROJO INTENSO', 'CC', 'Serie Negros Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (802, 'D.802', 'NEGRO MOGNO ROJO NEVADO', 'CC', 'Serie Negros Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (803, 'D.803', 'NEGRO MOGNO ROJO MARFIL INTENSO', 'CC', 'Serie Negros Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (804, 'D.804', 'NEGRO MOGNO ROJO MARFIL NEVADO', 'CC', 'Serie Negros Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (805, 'D.805', 'NEGRO MOGNO ROJO MOSAICO MACHO', 'CC', 'Serie Negros Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (806, 'D.806', 'NEGRO MOGNO ROJO MOSAICO HEMBRA', 'CC', 'Serie Negros Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (807, 'D.807', 'NEGRO MOGNO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Negros Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (808, 'D.808', 'NEGRO MOGNO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negros Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (809, 'D.809', 'BRUNO MOGNO BLANCO', 'CC', 'Serie Bruno Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (810, 'D.810', 'BRUNO MOGNO BLANCO DOMINANTE', 'CC', 'Serie Bruno Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (811, 'D.811', 'BRUNO MOGNO AMARILLO INTENSO', 'CC', 'Serie Bruno Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (812, 'D.812', 'BRUNO MOGNO AMARILLO NEVADO', 'CC', 'Serie Bruno Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (813, 'D.813', 'BRUNO MOGNO AMARILLO MARFIL INTENSO', 'CC', 'Serie Bruno Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (814, 'D.814', 'BRUNO MOGNO AMARILLO MARFIL NEVADO', 'CC', 'Serie Bruno Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (815, 'D.815', 'BRUNO MOGNO AMARILLO MOSAICO MACHO', 'CC', 'Serie Bruno Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (816, 'D.816', 'BRUNO MOGNO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Bruno Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (817, 'D.817', 'BRUNO MOGNO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (818, 'D.818', 'BRUNO MOGNO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (819, 'D.819', 'BRUNO MOGNO ROJO INTENSO', 'CC', 'Serie Bruno Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (820, 'D.820', 'BRUNO MOGNO ROJO NEVADO', 'CC', 'Serie Bruno Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (821, 'D.821', 'BRUNO MOGNO ROJO MARFIL INTENSO', 'CC', 'Serie Bruno Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (822, 'D.822', 'BRUNO MOGNO ROJO MARFIL NEVADO', 'CC', 'Serie Bruno Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (823, 'D.823', 'BRUNO MOGNO ROJO MOSAICO MACHO', 'CC', 'Serie Bruno Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (824, 'D.824', 'BRUNO MOGNO ROJO MOSAICO HEMBRA', 'CC', 'Serie Bruno Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (825, 'D.825', 'BRUNO MOGNO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Bruno Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (826, 'D.826', 'BRUNO MOGNO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Bruno Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (827, 'D.827', 'ÁGATA MOGNO BLANCO', 'CC', 'Serie Ágata Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (828, 'D.828', 'ÁGATA MOGNO BLANCO DOMINANTE', 'CC', 'Serie Ágata Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (829, 'D.829', 'ÁGATA MOGNO AMARILLO INTENSO', 'CC', 'Serie Ágata Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (830, 'D.830', 'ÁGATA MOGNO AMARILLO NEVADO', 'CC', 'Serie Ágata Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (831, 'D.831', 'ÁGATA MOGNO AMARILLO MARFIL INTENSO', 'CC', 'Serie Ágata Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (832, 'D.832', 'ÁGATA MOGNO AMARILLO MARFIL NEVADO', 'CC', 'Serie Ágata Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (833, 'D.833', 'ÁGATA MOGNO AMARILLO MOSAICO MACHO', 'CC', 'Serie Ágata Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (834, 'D.834', 'ÁGATA MOGNO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Ágata Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (835, 'D.835', 'ÁGATA MOGNO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (836, 'D.836', 'ÁGATA MOGNO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (837, 'D.837', 'ÁGATA MOGNO ROJO INTENSO', 'CC', 'Serie Ágata Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (838, 'D.838', 'ÁGATA MOGNO ROJO NEVADO', 'CC', 'Serie Ágata Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (839, 'D.839', 'ÁGATA MOGNO ROJO MARFIL INTENSO', 'CC', 'Serie Ágata Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (840, 'D.840', 'ÁGATA MOGNO ROJO MARFIL NEVADO', 'CC', 'Serie Ágata Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (841, 'D.841', 'ÁGATA MOGNO ROJO MOSAICO MACHO', 'CC', 'Serie Ágata Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (842, 'D.842', 'ÁGATA MOGNO ROJO MOSAICO HEMBRA', 'CC', 'Serie Ágata Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (843, 'D.843', 'ÁGATA MOGNO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Ágata Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (844, 'D.844', 'ÁGATA MOGNO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Ágata Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (845, 'D.845', 'ISABEL MOGNO BLANCO', 'CC', 'Serie Isabel Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (846, 'D.846', 'ISABEL MOGNO BLANCO DOMINANTE', 'CC', 'Serie Isabel Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (847, 'D.847', 'ISABEL MOGNO AMARILLO INTENSO', 'CC', 'Serie Isabel Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (848, 'D.848', 'ISABEL MOGNO AMARILLO NEVADO', 'CC', 'Serie Isabel Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (849, 'D.849', 'ISABEL MOGNO AMARILLO MARFIL INTENSO', 'CC', 'Serie Isabel Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (850, 'D.850', 'ISABEL MOGNO AMARILLO MARFIL NEVADO', 'CC', 'Serie Isabel Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (851, 'D.851', 'ISABEL MOGNO AMARILLO MOSAICO MACHO', 'CC', 'Serie Isabel Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (852, 'D.852', 'ISABEL MOGNO AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Isabel Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (853, 'D.853', 'ISABEL MOGNO AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (854, 'D.854', 'ISABEL MOGNO AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Mogno sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (855, 'D.855', 'ISABEL MOGNO ROJO INTENSO', 'CC', 'Serie Isabel Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (856, 'D.856', 'ISABEL MOGNO ROJO NEVADO', 'CC', 'Serie Isabel Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (857, 'D.857', 'ISABEL MOGNO ROJO MARFIL INTENSO', 'CC', 'Serie Isabel Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (858, 'D.858', 'ISABEL MOGNO ROJO MARFIL NEVADO', 'CC', 'Serie Isabel Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (859, 'D.859', 'ISABEL MOGNO ROJO MOSAICO MACHO', 'CC', 'Serie Isabel Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (860, 'D.860', 'ISABEL MOGNO ROJO MOSAICO HEMBRA', 'CC', 'Serie Isabel Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (861, 'D.861', 'ISABEL MOGNO ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Isabel Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (862, 'D.862', 'ISABEL MOGNO ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Isabel Mogno con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (863, 'D.863', 'NEGRO PERLA BLANCO', 'CC', 'Serie Negro Perla sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (864, 'D.864', 'NEGRO PERLA BLANCO DOMINANTE', 'CC', 'Serie Negro Perla sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (865, 'D.865', 'NEGRO PERLA AMARILLO INTENSO', 'CC', 'Serie Negro Perla sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (866, 'D.866', 'NEGRO PERLA AMARILLO NEVADO', 'CC', 'Serie Negro Perla sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (867, 'D.867', 'NEGRO PERLA AMARILLO MARFIL INTENSO', 'CC', 'Serie Negro Perla sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (868, 'D.868', 'NEGRO PERLA AMARILLO MARFIL NEVADO', 'CC', 'Serie Negro Perla sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (869, 'D.869', 'NEGRO PERLA AMARILLO MOSAICO MACHO', 'CC', 'Serie Negro Perla sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (870, 'D.870', 'NEGRO PERLA AMARILLO MOSAICO HEMBRA', 'CC', 'Serie Negro Perla sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (871, 'D.871', 'NEGRO PERLA AMARILLO MARFIL MOSAICO MACHO', 'CC', 'Serie Negro Perla sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (872, 'D.872', 'NEGRO PERLA AMARILLO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negro Perla sin Factor', DEFAULT);
INSERT INTO public.variedad VALUES (873, 'D.873', 'NEGRO PERLA ROJO INTENSO', 'CC', 'Serie Negros Perla con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (874, 'D.874', 'NEGRO PERLA ROJO NEVADO', 'CC', 'Serie Negros Perla con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (875, 'D.875', 'NEGRO PERLA ROJO MARFIL INTENSO', 'CC', 'Serie Negros Perla con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (876, 'D.876', 'NEGRO PERLA ROJO MARFIL NEVADO', 'CC', 'Serie Negros Perla con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (877, 'D.877', 'NEGRO PERLA ROJO MOSAICO MACHO', 'CC', 'Serie Negros Perla con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (878, 'D.878', 'NEGRO PERLA ROJO MOSAICO HEMBRA', 'CC', 'Serie Negros Perla con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (879, 'D.879', 'NEGRO PERLA ROJO MARFIL MOSAICO MACHO', 'CC', 'Serie Negros Perla con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (880, 'D.880', 'NEGRO PERLA ROJO MARFIL MOSAICO HEMBRA', 'CC', 'Serie Negros Perla con Factor', DEFAULT);
INSERT INTO public.variedad VALUES (881, 'D.881', 'FENOTIPOS Y MUTACIONES EN ESTUDIO', 'CC', 'Serie Mutaciones en Estudio', DEFAULT);
INSERT INTO public.variedad VALUES (882, 'E1.0001', 'COPETE ALEMÁN BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (883, 'E1.0002', 'COPETE ALEMÁN BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (884, 'E1.0003', 'COPETE ALEMÁN AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (885, 'E1.0004', 'COPETE ALEMÁN AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (886, 'E1.0005', 'COPETE ALEMÁN AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (887, 'E1.0006', 'COPETE ALEMÁN AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (888, 'E1.0007', 'COPETE ALEMÁN AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (889, 'E1.0008', 'COPETE ALEMÁN AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (890, 'E1.0009', 'COPETE ALEMÁN AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (891, 'E1.0010', 'COPETE ALEMÁN AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (892, 'E1.0011', 'COPETE ALEMÁN ALBINO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (893, 'E1.0012', 'COPETE ALEMÁN ALBINO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (894, 'E1.0013', 'COPETE ALEMÁN LUTINO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (895, 'E1.0014', 'COPETE ALEMÁN LUTINO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (896, 'E1.0015', 'COPETE ALEMÁN LUTINO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (897, 'E1.0016', 'COPETE ALEMÁN LUTINO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (898, 'E1.0017', 'COPETE ALEMÁN LUTINO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (899, 'E1.0018', 'COPETE ALEMÁN LUTINO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (900, 'E1.0019', 'COPETE ALEMÁN LUTINO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (901, 'E1.0020', 'COPETE ALEMÁN LUTINO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (902, 'E1.0021', 'COPETE ALEMÁN AMARILLO INTENSO ALA BLANCA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (903, 'E1.0022', 'COPETE ALEMÁN AMARILLO NEVADO ALA BLANCA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (904, 'E1.0023', 'COPETE ALEMÁN AMARILLO INTENSO ALA BLANCA MARFIL', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (905, 'E1.0024', 'COPETE ALEMÁN AMARILLO NEVADO ALA BLANCA MARFIL', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (906, 'E1.0025', 'COPETE ALEMÁN AMARILLO MOSAICO ALA BLANCA MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (907, 'E1.0026', 'COPETE ALEMÁN AMARILLO MOSAICO ALA BLANCA HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (908, 'E1.0027', 'COPETE ALEMÁN AMARILLO MOSAICO ALA BLANCA MARFIL MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (909, 'E1.0028', 'COPETE ALEMÁN AMARILLO MOSAICO ALA BLANCA MARFIL HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (910, 'E1.0029', 'COPETE ALEMÁN LUTINO INTENSO ALA BLANCA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (911, 'E1.0030', 'COPETE ALEMÁN LUTINO NEVADO ALA BLANCA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (912, 'E1.0031', 'COPETE ALEMÁN LUTINO INTENSO ALA BLANCA MARFIL', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (913, 'E1.0032', 'COPETE ALEMÁN LUTINO NEVADO ALA BLANCA MARFIL', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (914, 'E1.0033', 'COPETE ALEMÁN LUTINO MOSAICO ALA BLANCA MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (915, 'E1.0034', 'COPETE ALEMÁN LUTINO MOSAICO ALA BLANCA HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (916, 'E1.0035', 'COPETE ALEMÁN LUTINO MOSAICO ALA BLANCA MARFIL MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (917, 'E1.0036', 'COPETE ALEMÁN LUTINO MOSAICO ALA BLANCA MARFIL HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (918, 'E1.0037', 'COPETE ALEMÁN AMARILLO INTENSO PICO AMARILLO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (919, 'E1.0038', 'COPETE ALEMÁN AMARILLO NEVADO PICO AMARILLO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (920, 'E1.0039', 'COPETE ALEMÁN LUTINO INTENSO PICO AMARILLO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (921, 'E1.0040', 'COPETE ALEMÁN LUTINO NEVADO PICO AMARILLO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (922, 'E1.0041', 'COPETE ALEMÁN AMARILLO MARFIL INTENSO PICO AMARILLO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (923, 'E1.0042', 'COPETE ALEMÁN AMARILLO MARFIL NEVADO PICO AMARILLO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (924, 'E1.0043', 'COPETE ALEMÁN LUTINO MARFIL INTENSO PICO AMARILLO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (925, 'E1.0044', 'COPETE ALEMÁN LUTINO MARFIL NEVADO PICO AMARILLO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (926, 'E1.0045', 'COPETE ALEMÁN ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (927, 'E1.0046', 'COPETE ALEMÁN ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (928, 'E1.0047', 'COPETE ALEMÁN ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (929, 'E1.0048', 'COPETE ALEMÁN ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (930, 'E1.0049', 'COPETE ALEMÁN ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (931, 'E1.0050', 'COPETE ALEMÁN ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (932, 'E1.0051', 'COPETE ALEMÁN ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (933, 'E1.0052', 'COPETE ALEMÁN ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (934, 'E1.0053', 'COPETE ALEMÁN RUBINO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (935, 'E1.0054', 'COPETE ALEMÁN RUBINO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (936, 'E1.0055', 'COPETE ALEMÁN RUBINO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (937, 'E1.0056', 'COPETE ALEMÁN RUBINO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (938, 'E1.0057', 'COPETE ALEMÁN RUBINO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (939, 'E1.0058', 'COPETE ALEMÁN RUBINO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (940, 'E1.0059', 'COPETE ALEMÁN RUBINO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (941, 'E1.0060', 'COPETE ALEMÁN RUBINO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (942, 'E1.0061', 'COPETE ALEMÁN ROJO INTENSO ALA BLANCA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (943, 'E1.0062', 'COPETE ALEMÁN ROJO NEVADO ALA BLANCA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (944, 'E1.0063', 'COPETE ALEMÁN ROJO INTENSO ALA BLANCA MARFIL', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (945, 'E1.0064', 'COPETE ALEMÁN ROJO NEVADO ALA BLANCA MARFIL', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (946, 'E1.0065', 'COPETE ALEMÁN ROJO MOSAICO ALA BLANCA MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (947, 'E1.0066', 'COPETE ALEMÁN ROJO MOSAICO ALA BLANCA HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (948, 'E1.0067', 'COPETE ALEMÁN ROJO MOSAICO ALA BLANCA MARFIL MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (949, 'E1.0068', 'COPETE ALEMÁN ROJO MOSAICO ALA BLANCA MARFIL HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (950, 'E1.0069', 'COPETE ALEMÁN RUBINO INTENSO ALA BLANCA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (951, 'E1.0070', 'COPETE ALEMÁN RUBINO NEVADO ALA BLANCA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (952, 'E1.0071', 'COPETE ALEMÁN RUBINO INTENSO ALA BLANCA MARFIL', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (953, 'E1.0072', 'COPETE ALEMÁN RUBINO NEVADO ALA BLANCA MARFIL', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (954, 'E1.0073', 'COPETE ALEMÁN RUBINO MOSAICO ALA BLANCA MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (955, 'E1.0074', 'COPETE ALEMÁN RUBINO MOSAICO ALA BLANCA HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (956, 'E1.0075', 'COPETE ALEMÁN RUBINO MOSAICO ALA BLANCA MARFIL MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (957, 'E1.0076', 'COPETE ALEMÁN RUBINO MOSAICO ALA BLANCA MARFIL HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (958, 'E1.0077', 'COPETE ALEMÁN ROJO INTENSO ÚRUCUM', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (959, 'E1.0078', 'COPETE ALEMÁN ROJO NEVADO ÚRUCUM', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (960, 'E1.0079', 'COPETE ALEMÁN ROJO INTENSO ÚRUCUM MARFIL', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (961, 'E1.0080', 'COPETE ALEMÁN ROJO NEVADO ÚRUCUM MARFIL', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (962, 'E1.0081', 'COPETE ALEMÁN ROJO MOSAICO ÚRUCUM MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (963, 'E1.0082', 'COPETE ALEMÁN ROJO MOSAICO ÚRUCUM HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (964, 'E1.0083', 'COPETE ALEMÁN ROJO MOSAICO ÚRUCUM MARFIL MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (965, 'E1.0084', 'COPETE ALEMÁN ROJO MOSAICO ÚRUCUM MARFIL HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (966, 'E1.0085', 'COPETE ALEMÁN RUBINO INTENSO ÚRUCUM', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (967, 'E1.0086', 'COPETE ALEMÁN RUBINO NEVADO ÚRUCUM', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (968, 'E1.0087', 'COPETE ALEMÁN RUBINO INTENSO ÚRUCUM MARFIL', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (969, 'E1.0088', 'COPETE ALEMÁN RUBINO NEVADO ÚRUCUM MARFIL', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (970, 'E1.0089', 'COPETE ALEMÁN RUBINO MOSAICO ÚRUCUM MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (971, 'E1.0090', 'COPETE ALEMÁN RUBINO MOSAICO ÚRUCUM HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (972, 'E1.0091', 'COPETE ALEMÁN RUBINO MOSAICO ÚRUCUM MARFIL MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (973, 'E1.0092', 'COPETE ALEMÁN RUBINO MOSAICO ÚRUCUM MARFIL HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (974, 'E1.0093', 'COPETE ALEMÁN NEGRO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (975, 'E1.0094', 'COPETE ALEMÁN NEGRO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (976, 'E1.0095', 'COPETE ALEMÁN NEGRO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (977, 'E1.0096', 'COPETE ALEMÁN NEGRO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (978, 'E1.0097', 'COPETE ALEMÁN NEGRO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (979, 'E1.0098', 'COPETE ALEMÁN NEGRO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (980, 'E1.0099', 'COPETE ALEMÁN NEGRO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (981, 'E1.0100', 'COPETE ALEMÁN NEGRO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (982, 'E1.0101', 'COPETE ALEMÁN NEGRO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (983, 'E1.0102', 'COPETE ALEMÁN NEGRO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (984, 'E1.0103', 'COPETE ALEMÁN NEGRO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (985, 'E1.0104', 'COPETE ALEMÁN NEGRO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (986, 'E1.0105', 'COPETE ALEMÁN NEGRO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (987, 'E1.0106', 'COPETE ALEMÁN NEGRO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (988, 'E1.0107', 'COPETE ALEMÁN NEGRO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (989, 'E1.0108', 'COPETE ALEMÁN NEGRO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (990, 'E1.0109', 'COPETE ALEMÁN NEGRO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (991, 'E1.0110', 'COPETE ALEMÁN NEGRO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (992, 'E1.0111', 'COPETE ALEMÁN BRUNO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (993, 'E1.0112', 'COPETE ALEMÁN BRUNO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (994, 'E1.0113', 'COPETE ALEMÁN BRUNO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (995, 'E1.0114', 'COPETE ALEMÁN BRUNO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (996, 'E1.0115', 'COPETE ALEMÁN BRUNO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (997, 'E1.0116', 'COPETE ALEMÁN BRUNO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (998, 'E1.0117', 'COPETE ALEMÁN BRUNO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (999, 'E1.0118', 'COPETE ALEMÁN BRUNO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1000, 'E1.0119', 'COPETE ALEMÁN BRUNO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1001, 'E1.0120', 'COPETE ALEMÁN BRUNO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1002, 'E1.0121', 'COPETE ALEMÁN BRUNO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1003, 'E1.0122', 'COPETE ALEMÁN BRUNO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1004, 'E1.0123', 'COPETE ALEMÁN BRUNO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1005, 'E1.0124', 'COPETE ALEMÁN BRUNO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1006, 'E1.0125', 'COPETE ALEMÁN BRUNO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1007, 'E1.0126', 'COPETE ALEMÁN BRUNO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1008, 'E1.0127', 'COPETE ALEMÁN BRUNO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1009, 'E1.0128', 'COPETE ALEMÁN BRUNO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1010, 'E1.0129', 'COPETE ALEMÁN ÁGATA BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1011, 'E1.0130', 'COPETE ALEMÁN ÁGATA BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1012, 'E1.0131', 'COPETE ALEMÁN ÁGATA AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1013, 'E1.0132', 'COPETE ALEMÁN ÁGATA AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1014, 'E1.0133', 'COPETE ALEMÁN ÁGATA AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1015, 'E1.0134', 'COPETE ALEMÁN ÁGATA AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1016, 'E1.0135', 'COPETE ALEMÁN ÁGATA AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1017, 'E1.0136', 'COPETE ALEMÁN ÁGATA AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1018, 'E1.0137', 'COPETE ALEMÁN ÁGATA AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1019, 'E1.0138', 'COPETE ALEMÁN ÁGATA AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1020, 'E1.0139', 'COPETE ALEMÁN ÁGATA ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1021, 'E1.0140', 'COPETE ALEMÁN ÁGATA ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1022, 'E1.0141', 'COPETE ALEMÁN ÁGATA ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1023, 'E1.0142', 'COPETE ALEMÁN ÁGATA ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1024, 'E1.0143', 'COPETE ALEMÁN ÁGATA ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1025, 'E1.0144', 'COPETE ALEMÁN ÁGATA ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1026, 'E1.0145', 'COPETE ALEMÁN ÁGATA ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1027, 'E1.0146', 'COPETE ALEMÁN ÁGATA ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1028, 'E1.0147', 'COPETE ALEMÁN ISABEL BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1029, 'E1.0148', 'COPETE ALEMÁN ISABEL BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1030, 'E1.0149', 'COPETE ALEMÁN ISABEL AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1031, 'E1.0150', 'COPETE ALEMÁN ISABEL AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1032, 'E1.0151', 'COPETE ALEMÁN ISABEL AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1033, 'E1.0152', 'COPETE ALEMÁN ISABEL AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1034, 'E1.0153', 'COPETE ALEMÁN ISABEL AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1035, 'E1.0154', 'COPETE ALEMÁN ISABEL AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1036, 'E1.0155', 'COPETE ALEMÁN ISABEL AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1037, 'E1.0156', 'COPETE ALEMÁN ISABEL AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1038, 'E1.0157', 'COPETE ALEMÁN ISABEL ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1039, 'E1.0158', 'COPETE ALEMÁN ISABEL ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1040, 'E1.0159', 'COPETE ALEMÁN ISABEL ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1041, 'E1.0160', 'COPETE ALEMÁN ISABEL ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1042, 'E1.0161', 'COPETE ALEMÁN ISABEL ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1043, 'E1.0162', 'COPETE ALEMÁN ISABEL ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1044, 'E1.0163', 'COPETE ALEMÁN ISABEL ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1045, 'E1.0164', 'COPETE ALEMÁN ISABEL ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1046, 'E1.0165', 'COPETE ALEMÁN NEGRO PASTEL BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1047, 'E1.0166', 'COPETE ALEMÁN NEGRO PASTEL BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1048, 'E1.0167', 'COPETE ALEMÁN NEGRO PASTEL AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1049, 'E1.0168', 'COPETE ALEMÁN NEGRO PASTEL AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1050, 'E1.0169', 'COPETE ALEMÁN NEGRO PASTEL AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1051, 'E1.0170', 'COPETE ALEMÁN NEGRO PASTEL AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1272, 'E1.0391', 'COPETE ALEMÁN NEGRO TOPACIO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1052, 'E1.0171', 'COPETE ALEMÁN NEGRO PASTEL AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1053, 'E1.0172', 'COPETE ALEMÁN NEGRO PASTEL AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1054, 'E1.0173', 'COPETE ALEMÁN NEGRO PASTEL AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1055, 'E1.0174', 'COPETE ALEMÁN NEGRO PASTEL AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1056, 'E1.0175', 'COPETE ALEMÁN NEGRO PASTEL ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1057, 'E1.0176', 'COPETE ALEMÁN NEGRO PASTEL ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1058, 'E1.0177', 'COPETE ALEMÁN NEGRO PASTEL ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1059, 'E1.0178', 'COPETE ALEMÁN NEGRO PASTEL ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1060, 'E1.0179', 'COPETE ALEMÁN NEGRO PASTEL ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1061, 'E1.0180', 'COPETE ALEMÁN NEGRO PASTEL ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1062, 'E1.0181', 'COPETE ALEMÁN NEGRO PASTEL ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1063, 'E1.0182', 'COPETE ALEMÁN NEGRO PASTEL ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1064, 'E1.0183', 'COPETE ALEMÁN BRUNO PASTEL BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1065, 'E1.0184', 'COPETE ALEMÁN BRUNO PASTEL BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1066, 'E1.0185', 'COPETE ALEMÁN BRUNO PASTEL AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1067, 'E1.0186', 'COPETE ALEMÁN BRUNO PASTEL AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1068, 'E1.0187', 'COPETE ALEMÁN BRUNO PASTEL AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1069, 'E1.0188', 'COPETE ALEMÁN BRUNO PASTEL AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1070, 'E1.0189', 'COPETE ALEMÁN BRUNO PASTEL AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1071, 'E1.0190', 'COPETE ALEMÁN BRUNO PASTEL AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1072, 'E1.0191', 'COPETE ALEMÁN BRUNO PASTEL AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1073, 'E1.0192', 'COPETE ALEMÁN BRUNO PASTEL AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1074, 'E1.0193', 'COPETE ALEMÁN BRUNO PASTEL ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1075, 'E1.0194', 'COPETE ALEMÁN BRUNO PASTEL ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1076, 'E1.0195', 'COPETE ALEMÁN BRUNO PASTEL ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1077, 'E1.0196', 'COPETE ALEMÁN BRUNO PASTEL ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1078, 'E1.0197', 'COPETE ALEMÁN BRUNO PASTEL ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1079, 'E1.0198', 'COPETE ALEMÁN BRUNO PASTEL ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1080, 'E1.0199', 'COPETE ALEMÁN BRUNO PASTEL ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1081, 'E1.0200', 'COPETE ALEMÁN BRUNO PASTEL ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1082, 'E1.0201', 'COPETE ALEMÁN ÁGATA PASTEL BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1083, 'E1.0202', 'COPETE ALEMÁN ÁGATA PASTEL BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1084, 'E1.0203', 'COPETE ALEMÁN ÁGATA PASTEL AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1085, 'E1.0204', 'COPETE ALEMÁN ÁGATA PASTEL AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1086, 'E1.0205', 'COPETE ALEMÁN ÁGATA PASTEL AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1087, 'E1.0206', 'COPETE ALEMÁN ÁGATA PASTEL AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1088, 'E1.0207', 'COPETE ALEMÁN ÁGATA PASTEL AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1089, 'E1.0208', 'COPETE ALEMÁN ÁGATA PASTEL AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1090, 'E1.0209', 'COPETE ALEMÁN ÁGATA PASTEL AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1091, 'E1.0210', 'COPETE ALEMÁN ÁGATA PASTEL AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1092, 'E1.0211', 'COPETE ALEMÁN ÁGATA PASTEL ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1093, 'E1.0212', 'COPETE ALEMÁN ÁGATA PASTEL ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1094, 'E1.0213', 'COPETE ALEMÁN ÁGATA PASTEL ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1095, 'E1.0214', 'COPETE ALEMÁN ÁGATA PASTEL ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1096, 'E1.0215', 'COPETE ALEMÁN ÁGATA PASTEL ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1097, 'E1.0216', 'COPETE ALEMÁN ÁGATA PASTEL ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1098, 'E1.0217', 'COPETE ALEMÁN ÁGATA PASTEL ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1099, 'E1.0218', 'COPETE ALEMÁN ÁGATA PASTEL ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1100, 'E1.0219', 'COPETE ALEMÁN ISABEL PASTEL BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1101, 'E1.0220', 'COPETE ALEMÁN ISABEL PASTEL BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1102, 'E1.0221', 'COPETE ALEMÁN ISABEL PASTEL AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1103, 'E1.0222', 'COPETE ALEMÁN ISABEL PASTEL AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1104, 'E1.0223', 'COPETE ALEMÁN ISABEL PASTEL AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1105, 'E1.0224', 'COPETE ALEMÁN ISABEL PASTEL AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1106, 'E1.0225', 'COPETE ALEMÁN ISABEL PASTEL AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1107, 'E1.0226', 'COPETE ALEMÁN ISABEL PASTEL AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1108, 'E1.0227', 'COPETE ALEMÁN ISABEL PASTEL AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1109, 'E1.0228', 'COPETE ALEMÁN ISABEL PASTEL AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1110, 'E1.0229', 'COPETE ALEMÁN ISABEL PASTEL ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1111, 'E1.0230', 'COPETE ALEMÁN ISABEL PASTEL ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1112, 'E1.0231', 'COPETE ALEMÁN ISABEL PASTEL ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1113, 'E1.0232', 'COPETE ALEMÁN ISABEL PASTEL ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1114, 'E1.0233', 'COPETE ALEMÁN ISABEL PASTEL ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1115, 'E1.0234', 'COPETE ALEMÁN ISABEL PASTEL ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1116, 'E1.0235', 'COPETE ALEMÁN ISABEL PASTEL ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1117, 'E1.0236', 'COPETE ALEMÁN ISABEL PASTEL ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1118, 'E1.0237', 'COPETE ALEMÁN NEGRO OPALO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1119, 'E1.0238', 'COPETE ALEMÁN NEGRO OPALO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1120, 'E1.0239', 'COPETE ALEMÁN NEGRO OPALO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1121, 'E1.0240', 'COPETE ALEMÁN NEGRO OPALO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1122, 'E1.0241', 'COPETE ALEMÁN NEGRO OPALO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1123, 'E1.0242', 'COPETE ALEMÁN NEGRO OPALO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1124, 'E1.0243', 'COPETE ALEMÁN NEGRO OPALO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1125, 'E1.0244', 'COPETE ALEMÁN NEGRO OPALO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1126, 'E1.0245', 'COPETE ALEMÁN NEGRO OPALO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1127, 'E1.0246', 'COPETE ALEMÁN NEGRO OPALO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1128, 'E1.0247', 'COPETE ALEMÁN NEGRO OPALO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1129, 'E1.0248', 'COPETE ALEMÁN NEGRO OPALO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1130, 'E1.0249', 'COPETE ALEMÁN NEGRO OPALO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1131, 'E1.0250', 'COPETE ALEMÁN NEGRO OPALO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1132, 'E1.0251', 'COPETE ALEMÁN NEGRO OPALO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1133, 'E1.0252', 'COPETE ALEMÁN NEGRO OPALO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1134, 'E1.0253', 'COPETE ALEMÁN NEGRO OPALO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1135, 'E1.0254', 'COPETE ALEMÁN NEGRO OPALO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1136, 'E1.0255', 'COPETE ALEMÁN BRUNO OPALO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1137, 'E1.0256', 'COPETE ALEMÁN BRUNO OPALO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1138, 'E1.0257', 'COPETE ALEMÁN BRUNO OPALO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1139, 'E1.0258', 'COPETE ALEMÁN BRUNO OPALO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1140, 'E1.0259', 'COPETE ALEMÁN BRUNO OPALO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1141, 'E1.0260', 'COPETE ALEMÁN BRUNO OPALO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1142, 'E1.0261', 'COPETE ALEMÁN BRUNO OPALO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1143, 'E1.0262', 'COPETE ALEMÁN BRUNO OPALO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1144, 'E1.0263', 'COPETE ALEMÁN BRUNO OPALO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1145, 'E1.0264', 'COPETE ALEMÁN BRUNO OPALO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1146, 'E1.0265', 'COPETE ALEMÁN BRUNO OPALO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1147, 'E1.0266', 'COPETE ALEMÁN BRUNO OPALO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1148, 'E1.0267', 'COPETE ALEMÁN BRUNO OPALO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1149, 'E1.0268', 'COPETE ALEMÁN BRUNO OPALO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1150, 'E1.0269', 'COPETE ALEMÁN BRUNO OPALO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1151, 'E1.0270', 'COPETE ALEMÁN BRUNO OPALO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1152, 'E1.0271', 'COPETE ALEMÁN BRUNO OPALO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1153, 'E1.0272', 'COPETE ALEMÁN BRUNO OPALO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1154, 'E1.0273', 'COPETE ALEMÁN ÁGATA OPALO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1155, 'E1.0274', 'COPETE ALEMÁN ÁGATA OPALO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1156, 'E1.0275', 'COPETE ALEMÁN ÁGATA OPALO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1157, 'E1.0276', 'COPETE ALEMÁN ÁGATA OPALO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1158, 'E1.0277', 'COPETE ALEMÁN ÁGATA OPALO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1159, 'E1.0278', 'COPETE ALEMÁN ÁGATA OPALO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1160, 'E1.0279', 'COPETE ALEMÁN ÁGATA OPALO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1161, 'E1.0280', 'COPETE ALEMÁN ÁGATA OPALO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1162, 'E1.0281', 'COPETE ALEMÁN ÁGATA OPALO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1163, 'E1.0282', 'COPETE ALEMÁN ÁGATA OPALO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1164, 'E1.0283', 'COPETE ALEMÁN ÁGATA OPALO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1165, 'E1.0284', 'COPETE ALEMÁN ÁGATA OPALO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1166, 'E1.0285', 'COPETE ALEMÁN ÁGATA OPALO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1167, 'E1.0286', 'COPETE ALEMÁN ÁGATA OPALO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1168, 'E1.0287', 'COPETE ALEMÁN ÁGATA OPALO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1169, 'E1.0288', 'COPETE ALEMÁN ÁGATA OPALO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1170, 'E1.0289', 'COPETE ALEMÁN ÁGATA OPALO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1171, 'E1.0290', 'COPETE ALEMÁN ÁGATA OPALO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1172, 'E1.0291', 'COPETE ALEMÁN ISABEL OPALO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1173, 'E1.0292', 'COPETE ALEMÁN ISABEL OPALO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1174, 'E1.0293', 'COPETE ALEMÁN ISABEL OPALO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1175, 'E1.0294', 'COPETE ALEMÁN ISABEL OPALO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1176, 'E1.0295', 'COPETE ALEMÁN ISABEL OPALO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1177, 'E1.0296', 'COPETE ALEMÁN ISABEL OPALO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1178, 'E1.0297', 'COPETE ALEMÁN ISABEL OPALO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1179, 'E1.0298', 'COPETE ALEMÁN ISABEL OPALO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1180, 'E1.0299', 'COPETE ALEMÁN ISABEL OPALO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1181, 'E1.0300', 'COPETE ALEMÁN ISABEL OPALO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1182, 'E1.0301', 'COPETE ALEMÁN ISABEL OPALO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1183, 'E1.0302', 'COPETE ALEMÁN ISABEL OPALO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1184, 'E1.0303', 'COPETE ALEMÁN ISABEL OPALO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1185, 'E1.0304', 'COPETE ALEMÁN ISABEL OPALO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1186, 'E1.0305', 'COPETE ALEMÁN ISABEL OPALO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1187, 'E1.0306', 'COPETE ALEMÁN ISABEL OPALO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1188, 'E1.0307', 'COPETE ALEMÁN ISABEL OPALO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1189, 'E1.0308', 'COPETE ALEMÁN ISABEL OPALO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1190, 'E1.0309', 'COPETE ALEMÁN FEO ALBINO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1191, 'E1.0310', 'COPETE ALEMÁN FEO ALBINO DOMINANTE MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1192, 'E1.0311', 'COPETE ALEMÁN FEO LUTINO INTENSO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1193, 'E1.0312', 'COPETE ALEMÁN FEO LUTINO NEVADO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1194, 'E1.0313', 'COPETE ALEMÁN FEO LUTINO MARFIL INTENSO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1195, 'E1.0314', 'COPETE ALEMÁN FEO LUTINO MARFIL NEVADO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1196, 'E1.0315', 'COPETE ALEMÁN FEO LUTINO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1197, 'E1.0316', 'COPETE ALEMÁN FEO LUTINO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1198, 'E1.0317', 'COPETE ALEMÁN FEO ALBINO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1199, 'E1.0318', 'COPETE ALEMÁN FEO ALBINO DOMINANTE HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1200, 'E1.0319', 'COPETE ALEMÁN FEO LUTINO INTENSO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1201, 'E1.0320', 'COPETE ALEMÁN FEO LUTINO NEVADO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1202, 'E1.0321', 'COPETE ALEMÁN FEO LUTINO MARFIL INTENSO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1203, 'E1.0322', 'COPETE ALEMÁN FEO LUTINO MARFIL NEVADO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1204, 'E1.0323', 'COPETE ALEMÁN FEO LUTINO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1205, 'E1.0324', 'COPETE ALEMÁN FEO LUTINO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1206, 'E1.0325', 'COPETE ALEMÁN FEO RUBINO INTENSO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1207, 'E1.0326', 'COPETE ALEMÁN FEO RUBINO NEVADO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1208, 'E1.0327', 'COPETE ALEMÁN FEO RUBINO MARFIL INTENSO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1209, 'E1.0328', 'COPETE ALEMÁN FEO RUBINO MARFIL NEVADO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1210, 'E1.0329', 'COPETE ALEMÁN FEO RUBINO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1211, 'E1.0330', 'COPETE ALEMÁN FEO RUBINO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1212, 'E1.0331', 'COPETE ALEMÁN FEO RUBINO INTENSO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1213, 'E1.0332', 'COPETE ALEMÁN FEO RUBINO NEVADO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1214, 'E1.0333', 'COPETE ALEMÁN FEO RUBINO MARFIL INTENSO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1215, 'E1.0334', 'COPETE ALEMÁN FEO RUBINO MARFIL NEVADO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1216, 'E1.0335', 'COPETE ALEMÁN FEO RUBINO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1217, 'E1.0336', 'COPETE ALEMÁN FEO RUBINO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1218, 'E1.0337', 'COPETE ALEMÁN BRUNO SATINÉ BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1219, 'E1.0338', 'COPETE ALEMÁN BRUNO SATINÉ BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1220, 'E1.0339', 'COPETE ALEMÁN BRUNO SATINÉ AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1221, 'E1.0340', 'COPETE ALEMÁN BRUNO SATINÉ AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1222, 'E1.0341', 'COPETE ALEMÁN BRUNO SATINÉ AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1223, 'E1.0342', 'COPETE ALEMÁN BRUNO SATINÉ AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1224, 'E1.0343', 'COPETE ALEMÁN BRUNO SATINÉ AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1225, 'E1.0344', 'COPETE ALEMÁN BRUNO SATINÉ AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1226, 'E1.0345', 'COPETE ALEMÁN BRUNO SATINÉ AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1227, 'E1.0346', 'COPETE ALEMÁN BRUNO SATINÉ AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1228, 'E1.0347', 'COPETE ALEMÁN BRUNO SATINÉ ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1229, 'E1.0348', 'COPETE ALEMÁN BRUNO SATINÉ ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1230, 'E1.0349', 'COPETE ALEMÁN BRUNO SATINÉ ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1231, 'E1.0350', 'COPETE ALEMÁN BRUNO SATINÉ ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1232, 'E1.0351', 'COPETE ALEMÁN BRUNO SATINÉ ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1233, 'E1.0352', 'COPETE ALEMÁN BRUNO SATINÉ ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1234, 'E1.0353', 'COPETE ALEMÁN BRUNO SATINÉ ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1235, 'E1.0354', 'COPETE ALEMÁN BRUNO SATINÉ ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1236, 'E1.0355', 'COPETE ALEMÁN ISABEL SATINÉ BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1237, 'E1.0356', 'COPETE ALEMÁN ISABEL SATINÉ BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1238, 'E1.0357', 'COPETE ALEMÁN ISABEL SATINÉ AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1239, 'E1.0358', 'COPETE ALEMÁN ISABEL SATINÉ AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1240, 'E1.0359', 'COPETE ALEMÁN ISABEL SATINÉ AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1241, 'E1.0360', 'COPETE ALEMÁN ISABEL SATINÉ AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1242, 'E1.0361', 'COPETE ALEMÁN ISABEL SATINÉ AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1243, 'E1.0362', 'COPETE ALEMÁN ISABEL SATINÉ AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1244, 'E1.0363', 'COPETE ALEMÁN ISABEL SATINÉ AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1245, 'E1.0364', 'COPETE ALEMÁN ISABEL SATINÉ AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1246, 'E1.0365', 'COPETE ALEMÁN ISABEL SATINÉ ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1247, 'E1.0366', 'COPETE ALEMÁN ISABEL SATINÉ ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1248, 'E1.0367', 'COPETE ALEMÁN ISABEL SATINÉ ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1249, 'E1.0368', 'COPETE ALEMÁN ISABEL SATINÉ ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1250, 'E1.0369', 'COPETE ALEMÁN ISABEL SATINÉ ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1251, 'E1.0370', 'COPETE ALEMÁN ISABEL SATINÉ ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1252, 'E1.0371', 'COPETE ALEMÁN ISABEL SATINÉ ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1253, 'E1.0372', 'COPETE ALEMÁN ISABEL SATINÉ ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1254, 'E1.0373', 'COPETE ALEMÁN NEGRO ALAS GRISES BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1255, 'E1.0374', 'COPETE ALEMÁN NEGRO ALAS GRISES BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1256, 'E1.0375', 'COPETE ALEMÁN NEGRO ALAS GRISES AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1257, 'E1.0376', 'COPETE ALEMÁN NEGRO ALAS GRISES AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1258, 'E1.0377', 'COPETE ALEMÁN NEGRO ALAS GRISES AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1259, 'E1.0378', 'COPETE ALEMÁN NEGRO ALAS GRISES AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1260, 'E1.0379', 'COPETE ALEMÁN NEGRO ALAS GRISES AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1261, 'E1.0380', 'COPETE ALEMÁN NEGRO ALAS GRISES AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1262, 'E1.0381', 'COPETE ALEMÁN NEGRO ALAS GRISES AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1263, 'E1.0382', 'COPETE ALEMÁN NEGRO ALAS GRISES AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1264, 'E1.0383', 'COPETE ALEMÁN NEGRO ALAS GRISES ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1265, 'E1.0384', 'COPETE ALEMÁN NEGRO ALAS GRISES ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1266, 'E1.0385', 'COPETE ALEMÁN NEGRO ALAS GRISES ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1267, 'E1.0386', 'COPETE ALEMÁN NEGRO ALAS GRISES ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1268, 'E1.0387', 'COPETE ALEMÁN NEGRO ALAS GRISES ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1269, 'E1.0388', 'COPETE ALEMÁN NEGRO ALAS GRISES ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1270, 'E1.0389', 'COPETE ALEMÁN NEGRO ALAS GRISES ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1271, 'E1.0390', 'COPETE ALEMÁN NEGRO ALAS GRISES ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1273, 'E1.0392', 'COPETE ALEMÁN NEGRO TOPACIO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1274, 'E1.0393', 'COPETE ALEMÁN NEGRO TOPACIO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1275, 'E1.0394', 'COPETE ALEMÁN NEGRO TOPACIO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1276, 'E1.0395', 'COPETE ALEMÁN NEGRO TOPACIO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1277, 'E1.0396', 'COPETE ALEMÁN NEGRO TOPACIO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1278, 'E1.0397', 'COPETE ALEMÁN NEGRO TOPACIO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1279, 'E1.0398', 'COPETE ALEMÁN NEGRO TOPACIO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1280, 'E1.0399', 'COPETE ALEMÁN NEGRO TOPACIO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1281, 'E1.0400', 'COPETE ALEMÁN NEGRO TOPACIO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1282, 'E1.0401', 'COPETE ALEMÁN NEGRO TOPACIO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1283, 'E1.0402', 'COPETE ALEMÁN NEGRO TOPACIO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1284, 'E1.0403', 'COPETE ALEMÁN NEGRO TOPACIO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1285, 'E1.0404', 'COPETE ALEMÁN NEGRO TOPACIO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1286, 'E1.0405', 'COPETE ALEMÁN NEGRO TOPACIO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1287, 'E1.0406', 'COPETE ALEMÁN NEGRO TOPACIO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1288, 'E1.0407', 'COPETE ALEMÁN NEGRO TOPACIO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1289, 'E1.0408', 'COPETE ALEMÁN NEGRO TOPACIO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1290, 'E1.0409', 'COPETE ALEMÁN BRUNO TOPACIO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1291, 'E1.0410', 'COPETE ALEMÁN BRUNO TOPACIO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1292, 'E1.0411', 'COPETE ALEMÁN BRUNO TOPACIO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1293, 'E1.0412', 'COPETE ALEMÁN BRUNO TOPACIO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1294, 'E1.0413', 'COPETE ALEMÁN BRUNO TOPACIO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1295, 'E1.0414', 'COPETE ALEMÁN BRUNO TOPACIO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1296, 'E1.0415', 'COPETE ALEMÁN BRUNO TOPACIO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1297, 'E1.0416', 'COPETE ALEMÁN BRUNO TOPACIO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1298, 'E1.0417', 'COPETE ALEMÁN BRUNO TOPACIO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1299, 'E1.0418', 'COPETE ALEMÁN BRUNO TOPACIO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1300, 'E1.0419', 'COPETE ALEMÁN BRUNO TOPACIO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1301, 'E1.0420', 'COPETE ALEMÁN BRUNO TOPACIO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1302, 'E1.0421', 'COPETE ALEMÁN BRUNO TOPACIO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1303, 'E1.0422', 'COPETE ALEMÁN BRUNO TOPACIO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1304, 'E1.0423', 'COPETE ALEMÁN BRUNO TOPACIO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1305, 'E1.0424', 'COPETE ALEMÁN BRUNO TOPACIO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1306, 'E1.0425', 'COPETE ALEMÁN BRUNO TOPACIO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1307, 'E1.0426', 'COPETE ALEMÁN BRUNO TOPACIO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1308, 'E1.0427', 'COPETE ALEMÁN ÁGATA TOPACIO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1309, 'E1.0428', 'COPETE ALEMÁN ÁGATA TOPACIO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1310, 'E1.0429', 'COPETE ALEMÁN ÁGATA TOPACIO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1311, 'E1.0430', 'COPETE ALEMÁN ÁGATA TOPACIO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1312, 'E1.0431', 'COPETE ALEMÁN ÁGATA TOPACIO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1313, 'E1.0432', 'COPETE ALEMÁN ÁGATA TOPACIO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1314, 'E1.0433', 'COPETE ALEMÁN ÁGATA TOPACIO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1315, 'E1.0434', 'COPETE ALEMÁN ÁGATA TOPACIO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1316, 'E1.0435', 'COPETE ALEMÁN ÁGATA TOPACIO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1317, 'E1.0436', 'COPETE ALEMÁN ÁGATA TOPACIO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1318, 'E1.0437', 'COPETE ALEMÁN ÁGATA TOPACIO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1319, 'E1.0438', 'COPETE ALEMÁN ÁGATA TOPACIO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1320, 'E1.0439', 'COPETE ALEMÁN ÁGATA TOPACIO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1321, 'E1.0440', 'COPETE ALEMÁN ÁGATA TOPACIO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1322, 'E1.0441', 'COPETE ALEMÁN ÁGATA TOPACIO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1323, 'E1.0442', 'COPETE ALEMÁN ÁGATA TOPACIO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1324, 'E1.0443', 'COPETE ALEMÁN ÁGATA TOPACIO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1325, 'E1.0444', 'COPETE ALEMÁN ÁGATA TOPACIO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1326, 'E1.0445', 'COPETE ALEMÁN ISABEL TOPACIO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1327, 'E1.0446', 'COPETE ALEMÁN ISABEL TOPACIO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1328, 'E1.0447', 'COPETE ALEMÁN ISABEL TOPACIO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1329, 'E1.0448', 'COPETE ALEMÁN ISABEL TOPACIO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1330, 'E1.0449', 'COPETE ALEMÁN ISABEL TOPACIO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1331, 'E1.0450', 'COPETE ALEMÁN ISABEL TOPACIO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1332, 'E1.0451', 'COPETE ALEMÁN ISABEL TOPACIO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1333, 'E1.0452', 'COPETE ALEMÁN ISABEL TOPACIO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1334, 'E1.0453', 'COPETE ALEMÁN ISABEL TOPACIO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1335, 'E1.0454', 'COPETE ALEMÁN ISABEL TOPACIO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1336, 'E1.0455', 'COPETE ALEMÁN ISABEL TOPACIO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1337, 'E1.0456', 'COPETE ALEMÁN ISABEL TOPACIO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1338, 'E1.0457', 'COPETE ALEMÁN ISABEL TOPACIO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1339, 'E1.0458', 'COPETE ALEMÁN ISABEL TOPACIO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1340, 'E1.0459', 'COPETE ALEMÁN ISABEL TOPACIO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1341, 'E1.0460', 'COPETE ALEMÁN ISABEL TOPACIO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1342, 'E1.0461', 'COPETE ALEMÁN ISABEL TOPACIO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1343, 'E1.0462', 'COPETE ALEMÁN ISABEL TOPACIO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1344, 'E1.0463', 'COPETE ALEMÁN NEGRO EUMO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1345, 'E1.0464', 'COPETE ALEMÁN NEGRO EUMO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1346, 'E1.0465', 'COPETE ALEMÁN NEGRO EUMO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1347, 'E1.0466', 'COPETE ALEMÁN NEGRO EUMO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1348, 'E1.0467', 'COPETE ALEMÁN NEGRO EUMO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1349, 'E1.0468', 'COPETE ALEMÁN NEGRO EUMO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1350, 'E1.0469', 'COPETE ALEMÁN NEGRO EUMO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1351, 'E1.0470', 'COPETE ALEMÁN NEGRO EUMO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1352, 'E1.0471', 'COPETE ALEMÁN NEGRO EUMO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1353, 'E1.0472', 'COPETE ALEMÁN NEGRO EUMO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1354, 'E1.0473', 'COPETE ALEMÁN NEGRO EUMO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1355, 'E1.0474', 'COPETE ALEMÁN NEGRO EUMO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1356, 'E1.0475', 'COPETE ALEMÁN NEGRO EUMO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1357, 'E1.0476', 'COPETE ALEMÁN NEGRO EUMO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1358, 'E1.0477', 'COPETE ALEMÁN NEGRO EUMO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1359, 'E1.0478', 'COPETE ALEMÁN NEGRO EUMO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1360, 'E1.0479', 'COPETE ALEMÁN NEGRO EUMO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1361, 'E1.0480', 'COPETE ALEMÁN NEGRO EUMO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1362, 'E1.0481', 'COPETE ALEMÁN BRUNO EUMO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1363, 'E1.0482', 'COPETE ALEMÁN BRUNO EUMO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1364, 'E1.0483', 'COPETE ALEMÁN BRUNO EUMO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1365, 'E1.0484', 'COPETE ALEMÁN BRUNO EUMO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1366, 'E1.0485', 'COPETE ALEMÁN BRUNO EUMO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1367, 'E1.0486', 'COPETE ALEMÁN BRUNO EUMO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1368, 'E1.0487', 'COPETE ALEMÁN BRUNO EUMO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1369, 'E1.0488', 'COPETE ALEMÁN BRUNO EUMO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1370, 'E1.0489', 'COPETE ALEMÁN BRUNO EUMO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1371, 'E1.0490', 'COPETE ALEMÁN BRUNO EUMO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1372, 'E1.0491', 'COPETE ALEMÁN BRUNO EUMO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1373, 'E1.0492', 'COPETE ALEMÁN BRUNO EUMO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1374, 'E1.0493', 'COPETE ALEMÁN BRUNO EUMO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1375, 'E1.0494', 'COPETE ALEMÁN BRUNO EUMO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1376, 'E1.0495', 'COPETE ALEMÁN BRUNO EUMO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1377, 'E1.0496', 'COPETE ALEMÁN BRUNO EUMO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1378, 'E1.0497', 'COPETE ALEMÁN BRUNO EUMO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1379, 'E1.0498', 'COPETE ALEMÁN BRUNO EUMO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1380, 'E1.0499', 'COPETE ALEMÁN ÁGATA EUMO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1381, 'E1.0500', 'COPETE ALEMÁN ÁGATA EUMO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1382, 'E1.0501', 'COPETE ALEMÁN ÁGATA EUMO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1383, 'E1.0502', 'COPETE ALEMÁN ÁGATA EUMO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1384, 'E1.0503', 'COPETE ALEMÁN ÁGATA EUMO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1385, 'E1.0504', 'COPETE ALEMÁN ÁGATA EUMO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1386, 'E1.0505', 'COPETE ALEMÁN ÁGATA EUMO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1387, 'E1.0506', 'COPETE ALEMÁN ÁGATA EUMO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1388, 'E1.0507', 'COPETE ALEMÁN ÁGATA EUMO AMARILLO MARFIL MOSAICO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1389, 'E1.0508', 'COPETE ALEMÁN ÁGATA EUMO AMARILLO MARFIL MOSAICO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1390, 'E1.0509', 'COPETE ALEMÁN ÁGATA EUMO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1391, 'E1.0510', 'COPETE ALEMÁN ÁGATA EUMO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1392, 'E1.0511', 'COPETE ALEMÁN ÁGATA EUMO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1393, 'E1.0512', 'COPETE ALEMÁN ÁGATA EUMO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1394, 'E1.0513', 'COPETE ALEMÁN ÁGATA EUMO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1395, 'E1.0514', 'COPETE ALEMÁN ÁGATA EUMO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1396, 'E1.0515', 'COPETE ALEMÁN ÁGATA EUMO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1397, 'E1.0516', 'COPETE ALEMÁN ÁGATA EUMO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1398, 'E1.0517', 'COPETE ALEMÁN NEGRO ÓNIX BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1399, 'E1.0518', 'COPETE ALEMÁN NEGRO ÓNIX BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1400, 'E1.0519', 'COPETE ALEMÁN NEGRO ÓNIX AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1401, 'E1.0520', 'COPETE ALEMÁN NEGRO ÓNIX AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1402, 'E1.0521', 'COPETE ALEMÁN NEGRO ÓNIX AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1403, 'E1.0522', 'COPETE ALEMÁN NEGRO ÓNIX AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1404, 'E1.0523', 'COPETE ALEMÁN NEGRO ÓNIX AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1405, 'E1.0524', 'COPETE ALEMÁN NEGRO ÓNIX AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1406, 'E1.0525', 'COPETE ALEMÁN NEGRO ÓNIX AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1407, 'E1.0526', 'COPETE ALEMÁN NEGRO ÓNIX AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1408, 'E1.0527', 'COPETE ALEMÁN NEGRO ÓNIX ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1409, 'E1.0528', 'COPETE ALEMÁN NEGRO ÓNIX ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1410, 'E1.0529', 'COPETE ALEMÁN NEGRO ÓNIX ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1411, 'E1.0530', 'COPETE ALEMÁN NEGRO ÓNIX ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1412, 'E1.0531', 'COPETE ALEMÁN NEGRO ÓNIX ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1413, 'E1.0532', 'COPETE ALEMÁN NEGRO ÓNIX ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1414, 'E1.0533', 'COPETE ALEMÁN NEGRO ÓNIX ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1415, 'E1.0534', 'COPETE ALEMÁN NEGRO ÓNIX ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1416, 'E1.0535', 'COPETE ALEMÁN BRUNO ÓNIX BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1417, 'E1.0536', 'COPETE ALEMÁN BRUNO ÓNIX BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1418, 'E1.0537', 'COPETE ALEMÁN BRUNO ÓNIX AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1419, 'E1.0538', 'COPETE ALEMÁN BRUNO ÓNIX AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1420, 'E1.0539', 'COPETE ALEMÁN BRUNO ÓNIX AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1421, 'E1.0540', 'COPETE ALEMÁN BRUNO ÓNIX AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1422, 'E1.0541', 'COPETE ALEMÁN BRUNO ÓNIX AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1423, 'E1.0542', 'COPETE ALEMÁN BRUNO ÓNIX AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1424, 'E1.0543', 'COPETE ALEMÁN BRUNO ÓNIX AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1425, 'E1.0544', 'COPETE ALEMÁN BRUNO ÓNIX AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1426, 'E1.0545', 'COPETE ALEMÁN BRUNO ÓNIX ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1427, 'E1.0546', 'COPETE ALEMÁN BRUNO ÓNIX ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1428, 'E1.0547', 'COPETE ALEMÁN BRUNO ÓNIX ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1429, 'E1.0548', 'COPETE ALEMÁN BRUNO ÓNIX ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1430, 'E1.0549', 'COPETE ALEMÁN BRUNO ÓNIX ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1431, 'E1.0550', 'COPETE ALEMÁN BRUNO ÓNIX ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1432, 'E1.0551', 'COPETE ALEMÁN BRUNO ÓNIX ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1433, 'E1.0552', 'COPETE ALEMÁN BRUNO ÓNIX ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1434, 'E1.0553', 'COPETE ALEMÁN ÁGATA ÓNIX BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1435, 'E1.0554', 'COPETE ALEMÁN ÁGATA ÓNIX BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1436, 'E1.0555', 'COPETE ALEMÁN ÁGATA ÓNIX AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1437, 'E1.0556', 'COPETE ALEMÁN ÁGATA ÓNIX AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1438, 'E1.0557', 'COPETE ALEMÁN ÁGATA ÓNIX AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1439, 'E1.0558', 'COPETE ALEMÁN ÁGATA ÓNIX AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1440, 'E1.0559', 'COPETE ALEMÁN ÁGATA ÓNIX AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1441, 'E1.0560', 'COPETE ALEMÁN ÁGATA ÓNIX AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1442, 'E1.0561', 'COPETE ALEMÁN ÁGATA ÓNIX AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1443, 'E1.0562', 'COPETE ALEMÁN ÁGATA ÓNIX AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1444, 'E1.0563', 'COPETE ALEMÁN ÁGATA ÓNIX ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1445, 'E1.0564', 'COPETE ALEMÁN ÁGATA ÓNIX ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1446, 'E1.0565', 'COPETE ALEMÁN ÁGATA ÓNIX ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1447, 'E1.0566', 'COPETE ALEMÁN ÁGATA ÓNIX ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1448, 'E1.0567', 'COPETE ALEMÁN ÁGATA ÓNIX ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1449, 'E1.0568', 'COPETE ALEMÁN ÁGATA ÓNIX ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1450, 'E1.0569', 'COPETE ALEMÁN ÁGATA ÓNIX ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1451, 'E1.0570', 'COPETE ALEMÁN ÁGATA ÓNIX ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1452, 'E1.0571', 'COPETE ALEMÁN ISABEL ÓNIX BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1453, 'E1.0572', 'COPETE ALEMÁN ISABEL ÓNIX BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1454, 'E1.0573', 'COPETE ALEMÁN ISABEL ÓNIX AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1455, 'E1.0574', 'COPETE ALEMÁN ISABEL ÓNIX AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1456, 'E1.0575', 'COPETE ALEMÁN ISABEL ÓNIX AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1457, 'E1.0576', 'COPETE ALEMÁN ISABEL ÓNIX AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1458, 'E1.0577', 'COPETE ALEMÁN ISABEL ÓNIX AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1459, 'E1.0578', 'COPETE ALEMÁN ISABEL ÓNIX AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1460, 'E1.0579', 'COPETE ALEMÁN ISABEL ÓNIX AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1461, 'E1.0580', 'COPETE ALEMÁN ISABEL ÓNIX AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1462, 'E1.0581', 'COPETE ALEMÁN ISABEL ÓNIX ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1463, 'E1.0582', 'COPETE ALEMÁN ISABEL ÓNIX ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1464, 'E1.0583', 'COPETE ALEMÁN ISABEL ÓNIX ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1465, 'E1.0584', 'COPETE ALEMÁN ISABEL ÓNIX ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1466, 'E1.0585', 'COPETE ALEMÁN ISABEL ÓNIX ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1467, 'E1.0586', 'COPETE ALEMÁN ISABEL ÓNIX ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1468, 'E1.0587', 'COPETE ALEMÁN ISABEL ÓNIX ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1469, 'E1.0588', 'COPETE ALEMÁN ISABEL ÓNIX ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1470, 'E1.0589', 'COPETE ALEMÁN NEGRO COBALTO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1471, 'E1.0590', 'COPETE ALEMÁN NEGRO COBALTO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1472, 'E1.0591', 'COPETE ALEMÁN NEGRO COBALTO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1473, 'E1.0592', 'COPETE ALEMÁN NEGRO COBALTO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1474, 'E1.0593', 'COPETE ALEMÁN NEGRO COBALTO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1475, 'E1.0594', 'COPETE ALEMÁN NEGRO COBALTO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1476, 'E1.0595', 'COPETE ALEMÁN NEGRO COBALTO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1477, 'E1.0596', 'COPETE ALEMÁN NEGRO COBALTO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1478, 'E1.0597', 'COPETE ALEMÁN NEGRO COBALTO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1479, 'E1.0598', 'COPETE ALEMÁN NEGRO COBALTO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1480, 'E1.0599', 'COPETE ALEMÁN NEGRO COBALTO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1481, 'E1.0600', 'COPETE ALEMÁN NEGRO COBALTO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1482, 'E1.0601', 'COPETE ALEMÁN NEGRO COBALTO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1483, 'E1.0602', 'COPETE ALEMÁN NEGRO COBALTO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1484, 'E1.0603', 'COPETE ALEMÁN NEGRO COBALTO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1485, 'E1.0604', 'COPETE ALEMÁN NEGRO COBALTO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1486, 'E1.0605', 'COPETE ALEMÁN NEGRO COBALTO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1487, 'E1.0606', 'COPETE ALEMÁN NEGRO COBALTO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1488, 'E1.0607', 'COPETE ALEMÁN BRUNO COBALTO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1489, 'E1.0608', 'COPETE ALEMÁN BRUNO COBALTO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1490, 'E1.0609', 'COPETE ALEMÁN BRUNO COBALTO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1491, 'E1.0610', 'COPETE ALEMÁN BRUNO COBALTO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1492, 'E1.0611', 'COPETE ALEMÁN BRUNO COBALTO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1493, 'E1.0612', 'COPETE ALEMÁN BRUNO COBALTO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1494, 'E1.0613', 'COPETE ALEMÁN BRUNO COBALTO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1495, 'E1.0614', 'COPETE ALEMÁN BRUNO COBALTO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1496, 'E1.0615', 'COPETE ALEMÁN BRUNO COBALTO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1497, 'E1.0616', 'COPETE ALEMÁN BRUNO COBALTO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1498, 'E1.0617', 'COPETE ALEMÁN BRUNO COBALTO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1499, 'E1.0618', 'COPETE ALEMÁN BRUNO COBALTO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1500, 'E1.0619', 'COPETE ALEMÁN BRUNO COBALTO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1501, 'E1.0620', 'COPETE ALEMÁN BRUNO COBALTO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1502, 'E1.0621', 'COPETE ALEMÁN BRUNO COBALTO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1503, 'E1.0622', 'COPETE ALEMÁN BRUNO COBALTO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1504, 'E1.0623', 'COPETE ALEMÁN BRUNO COBALTO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1505, 'E1.0624', 'COPETE ALEMÁN BRUNO COBALTO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1506, 'E1.0625', 'COPETE ALEMÁN ÁGATA COBALTO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1507, 'E1.0626', 'COPETE ALEMÁN ÁGATA COBALTO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1508, 'E1.0627', 'COPETE ALEMÁN ÁGATA COBALTO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1509, 'E1.0628', 'COPETE ALEMÁN ÁGATA COBALTO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1510, 'E1.0629', 'COPETE ALEMÁN ÁGATA COBALTO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1511, 'E1.0630', 'COPETE ALEMÁN ÁGATA COBALTO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1512, 'E1.0631', 'COPETE ALEMÁN ÁGATA COBALTO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1513, 'E1.0632', 'COPETE ALEMÁN ÁGATA COBALTO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1514, 'E1.0633', 'COPETE ALEMÁN ÁGATA COBALTO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1515, 'E1.0634', 'COPETE ALEMÁN ÁGATA COBALTO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1516, 'E1.0635', 'COPETE ALEMÁN ÁGATA COBALTO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1517, 'E1.0636', 'COPETE ALEMÁN ÁGATA COBALTO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1518, 'E1.0637', 'COPETE ALEMÁN ÁGATA COBALTO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1519, 'E1.0638', 'COPETE ALEMÁN ÁGATA COBALTO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1520, 'E1.0639', 'COPETE ALEMÁN ÁGATA COBALTO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1521, 'E1.0640', 'COPETE ALEMÁN ÁGATA COBALTO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1522, 'E1.0641', 'COPETE ALEMÁN ÁGATA COBALTO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1523, 'E1.0642', 'COPETE ALEMÁN ÁGATA COBALTO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1524, 'E1.0643', 'COPETE ALEMÁN ISABEL COBALTO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1525, 'E1.0644', 'COPETE ALEMÁN ISABEL COBALTO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1526, 'E1.0645', 'COPETE ALEMÁN ISABEL COBALTO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1527, 'E1.0646', 'COPETE ALEMÁN ISABEL COBALTO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1528, 'E1.0647', 'COPETE ALEMÁN ISABEL COBALTO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1529, 'E1.0648', 'COPETE ALEMÁN ISABEL COBALTO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1530, 'E1.0649', 'COPETE ALEMÁN ISABEL COBALTO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1531, 'E1.0650', 'COPETE ALEMÁN ISABEL COBALTO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1532, 'E1.0651', 'COPETE ALEMÁN ISABEL COBALTO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1533, 'E1.0652', 'COPETE ALEMÁN ISABEL COBALTO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1534, 'E1.0653', 'COPETE ALEMÁN ISABEL COBALTO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1535, 'E1.0654', 'COPETE ALEMÁN ISABEL COBALTO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1536, 'E1.0655', 'COPETE ALEMÁN ISABEL COBALTO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1537, 'E1.0656', 'COPETE ALEMÁN ISABEL COBALTO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1538, 'E1.0657', 'COPETE ALEMÁN ISABEL COBALTO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1539, 'E1.0658', 'COPETE ALEMÁN ISABEL COBALTO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1540, 'E1.0659', 'COPETE ALEMÁN ISABEL COBALTO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1541, 'E1.0660', 'COPETE ALEMÁN ISABEL COBALTO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1542, 'E1.0661', 'COPETE ALEMÁN NEGRO JASPE SD BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1543, 'E1.0662', 'COPETE ALEMÁN NEGRO JASPE SD BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1544, 'E1.0663', 'COPETE ALEMÁN NEGRO JASPE SD AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1545, 'E1.0664', 'COPETE ALEMÁN NEGRO JASPE SD AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1546, 'E1.0665', 'COPETE ALEMÁN NEGRO JASPE SD AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1547, 'E1.0666', 'COPETE ALEMÁN NEGRO JASPE SD AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1548, 'E1.0667', 'COPETE ALEMÁN NEGRO JASPE SD AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1549, 'E1.0668', 'COPETE ALEMÁN NEGRO JASPE SD AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1550, 'E1.0669', 'COPETE ALEMÁN NEGRO JASPE SD AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1551, 'E1.0670', 'COPETE ALEMÁN NEGRO JASPE SD AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1552, 'E1.0671', 'COPETE ALEMÁN NEGRO JASPE SD ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1553, 'E1.0672', 'COPETE ALEMÁN NEGRO JASPE SD ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1554, 'E1.0673', 'COPETE ALEMÁN NEGRO JASPE SD ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1555, 'E1.0674', 'COPETE ALEMÁN NEGRO JASPE SD ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1556, 'E1.0675', 'COPETE ALEMÁN NEGRO JASPE SD ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1557, 'E1.0676', 'COPETE ALEMÁN NEGRO JASPE SD ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1558, 'E1.0677', 'COPETE ALEMÁN NEGRO JASPE SD ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1559, 'E1.0678', 'COPETE ALEMÁN NEGRO JASPE SD ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1560, 'E1.0679', 'COPETE ALEMÁN BRUNO JASPE SD BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1561, 'E1.0680', 'COPETE ALEMÁN BRUNO JASPE SD BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1562, 'E1.0681', 'COPETE ALEMÁN BRUNO JASPE SD AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1563, 'E1.0682', 'COPETE ALEMÁN BRUNO JASPE SD AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1564, 'E1.0683', 'COPETE ALEMÁN BRUNO JASPE SD AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1565, 'E1.0684', 'COPETE ALEMÁN BRUNO JASPE SD AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1566, 'E1.0685', 'COPETE ALEMÁN BRUNO JASPE SD AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1567, 'E1.0686', 'COPETE ALEMÁN BRUNO JASPE SD AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1568, 'E1.0687', 'COPETE ALEMÁN BRUNO JASPE SD AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1569, 'E1.0688', 'COPETE ALEMÁN BRUNO JASPE SD AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1570, 'E1.0689', 'COPETE ALEMÁN BRUNO JASPE SD ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1571, 'E1.0690', 'COPETE ALEMÁN BRUNO JASPE SD ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1572, 'E1.0691', 'COPETE ALEMÁN BRUNO JASPE SD ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1573, 'E1.0692', 'COPETE ALEMÁN BRUNO JASPE SD ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1574, 'E1.0693', 'COPETE ALEMÁN BRUNO JASPE SD ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1575, 'E1.0694', 'COPETE ALEMÁN BRUNO JASPE SD ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1576, 'E1.0695', 'COPETE ALEMÁN BRUNO JASPE SD ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1577, 'E1.0696', 'COPETE ALEMÁN BRUNO JASPE SD ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1578, 'E1.0697', 'COPETE ALEMÁN ÁGATA JASPE SD BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1579, 'E1.0698', 'COPETE ALEMÁN ÁGATA JASPE SD BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1580, 'E1.0699', 'COPETE ALEMÁN ÁGATA JASPE SD AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1581, 'E1.0700', 'COPETE ALEMÁN ÁGATA JASPE SD AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1582, 'E1.0701', 'COPETE ALEMÁN ÁGATA JASPE SD AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1583, 'E1.0702', 'COPETE ALEMÁN ÁGATA JASPE SD AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1584, 'E1.0703', 'COPETE ALEMÁN ÁGATA JASPE SD AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1585, 'E1.0704', 'COPETE ALEMÁN ÁGATA JASPE SD AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1586, 'E1.0705', 'COPETE ALEMÁN ÁGATA JASPE SD AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1587, 'E1.0706', 'COPETE ALEMÁN ÁGATA JASPE SD AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1588, 'E1.0707', 'COPETE ALEMÁN ÁGATA JASPE SD ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1589, 'E1.0708', 'COPETE ALEMÁN ÁGATA JASPE SD ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1590, 'E1.0709', 'COPETE ALEMÁN ÁGATA JASPE SD ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1591, 'E1.0710', 'COPETE ALEMÁN ÁGATA JASPE SD ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1592, 'E1.0711', 'COPETE ALEMÁN ÁGATA JASPE SD ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1593, 'E1.0712', 'COPETE ALEMÁN ÁGATA JASPE SD ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1594, 'E1.0713', 'COPETE ALEMÁN ÁGATA JASPE SD ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1595, 'E1.0714', 'COPETE ALEMÁN ÁGATA JASPE SD ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1596, 'E1.0715', 'COPETE ALEMÁN ISABEL JASPE SD BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1597, 'E1.0716', 'COPETE ALEMÁN ISABEL JASPE SD BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1598, 'E1.0717', 'COPETE ALEMÁN ISABEL JASPE SD AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1599, 'E1.0718', 'COPETE ALEMÁN ISABEL JASPE SD AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1600, 'E1.0719', 'COPETE ALEMÁN ISABEL JASPE SD AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1601, 'E1.0720', 'COPETE ALEMÁN ISABEL JASPE SD AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1602, 'E1.0721', 'COPETE ALEMÁN ISABEL JASPE SD AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1603, 'E1.0722', 'COPETE ALEMÁN ISABEL JASPE SD AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1604, 'E1.0723', 'COPETE ALEMÁN ISABEL JASPE SD AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1605, 'E1.0724', 'COPETE ALEMÁN ISABEL JASPE SD AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1606, 'E1.0725', 'COPETE ALEMÁN ISABEL JASPE SD ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1607, 'E1.0726', 'COPETE ALEMÁN ISABEL JASPE SD ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1608, 'E1.0727', 'COPETE ALEMÁN ISABEL JASPE SD ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1609, 'E1.0728', 'COPETE ALEMÁN ISABEL JASPE SD ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1610, 'E1.0729', 'COPETE ALEMÁN ISABEL JASPE SD ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1611, 'E1.0730', 'COPETE ALEMÁN ISABEL JASPE SD ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1612, 'E1.0731', 'COPETE ALEMÁN ISABEL JASPE SD ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1613, 'E1.0732', 'COPETE ALEMÁN ISABEL JASPE SD ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1614, 'E1.0733', 'COPETE ALEMÁN NEGRO JASPE DD BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1615, 'E1.0734', 'COPETE ALEMÁN NEGRO JASPE DD BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1616, 'E1.0735', 'COPETE ALEMÁN NEGRO JASPE DD AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1617, 'E1.0736', 'COPETE ALEMÁN NEGRO JASPE DD AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1618, 'E1.0737', 'COPETE ALEMÁN NEGRO JASPE DD AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1619, 'E1.0738', 'COPETE ALEMÁN NEGRO JASPE DD AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1620, 'E1.0739', 'COPETE ALEMÁN NEGRO JASPE DD AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1621, 'E1.0740', 'COPETE ALEMÁN NEGRO JASPE DD AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1622, 'E1.0741', 'COPETE ALEMÁN NEGRO JASPE DD AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1623, 'E1.0742', 'COPETE ALEMÁN NEGRO JASPE DD AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1624, 'E1.0743', 'COPETE ALEMÁN NEGRO JASPE DD ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1625, 'E1.0744', 'COPETE ALEMÁN NEGRO JASPE DD ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1626, 'E1.0745', 'COPETE ALEMÁN NEGRO JASPE DD ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1627, 'E1.0746', 'COPETE ALEMÁN NEGRO JASPE DD ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1628, 'E1.0747', 'COPETE ALEMÁN NEGRO JASPE DD ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1629, 'E1.0748', 'COPETE ALEMÁN NEGRO JASPE DD ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1630, 'E1.0749', 'COPETE ALEMÁN NEGRO JASPE DD ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1631, 'E1.0750', 'COPETE ALEMÁN NEGRO JASPE DD ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1632, 'E1.0751', 'COPETE ALEMÁN BRUNO JASPE DD BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1633, 'E1.0752', 'COPETE ALEMÁN BRUNO JASPE DD BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1634, 'E1.0753', 'COPETE ALEMÁN BRUNO JASPE DD AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1790, 'E1.1103', 'LIZARD CUPULA IMPERF FDO AM NEV', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1635, 'E1.0754', 'COPETE ALEMÁN BRUNO JASPE DD AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1636, 'E1.0755', 'COPETE ALEMÁN BRUNO JASPE DD AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1637, 'E1.0756', 'COPETE ALEMÁN BRUNO JASPE DD AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1638, 'E1.0757', 'COPETE ALEMÁN BRUNO JASPE DD AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1639, 'E1.0758', 'COPETE ALEMÁN BRUNO JASPE DD AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1640, 'E1.0759', 'COPETE ALEMÁN BRUNO JASPE DD AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1641, 'E1.0760', 'COPETE ALEMÁN BRUNO JASPE DD AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1642, 'E1.0761', 'COPETE ALEMÁN BRUNO JASPE DD ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1643, 'E1.0762', 'COPETE ALEMÁN BRUNO JASPE DD ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1644, 'E1.0763', 'COPETE ALEMÁN BRUNO JASPE DD ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1645, 'E1.0764', 'COPETE ALEMÁN BRUNO JASPE DD ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1646, 'E1.0765', 'COPETE ALEMÁN BRUNO JASPE DD ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1647, 'E1.0766', 'COPETE ALEMÁN BRUNO JASPE DD ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1648, 'E1.0767', 'COPETE ALEMÁN BRUNO JASPE DD ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1649, 'E1.0768', 'COPETE ALEMÁN BRUNO JASPE DD ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1650, 'E1.0769', 'COPETE ALEMÁN ÁGATA JASPE DD BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1651, 'E1.0770', 'COPETE ALEMÁN ÁGATA JASPE DD BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1652, 'E1.0771', 'COPETE ALEMÁN ÁGATA JASPE DD AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1653, 'E1.0772', 'COPETE ALEMÁN ÁGATA JASPE DD AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1654, 'E1.0773', 'COPETE ALEMÁN ÁGATA JASPE DD AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1655, 'E1.0774', 'COPETE ALEMÁN ÁGATA JASPE DD AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1656, 'E1.0775', 'COPETE ALEMÁN ÁGATA JASPE DD AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1657, 'E1.0776', 'COPETE ALEMÁN ÁGATA JASPE DD AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1658, 'E1.0777', 'COPETE ALEMÁN ÁGATA JASPE DD AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1659, 'E1.0778', 'COPETE ALEMÁN ÁGATA JASPE DD AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1660, 'E1.0779', 'COPETE ALEMÁN ÁGATA JASPE DD ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1661, 'E1.0780', 'COPETE ALEMÁN ÁGATA JASPE DD ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1662, 'E1.0781', 'COPETE ALEMÁN ÁGATA JASPE DD ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1663, 'E1.0782', 'COPETE ALEMÁN ÁGATA JASPE DD ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1664, 'E1.0783', 'COPETE ALEMÁN ÁGATA JASPE DD ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1665, 'E1.0784', 'COPETE ALEMÁN ÁGATA JASPE DD ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1666, 'E1.0785', 'COPETE ALEMÁN ÁGATA JASPE DD ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1667, 'E1.0786', 'COPETE ALEMÁN ÁGATA JASPE DD ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1668, 'E1.0787', 'COPETE ALEMÁN NEGRO MOGNO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1669, 'E1.0788', 'COPETE ALEMÁN NEGRO MOGNO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1670, 'E1.0789', 'COPETE ALEMÁN NEGRO MOGNO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1671, 'E1.0790', 'COPETE ALEMÁN NEGRO MOGNO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1672, 'E1.0791', 'COPETE ALEMÁN NEGRO MOGNO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1673, 'E1.0792', 'COPETE ALEMÁN NEGRO MOGNO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1674, 'E1.0793', 'COPETE ALEMÁN NEGRO MOGNO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1675, 'E1.0794', 'COPETE ALEMÁN NEGRO MOGNO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1676, 'E1.0795', 'COPETE ALEMÁN NEGRO MOGNO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1677, 'E1.0796', 'COPETE ALEMÁN NEGRO MOGNO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1678, 'E1.0797', 'COPETE ALEMÁN NEGRO MOGNO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1679, 'E1.0798', 'COPETE ALEMÁN NEGRO MOGNO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1680, 'E1.0799', 'COPETE ALEMÁN NEGRO MOGNO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1681, 'E1.0800', 'COPETE ALEMÁN NEGRO MOGNO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1682, 'E1.0801', 'COPETE ALEMÁN NEGRO MOGNO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1683, 'E1.0802', 'COPETE ALEMÁN NEGRO MOGNO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1684, 'E1.0803', 'COPETE ALEMÁN NEGRO MOGNO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1685, 'E1.0804', 'COPETE ALEMÁN NEGRO MOGNO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1686, 'E1.0805', 'COPETE ALEMÁN BRUNO MOGNO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1687, 'E1.0806', 'COPETE ALEMÁN BRUNO MOGNO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1688, 'E1.0807', 'COPETE ALEMÁN BRUNO MOGNO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1689, 'E1.0808', 'COPETE ALEMÁN BRUNO MOGNO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1690, 'E1.0809', 'COPETE ALEMÁN BRUNO MOGNO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1691, 'E1.0810', 'COPETE ALEMÁN BRUNO MOGNO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1692, 'E1.0811', 'COPETE ALEMÁN BRUNO MOGNO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1693, 'E1.0812', 'COPETE ALEMÁN BRUNO MOGNO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1694, 'E1.0813', 'COPETE ALEMÁN BRUNO MOGNO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1695, 'E1.0814', 'COPETE ALEMÁN BRUNO MOGNO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1696, 'E1.0815', 'COPETE ALEMÁN BRUNO MOGNO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1697, 'E1.0816', 'COPETE ALEMÁN BRUNO MOGNO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1698, 'E1.0817', 'COPETE ALEMÁN BRUNO MOGNO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1699, 'E1.0818', 'COPETE ALEMÁN BRUNO MOGNO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1700, 'E1.0819', 'COPETE ALEMÁN BRUNO MOGNO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1701, 'E1.0820', 'COPETE ALEMÁN BRUNO MOGNO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1702, 'E1.0821', 'COPETE ALEMÁN BRUNO MOGNO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1703, 'E1.0822', 'COPETE ALEMÁN BRUNO MOGNO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1704, 'E1.0823', 'COPETE ALEMÁN ÁGATA MOGNO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1705, 'E1.0824', 'COPETE ALEMÁN ÁGATA MOGNO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1706, 'E1.0825', 'COPETE ALEMÁN ÁGATA MOGNO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1707, 'E1.0826', 'COPETE ALEMÁN ÁGATA MOGNO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1708, 'E1.0827', 'COPETE ALEMÁN ÁGATA MOGNO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1709, 'E1.0828', 'COPETE ALEMÁN ÁGATA MOGNO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1710, 'E1.0829', 'COPETE ALEMÁN ÁGATA MOGNO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1711, 'E1.0830', 'COPETE ALEMÁN ÁGATA MOGNO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1712, 'E1.0831', 'COPETE ALEMÁN ÁGATA MOGNO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1713, 'E1.0832', 'COPETE ALEMÁN ÁGATA MOGNO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1714, 'E1.0833', 'COPETE ALEMÁN ÁGATA MOGNO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1715, 'E1.0834', 'COPETE ALEMÁN ÁGATA MOGNO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1716, 'E1.0835', 'COPETE ALEMÁN ÁGATA MOGNO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1717, 'E1.0836', 'COPETE ALEMÁN ÁGATA MOGNO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1718, 'E1.0837', 'COPETE ALEMÁN ÁGATA MOGNO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1719, 'E1.0838', 'COPETE ALEMÁN ÁGATA MOGNO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1720, 'E1.0839', 'COPETE ALEMÁN ÁGATA MOGNO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1721, 'E1.0840', 'COPETE ALEMÁN ÁGATA MOGNO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1722, 'E1.0841', 'COPETE ALEMÁN ISABEL MOGNO BLANCO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1723, 'E1.0842', 'COPETE ALEMÁN ISABEL MOGNO BLANCO DOMINANTE', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1724, 'E1.0843', 'COPETE ALEMÁN ISABEL MOGNO AMARILLO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1725, 'E1.0844', 'COPETE ALEMÁN ISABEL MOGNO AMARILLO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1726, 'E1.0845', 'COPETE ALEMÁN ISABEL MOGNO AMARILLO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1727, 'E1.0846', 'COPETE ALEMÁN ISABEL MOGNO AMARILLO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1728, 'E1.0847', 'COPETE ALEMÁN ISABEL MOGNO AMARILLO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1729, 'E1.0848', 'COPETE ALEMÁN ISABEL MOGNO AMARILLO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1730, 'E1.0849', 'COPETE ALEMÁN ISABEL MOGNO AMARILLO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1731, 'E1.0850', 'COPETE ALEMÁN ISABEL MOGNO AMARILLO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1732, 'E1.0851', 'COPETE ALEMÁN ISABEL MOGNO ROJO INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1733, 'E1.0852', 'COPETE ALEMÁN ISABEL MOGNO ROJO NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1734, 'E1.0853', 'COPETE ALEMÁN ISABEL MOGNO ROJO MARFIL INTENSO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1735, 'E1.0854', 'COPETE ALEMÁN ISABEL MOGNO ROJO MARFIL NEVADO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1736, 'E1.0855', 'COPETE ALEMÁN ISABEL MOGNO ROJO MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1737, 'E1.0856', 'COPETE ALEMÁN ISABEL MOGNO ROJO MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1738, 'E1.0857', 'COPETE ALEMÁN ISABEL MOGNO ROJO MARFIL MOSAICO MACHO', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1739, 'E1.0858', 'COPETE ALEMÁN ISABEL MOGNO ROJO MARFIL MOSAICO HEMBRA', 'CP', 'COPETE ALEMÁN', DEFAULT);
INSERT INTO public.variedad VALUES (1740, 'E1.1001', 'ARLEQUIN PORTUGUES SIN COPETE MACHO', 'CP', 'ARLEQUÍN PORTUGUÉS', DEFAULT);
INSERT INTO public.variedad VALUES (1741, 'E1.1002', 'ARLEQUIN PORTUGUES SIN COPETE HEMBRA', 'CP', 'ARLEQUÍN PORTUGUÉS', DEFAULT);
INSERT INTO public.variedad VALUES (1742, 'E1.1003', 'ARLEQUIN PORTUGUES CON COPETE MACHO', 'CP', 'ARLEQUÍN PORTUGUÉS', DEFAULT);
INSERT INTO public.variedad VALUES (1743, 'E1.1004', 'ARLEQUIN PORTUGUES CON COPETE HEMBRA', 'CP', 'ARLEQUÍN PORTUGUÉS', DEFAULT);
INSERT INTO public.variedad VALUES (1744, 'E1.1021', 'IRISH FANCY FDO BL LIP', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1745, 'E1.1022', 'IRISH FANCY FDO BL MEL', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1746, 'E1.1023', 'IRISH FANCY FDO BL OVE LIP', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1747, 'E1.1024', 'IRISH FANCY FDO BL OVE MEL', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1748, 'E1.1025', 'IRISH FANCY FDO AM INT LIP', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1749, 'E1.1026', 'IRISH FANCY FDO AM INT MEL', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1750, 'E1.1027', 'IRISH FANCY FDO AM INT OVE LIP', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1751, 'E1.1028', 'IRISH FANCY FDO AM INT OVE MEL', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1752, 'E1.1029', 'IRISH FANCY FDO AM NEV LIP', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1753, 'E1.1030', 'IRISH FANCY FDO AM NEV MEL', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1754, 'E1.1031', 'IRISH FANCY FDO AM NEV OVE LIP', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1755, 'E1.1032', 'IRISH FANCY FDO AM NEV OVE MEL', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1756, 'E1.1033', 'IRISH FANCY FDO BRUNO BL MEL', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1757, 'E1.1034', 'IRISH FANCY FDO BRUNO BL OVE LIP', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1758, 'E1.1035', 'IRISH FANCY FDO BRUNO BL OVE MEL', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1759, 'E1.1036', 'IRISH FANCY FDO BRUNO AM INT MEL', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1760, 'E1.1037', 'IRISH FANCY FDO BRUNO AM INT OVE LIP', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1761, 'E1.1038', 'IRISH FANCY FDO BRUNO AM INT OVE MEL', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1762, 'E1.1039', 'IRISH FANCY FDO BRUNO AM NEV MEL', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1763, 'E1.1040', 'IRISH FANCY FDO BRUNO AM NEV OVE LIP', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1764, 'E1.1041', 'IRISH FANCY FDO BRUNO AM NEV OVE MEL', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1765, 'E1.1042', 'IRISH FANCY FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1766, 'E1.1043', 'IRISH FANCY FDO OTRAS MUTACIONES AM INT TODOS', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1767, 'E1.1044', 'IRISH FANCY FDO OTRAS MUTACIONES AM NEV TODOS', 'CP', 'IRISH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1768, 'E1.1081', 'LIZARD CUPULA PERF FDO BL', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1769, 'E1.1082', 'LIZARD CUPULA PERF FDO AM INT', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1770, 'E1.1083', 'LIZARD CUPULA PERF FDO AM NEV', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1771, 'E1.1084', 'LIZARD CUPULA PERF FDO RO INT', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1772, 'E1.1085', 'LIZARD CUPULA PERF FDO RO NEV', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1773, 'E1.1086', 'LIZARD CUPULA PERF FDO BRUNO BL', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1774, 'E1.1087', 'LIZARD CUPULA PERF FDO BRUNO AM INT', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1775, 'E1.1088', 'LIZARD CUPULA PERF FDO BRUNO AM NEV', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1776, 'E1.1089', 'LIZARD CUPULA PERF FDO BRUNO RO INT', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1777, 'E1.1090', 'LIZARD CUPULA PERF FDO BRUNO RO NEV', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1778, 'E1.1091', 'LIZARD SIN CUPULA FDO BL', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1779, 'E1.1092', 'LIZARD SIN CUPULA FDO AM INT', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1780, 'E1.1093', 'LIZARD SIN CUPULA FDO AM NEV', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1781, 'E1.1094', 'LIZARD SIN CUPULA FDO RO INT', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1782, 'E1.1095', 'LIZARD SIN CUPULA FDO RO NEV', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1783, 'E1.1096', 'LIZARD SIN CUPULA FDO BRUNO BL', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1784, 'E1.1097', 'LIZARD SIN CUPULA FDO BRUNO AM INT', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1785, 'E1.1098', 'LIZARD SIN CUPULA FDO BRUNO AM NEV', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1786, 'E1.1099', 'LIZARD SIN CUPULA FDO BRUNO RO INT', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1787, 'E1.1100', 'LIZARD SIN CUPULA FDO BRUNO RO NEV', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1788, 'E1.1101', 'LIZARD CUPULA IMPERF FDO BL', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1789, 'E1.1102', 'LIZARD CUPULA IMPERF FDO AM INT', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1791, 'E1.1104', 'LIZARD CUPULA IMPERF FDO RO INT', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1792, 'E1.1105', 'LIZARD CUPULA IMPERF FDO RO NEV', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1793, 'E1.1106', 'LIZARD CUPULA IMPERF FDO BRUNO BL', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1794, 'E1.1107', 'LIZARD CUPULA IMPERF FDO BRUNO AM INT', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1795, 'E1.1108', 'LIZARD CUPULA IMPERF FDO BRUNO AM NEV', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1796, 'E1.1109', 'LIZARD CUPULA IMPERF FDO BRUNO RO INT', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1797, 'E1.1110', 'LIZARD CUPULA IMPERF FDO BRUNO RO NEV', 'CP', 'LIZARD', DEFAULT);
INSERT INTO public.variedad VALUES (1798, 'E1.1141', 'LONDON FANCY FDO BLANCO', 'CP', 'LONDON FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1799, 'E1.1142', 'LONDON FANCY FDO AM INT', 'CP', 'LONDON FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1800, 'E1.1143', 'LONDON FANCY FDO AM NEV', 'CP', 'LONDON FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1801, 'E1.1144', 'LONDON FANCY FDO BRUNO BLANCO', 'CP', 'LONDON FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1802, 'E1.1145', 'LONDON FANCY FDO BRUNO AM INT', 'CP', 'LONDON FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1803, 'E1.1146', 'LONDON FANCY FDO BRUNO AM NEV', 'CP', 'LONDON FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1804, 'E1.1171', 'GLOSTER CONSORTE FDO BL LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1805, 'E1.1172', 'GLOSTER CONSORTE FDO BL MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1806, 'E1.1173', 'GLOSTER CONSORTE FDO BL OVE LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1807, 'E1.1174', 'GLOSTER CONSORTE FDO BL OVE MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1808, 'E1.1175', 'GLOSTER CONSORTE FDO AM IN LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1809, 'E1.1176', 'GLOSTER CONSORTE FDO AM INT MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1810, 'E1.1177', 'GLOSTER CONSORTE FDO AM INT OVE LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1811, 'E1.1178', 'GLOSTER CONSORTE FDO AM INT OVE MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1812, 'E1.1179', 'GLOSTER CONSORTE FDO AM NEV LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1813, 'E1.1180', 'GLOSTER CONSORTE FDO AM NEV MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1814, 'E1.1181', 'GLOSTER CONSORTE FDO AM NEV OVE LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1815, 'E1.1182', 'GLOSTER CONSORTE FDO AM NEV OVE MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1816, 'E1.1183', 'GLOSTER CONSORTE FDO BRUNO BL MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1817, 'E1.1184', 'GLOSTER CONSORTE FDO BRUNO BL OVE LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1818, 'E1.1185', 'GLOSTER CONSORTE FDO BRUNO BL OVE MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1819, 'E1.1186', 'GLOSTER CONSORTE FDO BRUNO AM INT MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1820, 'E1.1187', 'GLOSTER CONSORTE FDO BRUNO AM INT OVE LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1821, 'E1.1188', 'GLOSTER CONSORTE FDO BRUNO AM INT OVE MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1822, 'E1.1189', 'GLOSTER CONSORTE FDO BRUNO AM NEV MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1823, 'E1.1190', 'GLOSTER CONSORTE FDO BRUNO AM NEV OVE LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1824, 'E1.1191', 'GLOSTER CONSORTE FDO BRUNO AM NEV OVE MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1825, 'E1.1192', 'GLOSTER CONSORTE FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1826, 'E1.1193', 'GLOSTER CONSORTE FDO OTRAS MUTACIONES AM INT TODOS', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1827, 'E1.1194', 'GLOSTER CONSORTE FDO OTRAS MUTACIONES AM NEV TODOS', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1828, 'E1.1195', 'GLOSTER CORONA FDO BL LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1829, 'E1.1196', 'GLOSTER CORONA FDO BL MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1830, 'E1.1197', 'GLOSTER CORONA FDO BL OVE LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1831, 'E1.1198', 'GLOSTER CORONA FDO BL OVE MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1832, 'E1.1199', 'GLOSTER CORONA FDO AM INT LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1833, 'E1.1200', 'GLOSTER CORONA FDO AM INT MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1834, 'E1.1201', 'GLOSTER CORONA FDO AM INT OVE LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1835, 'E1.1202', 'GLOSTER CORONA FDO AM INT OVE MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1836, 'E1.1203', 'GLOSTER CORONA FDO AM NEV LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1837, 'E1.1204', 'GLOSTER CORONA FDO AM NEV MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1838, 'E1.1205', 'GLOSTER CORONA FDO AM NEV OVE LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1839, 'E1.1206', 'GLOSTER CORONA FDO AM NEV OVE MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1840, 'E1.1207', 'GLOSTER CORONA FDO BRUNO BL MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1841, 'E1.1208', 'GLOSTER CORONA FDO BRUNO BL OVE LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1842, 'E1.1209', 'GLOSTER CORONA FDO BRUNO BL OVE MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1843, 'E1.1210', 'GLOSTER CORONA FDO BRUNO AM INT MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1844, 'E1.1211', 'GLOSTER CORONA FDO BRUNO AM INT OVE LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1845, 'E1.1212', 'GLOSTER CORONA FDO BRUNO AM INT OVE MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1846, 'E1.1213', 'GLOSTER CORONA FDO BRUNO AM NEV MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1847, 'E1.1214', 'GLOSTER CORONA FDO BRUNO AM NEV OVE LIP', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1848, 'E1.1215', 'GLOSTER CORONA FDO BRUNO AM NEV OVE MEL', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1849, 'E1.1216', 'GLOSTER CORONA FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1850, 'E1.1217', 'GLOSTER CORONA FDO OTRAS MUTACIONES AM INT TODOS', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1851, 'E1.1218', 'GLOSTER CORONA FDO OTRAS MUTACIONES AM NEV TODOS', 'CP', 'GLOSTER', DEFAULT);
INSERT INTO public.variedad VALUES (1852, 'E1.1250', 'CREST BRED (SIN CORONA) FDO BL LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1853, 'E1.1251', 'CREST BRED (SIN CORONA) FDO BL MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1854, 'E1.1252', 'CREST BRED (SIN CORONA) FDO BL OVE LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1855, 'E1.1253', 'CREST BRED (SIN CORONA) FDO BL OVE MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1856, 'E1.1254', 'CREST BRED (SIN CORONA) FDO AM INT LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1857, 'E1.1255', 'CREST BRED (SIN CORONA) FDO AM INT MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1858, 'E1.1256', 'CREST BRED (SIN CORONA) FDO AM INT OVE LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1859, 'E1.1257', 'CREST BRED (SIN CORONA) FDO AM INT OVE MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1860, 'E1.1258', 'CREST BRED (SIN CORONA) FDO AM NEV LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1861, 'E1.1259', 'CREST BRED (SIN CORONA) FDO AM NEV MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1862, 'E1.1260', 'CREST BRED (SIN CORONA) FDO AM NEV OVE LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1863, 'E1.1261', 'CREST BRED (SIN CORONA) FDO AM NEV OVE MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1864, 'E1.1262', 'CREST BRED (SIN CORONA) FDO BRUNO BL MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1865, 'E1.1263', 'CREST BRED (SIN CORONA) FDO BRUNO BL OVE LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1866, 'E1.1264', 'CREST BRED (SIN CORONA) FDO BRUNO BL OVE MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1867, 'E1.1265', 'CREST BRED (SIN CORONA) FDO BRUNO AM INT MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1868, 'E1.1266', 'CREST BRED (SIN CORONA) FDO BRUNO AM INT OVE LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1869, 'E1.1267', 'CREST BRED (SIN CORONA) FDO BRUNO AM INT OVE MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1870, 'E1.1268', 'CREST BRED (SIN CORONA) FDO BRUNO AM NEV MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1871, 'E1.1269', 'CREST BRED (SIN CORONA) FDO BRUNO AM NEV OVE LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1872, 'E1.1270', 'CREST BRED (SIN CORONA) FDO BRUNO AM NEV OVE MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1873, 'E1.1271', 'CREST BRED (SIN CORONA) FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1874, 'E1.1272', 'CREST BRED (SIN CORONA) FDO OTRAS MUTACIONES AM INT TODOS', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1875, 'E1.1273', 'CREST BRED (SIN CORONA) FDO OTRAS MUTACIONES AM NEV TODOS', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1876, 'E1.1274', 'CRESTED (CORONA) FDO BL LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1877, 'E1.1275', 'CRESTED (CORONA) FDO BL MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1878, 'E1.1276', 'CRESTED (CORONA) FDO BL OVE LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1879, 'E1.1277', 'CRESTED (CORONA) FDO BL OVE MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1880, 'E1.1278', 'CRESTED (CORONA) FDO AM INT LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1881, 'E1.1279', 'CRESTED (CORONA) FDO AM INT MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1882, 'E1.1280', 'CRESTED (CORONA) FDO AM INT OVE LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1883, 'E1.1281', 'CRESTED (CORONA) FDO AM INT OVE MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1884, 'E1.1282', 'CRESTED (CORONA) FDO AM NEV LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1885, 'E1.1283', 'CRESTED (CORONA) FDO AM NEV MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1886, 'E1.1284', 'CRESTED (CORONA) FDO AM NEV OVE LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1887, 'E1.1285', 'CRESTED (CORONA) FDO AM NEV OVE MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1888, 'E1.1286', 'CRESTED (CORONA) FDO BRUNO BL MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1889, 'E1.1287', 'CRESTED (CORONA) FDO BRUNO BL OVE LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1890, 'E1.1288', 'CRESTED (CORONA) FDO BRUNO BL OVE MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1891, 'E1.1289', 'CRESTED (CORONA) FDO BRUNO AM INT MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1892, 'E1.1290', 'CRESTED (CORONA) FDO BRUNO AM INT OVE LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1893, 'E1.1291', 'CRESTED (CORONA) FDO BRUNO AM INT OVE MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1894, 'E1.1292', 'CRESTED (CORONA) FDO BRUNO AM NEV MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1895, 'E1.1293', 'CRESTED (CORONA) FDO BRUNO AM NEV OVE LIP', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1896, 'E1.1294', 'CRESTED (CORONA) FDO BRUNO AM NEV OVE MEL', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1897, 'E1.1295', 'CRESTED (CORONA) FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1898, 'E1.1296', 'CRESTED (CORONA) FDO OTRAS MUTACIONES AM INT TODOS', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1899, 'E1.1297', 'CRESTED (CORONA) FDO OTRAS MUTACIONES AM NEV TODOS', 'CP', 'CREST', DEFAULT);
INSERT INTO public.variedad VALUES (1900, 'E1.1331', 'RASMI PERSA FDO BL LIP', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1901, 'E1.1332', 'RASMI PERSA FDO BL MEL', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1902, 'E1.1333', 'RASMI PERSA FDO BL OVE LIP', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1903, 'E1.1334', 'RASMI PERSA FDO BL OVE MEL', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1904, 'E1.1335', 'RASMI PERSA FDO AM INT LIP', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1905, 'E1.1336', 'RASMI PERSA FDO AM INT MEL', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1906, 'E1.1337', 'RASMI PERSA FDO AM INT OVE LIP', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1907, 'E1.1338', 'RASMI PERSA FDO AM INT OVE MEL', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1908, 'E1.1339', 'RASMI PERSA FDO AM NEV LIP', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1909, 'E1.1340', 'RASMI PERSA FDO AM NEV MEL', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1910, 'E1.1341', 'RASMI PERSA FDO AM NEV OVE LIP', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1911, 'E1.1342', 'RASMI PERSA FDO AM NEV OVE MEL', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1912, 'E1.1343', 'RASMI PERSA FDO BRUNO BL MEL', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1913, 'E1.1344', 'RASMI PERSA FDO BRUNO BL OVE LIP', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1914, 'E1.1345', 'RASMI PERSA FDO BRUNO BL OVE MEL', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1915, 'E1.1346', 'RASMI PERSA FDO AM BRUNO INT MEL', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1916, 'E1.1347', 'RASMI PERSA FDO BRUNO AM INT OVE LIP', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1917, 'E1.1348', 'RASMI PERSA FDO BRUNO AM INT OVE MEL', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1918, 'E1.1349', 'RASMI PERSA FDO BRUNO AM NEV MEL', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1919, 'E1.1350', 'RASMI PERSA FDO BRUNO AM NEV OVE LIP', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1920, 'E1.1351', 'RASMI PERSA FDO BRUNO AM NEV OVE MEL', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1921, 'E1.1352', 'RASMI PERSA FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1922, 'E1.1353', 'RASMI PERSA FDO OTRAS MUTACIONES AM INT TODOS', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1923, 'E1.1354', 'RASMI PERSA FDO OTRAS MUTACIONES AM NEV TODOS', 'CP', 'RASMI PERSA', DEFAULT);
INSERT INTO public.variedad VALUES (1924, 'E1.1381', 'NORWICH FDO BL LIP', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1925, 'E1.1382', 'NORWICH FDO BL MEL', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1926, 'E1.1383', 'NORWICH FDO BL OVE LIP', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1927, 'E1.1384', 'NORWICH FDO BL OVE MEL', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1928, 'E1.1385', 'NORWICH FDO INT LIP', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1929, 'E1.1386', 'NORWICH FDO INT MEL', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1930, 'E1.1387', 'NORWICH FDO INT OVE LIP', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1931, 'E1.1388', 'NORWICH FDO INT OVE MEL', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1932, 'E1.1389', 'NORWICH FDO NEV LIP', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1933, 'E1.1390', 'NORWICH FDO NEV MEL', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1934, 'E1.1391', 'NORWICH FDO NEV OVE LIP', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1935, 'E1.1392', 'NORWICH FDO NEV OVE MEL', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1936, 'E1.1393', 'NORWICH FDO BRUNO BL MEL', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1937, 'E1.1394', 'NORWICH FDO BRUNO BL OVE LIP', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1938, 'E1.1395', 'NORWICH FDO BRUNO BL OVE MEL', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1939, 'E1.1396', 'NORWICH FDO BRUNO INT MEL', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1940, 'E1.1397', 'NORWICH FDO BRUNO INT OVE LIP', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1941, 'E1.1398', 'NORWICH FDO BRUNO INT OVE MEL', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1942, 'E1.1399', 'NORWICH FDO BRUNO NEV MEL', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1943, 'E1.1400', 'NORWICH FDO BRUNO NEV OVE LIP', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1944, 'E1.1401', 'NORWICH FDO BRUNO NEV OVE MEL', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1945, 'E1.1402', 'NORWICH FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1946, 'E1.1403', 'NORWICH FDO OTRAS MUTACIONES INT TODOS', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1947, 'E1.1404', 'NORWICH FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'NORWICH', DEFAULT);
INSERT INTO public.variedad VALUES (1948, 'E1.1431', 'BORDER FDO BL LIP', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1949, 'E1.1432', 'BORDER FDO BL MEL', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1950, 'E1.1433', 'BORDER FDO BL OVE LIP', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1951, 'E1.1434', 'BORDER FDO BL OVE MEL', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1952, 'E1.1435', 'BORDER FDO AM INT LIP', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1953, 'E1.1436', 'BORDER FDO AM INT MEL', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1954, 'E1.1437', 'BORDER FDO AM INT OVE LIP', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1955, 'E1.1438', 'BORDER FDO AM INT OVE MEL', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1956, 'E1.1439', 'BORDER FDO AM NEV LIP', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1957, 'E1.1440', 'BORDER FDO AM NEV MEL', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1958, 'E1.1441', 'BORDER FDO AM NEV OVE LIP', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1959, 'E1.1442', 'BORDER FDO AM NEV OVE MEL', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1960, 'E1.1443', 'BORDER FDO BRUNO BL MEL', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1961, 'E1.1444', 'BORDER FDO BRUNO BL OVE LIP', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1962, 'E1.1445', 'BORDER FDO BRUNO BL OVE MEL', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1963, 'E1.1446', 'BORDER FDO BRUNO AM INT MEL', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1964, 'E1.1447', 'BORDER FDO BRUNO AM INT OVE LIP', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1965, 'E1.1448', 'BORDER FDO BRUNO AM INT OVE MEL', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1966, 'E1.1449', 'BORDER FDO BRUNO AM NEV MEL', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1967, 'E1.1450', 'BORDER FDO BRUNO AM NEV OVE LIP', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1968, 'E1.1451', 'BORDER FDO BRUNO AM NEV OVE MEL', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1969, 'E1.1452', 'BORDER FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1970, 'E1.1453', 'BORDER FDO OTRAS MUTACIONES AM INT TODOS', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1971, 'E1.1454', 'BORDER FDO OTRAS MUTACIONES AM NEV TODOS', 'CP', 'BORDER', DEFAULT);
INSERT INTO public.variedad VALUES (1972, 'E1.1481', 'FIFE FANCY FDO BL LIP', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1973, 'E1.1482', 'FIFE FANCY FDO BL MEL', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1974, 'E1.1483', 'FIFE FANCY FDO BL OVE LIP', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1975, 'E1.1484', 'FIFE FANCY FDO BL OVE MEL', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1976, 'E1.1485', 'FIFE FANCY FDO AM INT LIP', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1977, 'E1.1486', 'FIFE FANCY FDO AM INT MEL', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1978, 'E1.1487', 'FIFE FANCY FDO AM INT OVE LIP', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1979, 'E1.1488', 'FIFE FANCY FDO AM INT OVE MEL', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1980, 'E1.1489', 'FIFE FANCY FDO AM NEV LIP', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1981, 'E1.1490', 'FIFE FANCY FDO AM NEV MEL', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1982, 'E1.1491', 'FIFE FANCY FDO AM NEV OVE LIP', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1983, 'E1.1492', 'FIFE FANCY FDO AM NEV OVE MEL', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1984, 'E1.1493', 'FIFE FANCY FDO BRUNO BL MEL', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1985, 'E1.1494', 'FIFE FANCY FDO BRUNO BL OVE LIP', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1986, 'E1.1495', 'FIFE FANCY FDO BRUNO BL OVE MEL', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1987, 'E1.1496', 'FIFE FANCY FDO BRUNO AM INT MEL', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1988, 'E1.1497', 'FIFE FANCY FDO BRUNO AM INT OVE LIP', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1989, 'E1.1498', 'FIFE FANCY FDO BRUNO AM INT OVE MEL', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1990, 'E1.1499', 'FIFE FANCY FDO BRUNO AM NEV MEL', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1991, 'E1.1500', 'FIFE FANCY FDO BRUNO AM NEV OVE LIP', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1992, 'E1.1501', 'FIFE FANCY FDO BRUNO AM NEV OVE MEL', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1993, 'E1.1502', 'FIFE FANCY FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1994, 'E1.1503', 'FIFE FANCY FDO OTRAS MUTACIONES AM INT TODOS', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1995, 'E1.1504', 'FIFE FANCY FDO OTRAS MUTACIONES AM NEV TODOS', 'CP', 'FIFE FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (1996, 'E1.1530', 'HOSSO JAPONES FDO BL LIP', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (1997, 'E1.1531', 'HOSSO JAPONES FDO BL MEL', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (1998, 'E1.1532', 'HOSSO JAPONES FDO BL OVE LIP', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (1999, 'E1.1533', 'HOSSO JAPONES FDO BL OVE MEL', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2000, 'E1.1534', 'HOSSO JAPONES FDO INT LIP', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2001, 'E1.1535', 'HOSSO JAPONES FDO INT MEL', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2002, 'E1.1536', 'HOSSO JAPONES FDO INT OVE LIP', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2003, 'E1.1537', 'HOSSO JAPONES FDO INT OVE MEL', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2004, 'E1.1538', 'HOSSO JAPONES FDO NEV LIP', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2005, 'E1.1539', 'HOSSO JAPONES FDO NEV MEL', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2006, 'E1.1540', 'HOSSO JAPONES FDO NEV OVE LIP', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2007, 'E1.1541', 'HOSSO JAPONES FDO NEV OVE MEL', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2008, 'E1.1542', 'HOSSO JAPONES FDO BRUNO BL MEL', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2009, 'E1.1543', 'HOSSO JAPONES FDO BRUNO BL OVE LIP', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2010, 'E1.1544', 'HOSSO JAPONES FDO BRUNO BL OVE MEL', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2011, 'E1.1545', 'HOSSO JAPONES FDO BRUNO INT MEL', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2012, 'E1.1546', 'HOSSO JAPONES FDO BRUNO INT OVE LIP', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2013, 'E1.1547', 'HOSSO JAPONES FDO BRUNO INT OVE MEL', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2014, 'E1.1548', 'HOSSO JAPONES FDO BRUNO NEV MEL', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2015, 'E1.1549', 'HOSSO JAPONES FDO BRUNO NEV OVE LIP', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2016, 'E1.1550', 'HOSSO JAPONES FDO BRUNO NEV OVE MEL', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2017, 'E1.1551', 'HOSSO JAPONES FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2018, 'E1.1552', 'HOSSO JAPONES FDO OTRAS MUTACIONES INT TODOS', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2019, 'E1.1553', 'HOSSO JAPONES FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'HOSSO JAPONÉS', DEFAULT);
INSERT INTO public.variedad VALUES (2020, 'E1.1581', 'RAZA ESPAÑOLA FDO BL LIP', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2021, 'E1.1582', 'RAZA ESPAÑOLA FDO BL MEL', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2022, 'E1.1583', 'RAZA ESPAÑOLA FDO BL OVE LIP', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2023, 'E1.1584', 'RAZA ESPAÑOLA FDO BL OVE MEL', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2024, 'E1.1585', 'RAZA ESPAÑOLA FDO INT LIP', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2025, 'E1.1586', 'RAZA ESPAÑOLA FDO INT MEL', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2026, 'E1.1587', 'RAZA ESPAÑOLA FDO INT OVE LIP', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2027, 'E1.1588', 'RAZA ESPAÑOLA FDO INT OVE MEL', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2028, 'E1.1589', 'RAZA ESPAÑOLA FDO NEV LIP', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2029, 'E1.1590', 'RAZA ESPAÑOLA FDO NEV MEL', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2030, 'E1.1591', 'RAZA ESPAÑOLA FDO NEV OVE LIP', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2031, 'E1.1592', 'RAZA ESPAÑOLA FDO NEV OVE MEL', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2032, 'E1.1593', 'RAZA ESPAÑOLA FDO BRUNO BL MEL', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2033, 'E1.1594', 'RAZA ESPAÑOLA FDO BRUNO BL OVE LIP', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2034, 'E1.1595', 'RAZA ESPAÑOLA FDO BRUNO BL OVE MEL', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2035, 'E1.1596', 'RAZA ESPAÑOLA FDO BRUNO INT MEL', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2036, 'E1.1597', 'RAZA ESPAÑOLA FDO BRUNO INT OVE LIP', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2037, 'E1.1598', 'RAZA ESPAÑOLA FDO BRUNO INT OVE MEL', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2038, 'E1.1599', 'RAZA ESPAÑOLA FDO BRUNO NEV MEL', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2039, 'E1.1600', 'RAZA ESPAÑOLA FDO BRUNO NEV OVE LIP', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2040, 'E1.1601', 'RAZA ESPAÑOLA FDO BRUNO NEV OVE MEL', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2041, 'E1.1602', 'RAZA ESPAÑOLA FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2042, 'E1.1603', 'RAZA ESPAÑOLA FDO OTRAS MUTACIONES INT TODOS', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2043, 'E1.1604', 'RAZA ESPAÑOLA FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'RAZA ESPAÑOLA', DEFAULT);
INSERT INTO public.variedad VALUES (2044, 'E1.1631', 'SCOTCH FANCY FDO BL LIP', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2045, 'E1.1632', 'SCOTCH FANCY FDO BL MEL', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2046, 'E1.1633', 'SCOTCH FANCY FDO BL OVE LIP', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2047, 'E1.1634', 'SCOTCH FANCY FDO BL OVE MEL', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2048, 'E1.1635', 'SCOTCH FANCY FDO AM INT LIP', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2049, 'E1.1636', 'SCOTCH FANCY FDO AM INT MEL', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2050, 'E1.1637', 'SCOTCH FANCY FDO AM INT OVE LIP', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2051, 'E1.1638', 'SCOTCH FANCY FDO AM INT OVE MEL', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2052, 'E1.1639', 'SCOTCH FANCY FDO AM NEV LIP', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2053, 'E1.1640', 'SCOTCH FANCY FDO AM NEV MEL', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2054, 'E1.1641', 'SCOTCH FANCY FDO AM NEV OVE LIP', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2055, 'E1.1642', 'SCOTCH FANCY FDO AM NEV OVE MEL', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2056, 'E1.1643', 'SCOTCH FANCY FDO BRUNO BL MEL', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2057, 'E1.1644', 'SCOTCH FANCY FDO BRUNO BL OVE LIP', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2058, 'E1.1645', 'SCOTCH FANCY FDO BRUNO BL OVE MEL', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2059, 'E1.1646', 'SCOTCH FANCY FDO BRUNO AM INT MEL', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2060, 'E1.1647', 'SCOTCH FANCY FDO BRUNO AM INT OVE LIP', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2061, 'E1.1648', 'SCOTCH FANCY FDO BRUNO AM INT OVE MEL', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2062, 'E1.1649', 'SCOTCH FANCY FDO BRUNO AM NEV MEL', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2063, 'E1.1650', 'SCOTCH FANCY FDO BRUNO AM NEV OVE LIP', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2064, 'E1.1651', 'SCOTCH FANCY FDO BRUNO AM NEV OVE MEL', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2065, 'E1.1652', 'SCOTCH FANCY FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2066, 'E1.1653', 'SCOTCH FANCY FDO OTRAS MUTACIONES AM INT TODOS', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2067, 'E1.1654', 'SCOTCH FANCY FDO OTRAS MUTACIONES AM NEV TODOS', 'CP', 'SCOTCH FANCY', DEFAULT);
INSERT INTO public.variedad VALUES (2068, 'E1.1681', 'BERNOIS FDO BL LIP', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2069, 'E1.1682', 'BERNOIS FDO BL MEL', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2070, 'E1.1683', 'BERNOIS FDO BL OVE LIP', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2071, 'E1.1684', 'BERNOIS FDO BL OVE MEL', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2072, 'E1.1685', 'BERNOIS FDO AM INT LIP', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2073, 'E1.1686', 'BERNOIS FDO AM INT MEL', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2074, 'E1.1687', 'BERNOIS FDO AM INT OVE LIP', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2075, 'E1.1688', 'BERNOIS FDO AM INT OVE MEL', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2076, 'E1.1689', 'BERNOIS FDO AM NEV LIP', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2077, 'E1.1690', 'BERNOIS FDO AM NEV MEL', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2078, 'E1.1691', 'BERNOIS FDO AM NEV OVE LIP', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2079, 'E1.1692', 'BERNOIS FDO AM NEV OVE MEL', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2080, 'E1.1693', 'BERNOIS FDO BRUNO BL MEL', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2081, 'E1.1694', 'BERNOIS FDO BRUNO BL OVE LIP', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2082, 'E1.1695', 'BERNOIS FDO BRUNO BL OVE MEL', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2083, 'E1.1696', 'BERNOIS FDO BRUNO AM INT MEL', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2084, 'E1.1697', 'BERNOIS FDO BRUNO AM INT OVE LIP', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2085, 'E1.1698', 'BERNOIS FDO BRUNO AM INT OVE MEL', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2086, 'E1.1699', 'BERNOIS FDO BRUNO AM NEV MEL', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2087, 'E1.1700', 'BERNOIS FDO BRUNO AM NEV OVE LIP', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2088, 'E1.1701', 'BERNOIS FDO BRUNO AM NEV OVE MEL', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2089, 'E1.1702', 'BERNOIS FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2090, 'E1.1703', 'BERNOIS FDO OTRAS MUTACIONES AM INT TODOS', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2091, 'E1.1704', 'BERNOIS FDO OTRAS MUTACIONES AM NEV TODOS', 'CP', 'BERNOIS', DEFAULT);
INSERT INTO public.variedad VALUES (2092, 'E1.1731', 'BOSSU BELGA FDO BL LIP', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2093, 'E1.1732', 'BOSSU BELGA FDO BL MEL', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2094, 'E1.1733', 'BOSSU BELGA FDO BL OVE LIP', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2095, 'E1.1734', 'BOSSU BELGA FDO BL OVE MEL', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2096, 'E1.1735', 'BOSSU BELGA FDO AM INT LIP', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2097, 'E1.1736', 'BOSSU BELGA FDO AM INT MEL', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2098, 'E1.1737', 'BOSSU BELGA FDO AM INT OVE LIP', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2099, 'E1.1738', 'BOSSU BELGA FDO AM INT OVE MEL', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2100, 'E1.1739', 'BOSSU BELGA FDO AM NEV LIP', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2101, 'E1.1740', 'BOSSU BELGA FDO AM NEV MEL', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2102, 'E1.1741', 'BOSSU BELGA FDO AM NEV OVE LIP', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2103, 'E1.1742', 'BOSSU BELGA FDO AM NEV OVE MEL', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2104, 'E1.1743', 'BOSSU BELGA FDO BRUNO BL MEL', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2105, 'E1.1744', 'BOSSU BELGA FDO BRUNO BL OVE LIP', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2106, 'E1.1745', 'BOSSU BELGA FDO BRUNO BL OVE MEL', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2107, 'E1.1746', 'BOSSU BELGA FDO BRUNO AM INT MEL', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2108, 'E1.1747', 'BOSSU BELGA FDO BRUNO AM INT OVE LIP', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2109, 'E1.1748', 'BOSSU BELGA FDO BRUNO AM INT OVE MEL', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2110, 'E1.1749', 'BOSSU BELGA FDO BRUNO AM NEV MEL', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2111, 'E1.1750', 'BOSSU BELGA FDO BRUNO AM NEV OVE LIP', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2112, 'E1.1751', 'BOSSU BELGA FDO BRUNO AM NEV OVE MEL', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2113, 'E1.1752', 'BOSSU BELGA FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2114, 'E1.1753', 'BOSSU BELGA FDO OTRAS MUTACIONES AM INT TODOS', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2115, 'E1.1754', 'BOSSU BELGA FDO OTRAS MUTACIONES AM NEV TODOS', 'CP', 'BOSSU BELGA', DEFAULT);
INSERT INTO public.variedad VALUES (2116, 'E1.1781', 'LLARGUET ESPAÑOL FDO BL LIP', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2117, 'E1.1782', 'LLARGUET ESPAÑOL FDO BL MEL', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2118, 'E1.1783', 'LLARGUET ESPAÑOL FDO BL OVE LIP', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2119, 'E1.1784', 'LLARGUET ESPAÑOL FDO BL OVE MEL', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2120, 'E1.1785', 'LLARGUET ESPAÑOL FDO INT LIP', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2121, 'E1.1786', 'LLARGUET ESPAÑOL FDO INT MEL', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2122, 'E1.1787', 'LLARGUET ESPAÑOL FDO INT OVE LIP', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2123, 'E1.1788', 'LLARGUET ESPAÑOL FDO INT OVE MEL', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2124, 'E1.1789', 'LLARGUET ESPAÑOL FDO NEV LIP', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2125, 'E1.1790', 'LLARGUET ESPAÑOL FDO NEV MEL', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2126, 'E1.1791', 'LLARGUET ESPAÑOL FDO NEV OVE LIP', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2127, 'E1.1792', 'LLARGUET ESPAÑOL FDO NEV OVE MEL', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2128, 'E1.1793', 'LLARGUET ESPAÑOL FDO BRUNO BL MEL', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2129, 'E1.1794', 'LLARGUET ESPAÑOL FDO BRUNO BL OVE LIP', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2130, 'E1.1795', 'LLARGUET ESPAÑOL FDO BRUNO BL OVE MEL', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2131, 'E1.1796', 'LLARGUET ESPAÑOL FDO BRUNO INT MEL', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2132, 'E1.1797', 'LLARGUET ESPAÑOL FDO BRUNO INT OVE LIP', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2133, 'E1.1798', 'LLARGUET ESPAÑOL FDO BRUNO INT OVE MEL', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2134, 'E1.1799', 'LLARGUET ESPAÑOL FDO BRUNO NEV MEL', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2135, 'E1.1800', 'LLARGUET ESPAÑOL FDO BRUNO NEV OVE LIP', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2136, 'E1.1801', 'LLARGUET ESPAÑOL FDO BRUNO NEV OVE MEL', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2137, 'E1.1802', 'LLARGUET ESPAÑOL FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2138, 'E1.1803', 'LLARGUET ESPAÑOL FDO OTRAS MUTACIONES INT TODOS', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2139, 'E1.1804', 'LLARGUET ESPAÑOL FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'LLARGUET ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2140, 'E1.1831', 'LANCASHIRE CONSORTE FDO BL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2141, 'E1.1832', 'LANCASHIRE CONSORTE FDO BL MEL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2142, 'E1.1833', 'LANCASHIRE CONSORTE FDO BL OVE LIP', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2143, 'E1.1834', 'LANCASHIRE CONSORTE FDO BL OVE MEL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2144, 'E1.1835', 'LANCASHIRE CONSORTE FDO AM INT LIP', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2145, 'E1.1836', 'LANCASHIRE CONSORTE FDO AM INT MEL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2146, 'E1.1837', 'LANCASHIRE CONSORTE FDO AM INT OVE LIP', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2147, 'E1.1838', 'LANCASHIRE CONSORTE FDO AM INT OVE MEL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2148, 'E1.1839', 'LANCASHIRE CONSORTE FDO AM NEV LIP', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2149, 'E1.1840', 'LANCASHIRE CONSORTE FDO AM NEV MEL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2150, 'E1.1841', 'LANCASHIRE CONSORTE FDO AM NEV OVE LIP', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2151, 'E1.1842', 'LANCASHIRE CONSORTE FDO AM NEV OVE MEL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2152, 'E1.1843', 'LANCASHIRE CORONA (COPY) FDO BL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2153, 'E1.1844', 'LANCASHIRE CORONA (COPY) FDO BL MEL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2154, 'E1.1845', 'LANCASHIRE CORONA (COPY) FDO BL OVE LIP', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2155, 'E1.1846', 'LANCASHIRE CORONA (COPY) FDO BL OVE MEL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2156, 'E1.1847', 'LANCASHIRE CORONA (COPY) FDO AM INT LIP', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2157, 'E1.1848', 'LANCASHIRE CORONA (COPY) FDO AM INT MEL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2158, 'E1.1849', 'LANCASHIRE CORONA (COPY) FDO AM INT OVE LIP', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2159, 'E1.1850', 'LANCASHIRE CORONA (COPY) FDO AM INT OVE MEL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2160, 'E1.1851', 'LANCASHIRE CORONA (COPY) FDO AM NEV LIP', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2161, 'E1.1852', 'LANCASHIRE CORONA (COPY) FDO AM NEV MEL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2162, 'E1.1853', 'LANCASHIRE CORONA (COPY) FDO AM NEV OVE LIP', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2163, 'E1.1854', 'LANCASHIRE CORONA (COPY) FDO AM NEV OVE MEL', 'CP', 'LANCASHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2164, 'E1.1871', 'MÜNCHENER FDO BL LIP', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2165, 'E1.1872', 'MÜNCHENER FDO BL MEL', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2166, 'E1.1873', 'MÜNCHENER FDO BL OVE LIP', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2167, 'E1.1874', 'MÜNCHENER FDO BL OVE MEL', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2168, 'E1.1875', 'MÜNCHENER FDO AM INT LIP', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2169, 'E1.1876', 'MÜNCHENER FDO AM INT MEL', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2170, 'E1.1877', 'MÜNCHENER FDO AM INT OVE LIP', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2171, 'E1.1878', 'MÜNCHENER FDO AM INT OVE MEL', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2172, 'E1.1879', 'MÜNCHENER FDO AM NEV LIP', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2173, 'E1.1880', 'MÜNCHENER FDO AM NEV MEL', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2174, 'E1.1881', 'MÜNCHENER FDO AM NEV OVE LIP', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2175, 'E1.1882', 'MÜNCHENER FDO AM NEV OVE MEL', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2176, 'E1.1883', 'MÜNCHENER FDO BRUNO BL MEL', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2177, 'E1.1884', 'MÜNCHENER FDO BRUNO BL OVE LIP', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2178, 'E1.1885', 'MÜNCHENER FDO BRUNO BL OVE MEL', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2179, 'E1.1886', 'MÜNCHENER FDO BRUNO AM INT MEL', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2180, 'E1.1887', 'MÜNCHENER FDO BRUNO AM INT OVE LIP', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2181, 'E1.1888', 'MÜNCHENER FDO BRUNO AM INT OVE MEL', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2182, 'E1.1889', 'MÜNCHENER FDO BRUNO AM NEV MEL', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2183, 'E1.1890', 'MÜNCHENER FDO BRUNO AM NEV OVE LIP', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2184, 'E1.1891', 'MÜNCHENER FDO BRUNO AM NEV OVE MEL', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2185, 'E1.1892', 'MÜNCHENER FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2186, 'E1.1893', 'MÜNCHENER FDO OTRAS MUTACIONES INT TODOS', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2187, 'E1.1894', 'MÜNCHENER FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'MÜNCHENER', DEFAULT);
INSERT INTO public.variedad VALUES (2188, 'E1.1920', 'REHINLÄNDER CONSORTE FDO BL', 'CP', 'REHINLÄNDER', DEFAULT);
INSERT INTO public.variedad VALUES (2189, 'E1.1921', 'REHINLÄNDER CONSORTE FDO INT', 'CP', 'REHINLÄNDER', DEFAULT);
INSERT INTO public.variedad VALUES (2190, 'E1.1922', 'REHINLÄNDER CONSORTE FDO NEV', 'CP', 'REHINLÄNDER', DEFAULT);
INSERT INTO public.variedad VALUES (2191, 'E1.1923', 'REHINLÄNDER CORONA BL', 'CP', 'REHINLÄNDER', DEFAULT);
INSERT INTO public.variedad VALUES (2192, 'E1.1924', 'REHINLÄNDER CORONA INT', 'CP', 'REHINLÄNDER', DEFAULT);
INSERT INTO public.variedad VALUES (2193, 'E1.1925', 'REHINLÄNDER CORONA NEV', 'CP', 'REHINLÄNDER', DEFAULT);
INSERT INTO public.variedad VALUES (2194, 'E1.1951', 'YORKSHIRE FDO BL LIP', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2195, 'E1.1952', 'YORKSHIRE FDO BL MEL', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2196, 'E1.1953', 'YORKSHIRE FDO BL OVE LIP', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2197, 'E1.1954', 'YORKSHIRE FDO BL OVE MEL', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2198, 'E1.1955', 'YORKSHIRE FDO INT LIP', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2199, 'E1.1956', 'YORKSHIRE FDO INT MEL', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2200, 'E1.1957', 'YORKSHIRE FDO INT OVE LIP', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2201, 'E1.1958', 'YORKSHIRE FDO INT OVE MEL', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2202, 'E1.1959', 'YORKSHIRE FDO NEV LIP', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2203, 'E1.1960', 'YORKSHIRE FDO NEV MEL', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2204, 'E1.1961', 'YORKSHIRE FDO NEV OVE LIP', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2205, 'E1.1962', 'YORKSHIRE FDO NEV OVE MEL', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2206, 'E1.1963', 'YORKSHIRE FDO BRUNO BL MEL', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2207, 'E1.1964', 'YORKSHIRE FDO BRUNO BL OVE LIP', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2208, 'E1.1965', 'YORKSHIRE FDO BRUNO BL OVE MEL', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2209, 'E1.1966', 'YORKSHIRE FDO BRUNO INT MEL', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2210, 'E1.1967', 'YORKSHIRE FDO BRUNO INT OVE LIP', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2211, 'E1.1968', 'YORKSHIRE FDO BRUNO INT OVE MEL', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2212, 'E1.1969', 'YORKSHIRE FDO BRUNO NEV MEL', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2213, 'E1.1970', 'YORKSHIRE FDO BRUNO NEV OVE LIP', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2214, 'E1.1971', 'YORKSHIRE FDO BRUNO NEV OVE MEL', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2215, 'E1.1972', 'YORKSHIRE FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2216, 'E1.1973', 'YORKSHIRE FDO OTRAS MUTACIONES INT TODOS', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2217, 'E1.1974', 'YORKSHIRE FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'YORKSHIRE', DEFAULT);
INSERT INTO public.variedad VALUES (2218, 'E1.2001', 'SALENTINO SIN COPETE FDO BL LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2219, 'E1.2002', 'SALENTINO SIN COPETE FDO BL MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2220, 'E1.2003', 'SALENTINO SIN COPETE FDO BL OVE LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2221, 'E1.2004', 'SALENTINO SIN COPETE FDO BL OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2222, 'E1.2005', 'SALENTINO SIN COPETE FDO RO INT LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2223, 'E1.2006', 'SALENTINO SIN COPETE FDO RO INT MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2224, 'E1.2007', 'SALENTINO SIN COPETE FDO RO INT OVE LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2225, 'E1.2008', 'SALENTINO SIN COPETE FDO RO INT OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2226, 'E1.2009', 'SALENTINO SIN COPETE FDO RO NEV LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2227, 'E1.2010', 'SALENTINO SIN COPETE FDO RO NEV MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2228, 'E1.2011', 'SALENTINO SIN COPETE FDO RO NEV OVE LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2229, 'E1.2012', 'SALENTINO SIN COPETE FDO RO NEV OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2230, 'E1.2013', 'SALENTINO SIN COPETE FDO RO NEV OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2231, 'E1.2014', 'SALENTINO SIN COPETE FDO BRUNO BL MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2232, 'E1.2015', 'SALENTINO SIN COPETE FDO BRUNO BL OVE LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2233, 'E1.2016', 'SALENTINO SIN COPETE FDO BRUNO BL OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2234, 'E1.2017', 'SALENTINO SIN COPETE FDO BRUNO RO INT MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2235, 'E1.2018', 'SALENTINO SIN COPETE FDO BRUNO RO INT OVE LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2236, 'E1.2019', 'SALENTINO SIN COPETE FDO BRUNO RO INT OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2237, 'E1.2020', 'SALENTINO SIN COPETE FDO BRUNO RO NEV MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2238, 'E1.2021', 'SALENTINO SIN COPETE FDO BRUNO RO NEV OVE LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2239, 'E1.2022', 'SALENTINO SIN COPETE FDO BRUNO RO NEV OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2240, 'E1.2023', 'SALENTINO SIN COPETE FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2241, 'E1.2024', 'SALENTINO SIN COPETE FDO OTRAS MUTACIONES RO INT TODOS', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2242, 'E1.2025', 'SALENTINO SIN COPETE FDO OTRAS MUTACIONES RO NEV TODOS', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2243, 'E1.2026', 'SALENTINO CON COPETE FDO BL LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2244, 'E1.2027', 'SALENTINO CON COPETE FDO BL MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2245, 'E1.2028', 'SALENTINO CON COPETE FDO BL OVE LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2246, 'E1.2029', 'SALENTINO CON COPETE FDO BL OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2247, 'E1.2030', 'SALENTINO CON COPETE FDO RO INT LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2248, 'E1.2031', 'SALENTINO CON COPETE FDO RO INT MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2249, 'E1.2032', 'SALENTINO CON COPETE FDO RO INT OVE LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2250, 'E1.2033', 'SALENTINO CON COPETE FDO RO INT OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2251, 'E1.2034', 'SALENTINO CON COPETE FDO RO NEV LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2252, 'E1.2035', 'SALENTINO CON COPETE FDO RO NEV MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2253, 'E1.2036', 'SALENTINO CON COPETE FDO RO NEV OVE LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2254, 'E1.2037', 'SALENTINO CON COPETE FDO RO NEV OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2255, 'E1.2038', 'SALENTINO CON COPETE FDO RO NEV OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2256, 'E1.2039', 'SALENTINO CON COPETE FDO BRUNO BL MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2257, 'E1.2040', 'SALENTINO CON COPETE FDO BRUNO BL OVE LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2258, 'E1.2041', 'SALENTINO CON COPETE FDO BRUNO BL OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2259, 'E1.2042', 'SALENTINO CON COPETE FDO BRUNO RO INT MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2260, 'E1.2043', 'SALENTINO CON COPETE FDO BRUNO RO INT OVE LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2261, 'E1.2044', 'SALENTINO CON COPETE FDO BRUNO RO INT OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2262, 'E1.2045', 'SALENTINO CON COPETE FDO BRUNO RO NEV MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2263, 'E1.2046', 'SALENTINO CON COPETE FDO BRUNO RO NEV OVE LIP', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2264, 'E1.2047', 'SALENTINO CON COPETE FDO BRUNO RO NEV OVE MEL', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2265, 'E1.2048', 'SALENTINO CON COPETE FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2266, 'E1.2049', 'SALENTINO CON COPETE FDO OTRAS MUTACIONES RO INT TODOS', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2267, 'E1.2050', 'SALENTINO CON COPETE FDO OTRAS MUTACIONES RO NEV TODOS', 'CP', 'SALENTINO', DEFAULT);
INSERT INTO public.variedad VALUES (2268, 'E1.2101', 'RAZAS EN ESTUDIO - PLUMA LISA', 'CP', 'RAZA EN ESTUDIO - PLUMA LISA', DEFAULT);
INSERT INTO public.variedad VALUES (2269, 'E2.5001', 'GIBBER ITALICUS FDO BL LIP', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2270, 'E2.5002', 'GIBBER ITALICUS FDO BL MEL', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2271, 'E2.5003', 'GIBBER ITALICUS FDO BL OVE LIP', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2272, 'E2.5004', 'GIBBER ITALICUS FDO BL OVE MEL', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2273, 'E2.5005', 'GIBBER ITALICUS FDO INT LIP', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2274, 'E2.5006', 'GIBBER ITALICUS FDO INT MEL', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2275, 'E2.5007', 'GIBBER ITALICUS FDO INT OVE LIP', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2276, 'E2.5008', 'GIBBER ITALICUS FDO INT OVE MEL', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2277, 'E2.5009', 'GIBBER ITALICUS FDO BRUNO BL MEL', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2278, 'E2.5010', 'GIBBER ITALICUS FDO BRUNO BL OVE LIP', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2279, 'E2.5011', 'GIBBER ITALICUS FDO BRUNO BL OVE MEL', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2280, 'E2.5012', 'GIBBER ITALICUS FDO BRUNO INT MEL', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2281, 'E2.5013', 'GIBBER ITALICUS FDO BRUNO INT OVE LIP', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2282, 'E2.5014', 'GIBBER ITALICUS FDO BRUNO INT OVE MEL', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2283, 'E2.5015', 'GIBBER ITALICUS FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2284, 'E2.5016', 'GIBBER ITALICUS FDO OTRAS MUTACIONES INT TODOS', 'CP', 'GIBBER ITALICUS', DEFAULT);
INSERT INTO public.variedad VALUES (2285, 'E2.5051', 'GIBOSO ESPAÑOL FDO BL LIP', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2286, 'E2.5052', 'GIBOSO ESPAÑOL FDO BL MEL', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2287, 'E2.5053', 'GIBOSO ESPAÑOL FDO BL OVE LIP', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2288, 'E2.5054', 'GIBOSO ESPAÑOL FDO BL OVE MEL', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2289, 'E2.5055', 'GIBOSO ESPAÑOL FDO INT LIP', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2290, 'E2.5056', 'GIBOSO ESPAÑOL FDO INT MEL', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2291, 'E2.5057', 'GIBOSO ESPAÑOL FDO INT OVE LIP', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2292, 'E2.5058', 'GIBOSO ESPAÑOL FDO INT OVE MEL', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2293, 'E2.5059', 'GIBOSO ESPAÑOL FDO BRUNO BL MEL', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2294, 'E2.5060', 'GIBOSO ESPAÑOL FDO BRUNO BL OVE LIP', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2295, 'E2.5061', 'GIBOSO ESPAÑOL FDO BRUNO BL OVE MEL', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2296, 'E2.5062', 'GIBOSO ESPAÑOL FDO BRUNO INT MEL', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2297, 'E2.5063', 'GIBOSO ESPAÑOL FDO BRUNO INT OVE LIP', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2298, 'E2.5064', 'GIBOSO ESPAÑOL FDO BRUNO INT OVE MEL', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2299, 'E2.5065', 'GIBOSO ESPAÑOL FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2300, 'E2.5066', 'GIBOSO ESPAÑOL FDO OTRAS MUTACIONES INT TODOS', 'CP', 'GIBOSO ESPAÑOL', DEFAULT);
INSERT INTO public.variedad VALUES (2301, 'E2.5101', 'RIZADO DEL SUR FDO BL LIP', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2302, 'E2.5102', 'RIZADO DEL SUR FDO BL MEL', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2303, 'E2.5103', 'RIZADO DEL SUR FDO BL OVE LIP', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2304, 'E2.5104', 'RIZADO DEL SUR FDO BL OVE MEL', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2305, 'E2.5105', 'RIZADO DEL SUR FDO INT LIP', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2306, 'E2.5106', 'RIZADO DEL SUR FDO INT MEL', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2307, 'E2.5107', 'RIZADO DEL SUR FDO INT OVE LIP', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2308, 'E2.5108', 'RIZADO DEL SUR FDO INT OVE MEL', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2309, 'E2.5109', 'RIZADO DEL SUR FDO NEV LIP', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2310, 'E2.5110', 'RIZADO DEL SUR FDO NEV MEL', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2311, 'E2.5111', 'RIZADO DEL SUR FDO NEV OVE LIP', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2312, 'E2.5112', 'RIZADO DEL SUR FDO NEV OVE MEL', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2313, 'E2.5113', 'RIZADO DEL SUR FDO BRUNO BL MEL', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2314, 'E2.5114', 'RIZADO DEL SUR FDO BRUNO BL OVE LIP', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2315, 'E2.5115', 'RIZADO DEL SUR FDO BRUNO BL OVE MEL', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2316, 'E2.5116', 'RIZADO DEL SUR FDO BRUNO INT MEL', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2317, 'E2.5117', 'RIZADO DEL SUR FDO BRUNO INT OVE LIP', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2318, 'E2.5118', 'RIZADO DEL SUR FDO BRUNO INT OVE MEL', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2319, 'E2.5119', 'RIZADO DEL SUR FDO BRUNO NEV MEL', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2320, 'E2.5120', 'RIZADO DEL SUR FDO BRUNO NEV OVE LIP', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2321, 'E2.5121', 'RIZADO DEL SUR FDO BRUNO NEV OVE MEL', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2322, 'E2.5122', 'RIZADO DEL SUR FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2323, 'E2.5123', 'RIZADO DEL SUR FDO OTRAS MUTACIONES INT TODOS', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2324, 'E2.5124', 'RIZADO DEL SUR FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'RIZADO DEL SUR', DEFAULT);
INSERT INTO public.variedad VALUES (2325, 'E2.5151', 'RIZADO SUIZO FDO BL LIP', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2326, 'E2.5152', 'RIZADO SUIZO FDO BL MEL', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2327, 'E2.5153', 'RIZADO SUIZO FDO BL OVE LIP', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2328, 'E2.5154', 'RIZADO SUIZO FDO BL OVE MEL', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2329, 'E2.5155', 'RIZADO SUIZO FDO AM INT LIP', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2330, 'E2.5156', 'RIZADO SUIZO FDO AM INT MEL', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2331, 'E2.5157', 'RIZADO SUIZO FDO AM INT OVE LIP', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2332, 'E2.5158', 'RIZADO SUIZO FDO AM INT OVE MEL', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2333, 'E2.5159', 'RIZADO SUIZO FDO AM NEV LIP', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2334, 'E2.5160', 'RIZADO SUIZO FDO AM NEV MEL', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2335, 'E2.5161', 'RIZADO SUIZO FDO AM NEV OVE LIP', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2336, 'E2.5162', 'RIZADO SUIZO FDO AM NEV OVE MEL', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2337, 'E2.5163', 'RIZADO SUIZO FDO BRUNO BL MEL', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2338, 'E2.5164', 'RIZADO SUIZO FDO BRUNO BL OVE LIP', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2339, 'E2.5165', 'RIZADO SUIZO FDO BRUNO BL OVE MEL', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2340, 'E2.5166', 'RIZADO SUIZO FDO BRUNO AM INT MEL', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2341, 'E2.5167', 'RIZADO SUIZO FDO BRUNO AM INT OVE LIP', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2342, 'E2.5168', 'RIZADO SUIZO FDO BRUNO AM INT OVE MEL', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2343, 'E2.5169', 'RIZADO SUIZO FDO BRUNO AM NEV MEL', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2344, 'E2.5170', 'RIZADO SUIZO FDO BRUNO AM NEV OVE LIP', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2345, 'E2.5171', 'RIZADO SUIZO FDO BRUNO NEV OVE MEL', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2346, 'E2.5172', 'RIZADO SUIZO FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2347, 'E2.5173', 'RIZADO SUIZO FDO OTRAS MUTACIONES INT TODOS', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2348, 'E2.5174', 'RIZADO SUIZO FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'RIZADO SUIZO', DEFAULT);
INSERT INTO public.variedad VALUES (2349, 'E2.5201', 'MELADO TENERIFEÑO FDO BL LIP', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2350, 'E2.5202', 'MELADO TENERIFEÑO FDO BL MEL', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2351, 'E2.5203', 'MELADO TENERIFEÑO FDO BL OVE LIP', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2352, 'E2.5204', 'MELADO TENERIFEÑO FDO BL OVE MEL', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2353, 'E2.5205', 'MELADO TENERIFEÑO FDO NEV LIP', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2354, 'E2.5206', 'MELADO TENERIFEÑO FDO NEV MEL', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2355, 'E2.5207', 'MELADO TENERIFEÑO FDO NEV OVE LIP', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2356, 'E2.5208', 'MELADO TENERIFEÑO FDO NEV OVE MEL', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2357, 'E2.5209', 'MELADO TENERIFEÑO FDO BRUNO BL MEL', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2358, 'E2.5210', 'MELADO TENERIFEÑO FDO BRUNO BL OVE LIP', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2359, 'E2.5211', 'MELADO TENERIFEÑO FDO BRUNO BL OVE MEL', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2360, 'E2.5212', 'MELADO TENERIFEÑO FDO BRUNO NEV MEL', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2361, 'E2.5213', 'MELADO TENERIFEÑO FDO BRUNO NEV OVE LIP', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2362, 'E2.5214', 'MELADO TENERIFEÑO FDO BRUNO NEV OVE MEL', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2363, 'E2.5215', 'MELADO TENERIFEÑO FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2364, 'E2.5216', 'MELADO TENERIFEÑO FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'MELADO TENERIFEÑO', DEFAULT);
INSERT INTO public.variedad VALUES (2365, 'E2.5251', 'GIRALDILLO SEVILLANO SIN COPETE FDO BL LIP', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2366, 'E2.5252', 'GIRALDILLO SEVILLANO SIN COPETE FDO BL MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2367, 'E2.5253', 'GIRALDILLO SEVILLANO SIN COPETE FDO BL OVE LIP', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2368, 'E2.5254', 'GIRALDILLO SEVILLANO SIN COPETE FDO BL OVE MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2369, 'E2.5255', 'GIRALDILLO SEVILLANO SIN COPETE FDO INT LIP', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2370, 'E2.5256', 'GIRALDILLO SEVILLANO SIN COPETE FDO INT MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2371, 'E2.5257', 'GIRALDILLO SEVILLANO SIN COPETE FDO INT OVE LIP', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2372, 'E2.5258', 'GIRALDILLO SEVILLANO SIN COPETE FDO INT OVE MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2373, 'E2.5259', 'GIRALDILLO SEVILLANO SIN COPETE FDO BRUNO BL MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2374, 'E2.5260', 'GIRALDILLO SEVILLANO SIN COPETE FDO BRUNO BL OVE LIP', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2375, 'E2.5261', 'GIRALDILLO SEVILLANO SIN COPETE FDO BRUNO BL OVE MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2376, 'E2.5262', 'GIRALDILLO SEVILLANO SIN COPETE FDO BRUNO INT MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2377, 'E2.5263', 'GIRALDILLO SEVILLANO SIN COPETE FDO BRUNO INT OVE LIP', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2378, 'E2.5264', 'GIRALDILLO SEVILLANO SIN COPETE FDO BRUNO INT OVE MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2379, 'E2.5265', 'GIRALDILLO SEVILLANO SIN COPETE FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2380, 'E2.5266', 'GIRALDILLO SEVILLANO SIN COPETE FDO OTRAS MUTACIONES INT TODOS', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2381, 'E2.5267', 'GIRALDILLO SEVILLANO CON COPETE FDO BL LIP', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2382, 'E2.5268', 'GIRALDILLO SEVILLANO CON COPETE FDO BL MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2383, 'E2.5269', 'GIRALDILLO SEVILLANO CON COPETE FDO BL OVE LIP', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2384, 'E2.5270', 'GIRALDILLO SEVILLANO CON COPETE FDO BL OVE MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2385, 'E2.5271', 'GIRALDILLO SEVILLANO CON COPETE FDO INT LIP', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2386, 'E2.5272', 'GIRALDILLO SEVILLANO CON COPETE FDO INT MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2387, 'E2.5273', 'GIRALDILLO SEVILLANO CON COPETE FDO INT OVE LIP', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2388, 'E2.5274', 'GIRALDILLO SEVILLANO CON COPETE FDO INT OVE MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2389, 'E2.5275', 'GIRALDILLO SEVILLANO CON COPETE FDO BRUNO BL MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2390, 'E2.5276', 'GIRALDILLO SEVILLANO CON COPETE FDO BRUNO BL OVE LIP', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2391, 'E2.5277', 'GIRALDILLO SEVILLANO CON COPETE FDO BRUNO BL OVE MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2392, 'E2.5278', 'GIRALDILLO SEVILLANO CON COPETE FDO BRUNO INT MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2393, 'E2.5279', 'GIRALDILLO SEVILLANO CON COPETE FDO BRUNO INT OVE LIP', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2394, 'E2.5280', 'GIRALDILLO SEVILLANO CON COPETE FDO BRUNO INT OVE MEL', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2395, 'E2.5281', 'GIRALDILLO SEVILLANO CON COPETE FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2396, 'E2.5282', 'GIRALDILLO SEVILLANO CON COPETE FDO OTRAS MUTACIONES INT TODOS', 'CP', 'GIRALDILLO SEVILLANO', DEFAULT);
INSERT INTO public.variedad VALUES (2397, 'E2.5311', 'BENACUS SIN COPETE FDO BL LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2398, 'E2.5312', 'BENACUS SIN COPETE FDO BL MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2399, 'E2.5313', 'BENACUS SIN COPETE FDO BL OVE LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2400, 'E2.5314', 'BENACUS SIN COPETE FDO BL OVE MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2401, 'E2.5315', 'BENACUS SIN COPETE FDO IN LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2402, 'E2.5316', 'BENACUS SIN COPETE FDO INT MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2403, 'E2.5317', 'BENACUS SIN COPETE FDO INT OVE LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2404, 'E2.5318', 'BENACUS SIN COPETE FDO INT OVE MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2405, 'E2.5319', 'BENACUS SIN COPETE FDO NEV LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2406, 'E2.5320', 'BENACUS SIN COPETE FDO NEV MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2407, 'E2.5321', 'BENACUS SIN COPETE FDO NEV OVE LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2408, 'E2.5322', 'BENACUS SIN COPETE FDO NEV OVE MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2409, 'E2.5323', 'BENACUS SIN COPETE FDO BRUNO BL MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2410, 'E2.5324', 'BENACUS SIN COPETE FDO BRUNO BL OVE LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2411, 'E2.5325', 'BENACUS SIN COPETE FDO BRUNO BL OVE MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2412, 'E2.5326', 'BENACUS SIN COPETE FDO BRUNO INT MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2413, 'E2.5327', 'BENACUS SIN COPETE FDO BRUNO INT OVE LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2414, 'E2.5328', 'BENACUS SIN COPETE FDO BRUNO INT OVE MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2415, 'E2.5329', 'BENACUS SIN COPETE FDO BRUNO NEV MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2416, 'E2.5330', 'BENACUS SIN COPETE FDO BRUNO NEV OVE LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2417, 'E2.5331', 'BENACUS SIN COPETE FDO BRUNO NEV OVE MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2418, 'E2.5332', 'BENACUS SIN COPETE FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2419, 'E2.5333', 'BENACUS SIN COPETE FDO OTRAS MUTACIONES INT TODOS', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2420, 'E2.5334', 'BENACUS SIN COPETE FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2421, 'E2.5335', 'BENACUS CON COPETE FDO BL LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2422, 'E2.5336', 'BENACUS CON COPETE FDO BL MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2423, 'E2.5337', 'BENACUS CON COPETE FDO BL OVE LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2424, 'E2.5338', 'BENACUS CON COPETE FDO BL OVE MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2425, 'E2.5339', 'BENACUS CON COPETE FDO INT LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2426, 'E2.5340', 'BENACUS CON COPETE FDO INT MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2427, 'E2.5341', 'BENACUS CON COPETE FDO INT OVE LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2428, 'E2.5342', 'BENACUS CON COPETE FDO INT OVE MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2429, 'E2.5343', 'BENACUS CON COPETE FDO NEV LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2430, 'E2.5344', 'BENACUS CON COPETE FDO NEV MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2431, 'E2.5345', 'BENACUS CON COPETE FDO NEV OVE LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2432, 'E2.5346', 'BENACUS CON COPETE FDO NEV OVE MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2433, 'E2.5347', 'BENACUS CON COPETE FDO BRUNO BL MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2434, 'E2.5348', 'BENACUS CON COPETE FDO BRUNO BL OVE LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2435, 'E2.5349', 'BENACUS CON COPETE FDO BRUNO BL OVE MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2436, 'E2.5350', 'BENACUS CON COPETE FDO BRUNO INT MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2437, 'E2.5351', 'BENACUS CON COPETE FDO BRUNO INT OVE LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2438, 'E2.5352', 'BENACUS CON COPETE FDO BRUNO INT OVE MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2439, 'E2.5353', 'BENACUS CON COPETE FDO BRUNO NEV MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2440, 'E2.5354', 'BENACUS CON COPETE FDO BRUNO NEV OVE LIP', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2441, 'E2.5355', 'BENACUS CON COPETE FDO BRUNO NEV OVE MEL', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2442, 'E2.5356', 'BENACUS CON COPETE FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2443, 'E2.5357', 'BENACUS CON COPETE FDO OTRAS MUTACIONES INT TODOS', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2444, 'E2.5358', 'BENACUS CON COPETE FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'BENACUS', DEFAULT);
INSERT INTO public.variedad VALUES (2445, 'E2.5381', 'RIZADO PARISINO FDO BL LIP', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2446, 'E2.5382', 'RIZADO PARISINO FDO BL MEL', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2447, 'E2.5383', 'RIZADO PARISINO FDO BL OVE LIP', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2448, 'E2.5384', 'RIZADO PARISINO FDO BL OVE MEL', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2449, 'E2.5385', 'RIZADO PARISINO FDO INT LIP', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2450, 'E2.5386', 'RIZADO PARISINO FDO INT MEL', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2451, 'E2.5387', 'RIZADO PARISINO FDO INT OVE LIP', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2452, 'E2.5388', 'RIZADO PARISINO FDO INT OVE MEL', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2453, 'E2.5389', 'RIZADO PARISINO FDO NEV LIP', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2454, 'E2.5390', 'RIZADO PARISINO FDO NEV MEL', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2455, 'E2.5391', 'RIZADO PARISINO FDO NEV OVE LIP', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2456, 'E2.5392', 'RIZADO PARISINO FDO NEV OVE MEL', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2457, 'E2.5393', 'RIZADO PARISINO FDO BRUNO BL MEL', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2458, 'E2.5394', 'RIZADO PARISINO FDO BRUNO BL OVE LIP', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2459, 'E2.5395', 'RIZADO PARISINO FDO BRUNO BL OVE MEL', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2460, 'E2.5396', 'RIZADO PARISINO FDO BRUNO INT MEL', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2461, 'E2.5397', 'RIZADO PARISINO FDO BRUNO INT OVE LIP', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2462, 'E2.5398', 'RIZADO PARISINO FDO BRUNO INT OVE MEL', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2463, 'E2.5399', 'RIZADO PARISINO FDO BRUNO NEV MEL', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2464, 'E2.5400', 'RIZADO PARISINO FDO BRUNO NEV OVE LIP', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2465, 'E2.5401', 'RIZADO PARISINO FDO BRUNO NEV OVE MEL', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2466, 'E2.5402', 'RIZADO PARISINO FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2467, 'E2.5403', 'RIZADO PARISINO FDO OTRAS MUTACIONES INT TODOS', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2468, 'E2.5404', 'RIZADO PARISINO FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'RIZADO PARISINO', DEFAULT);
INSERT INTO public.variedad VALUES (2469, 'E2.5431', 'RIZADO GIGANTE ITALIANO (AGI) FDO BL LIP', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2470, 'E2.5432', 'RIZADO GIGANTE ITALIANO (AGI) FDO BL MEL', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2471, 'E2.5433', 'RIZADO GIGANTE ITALIANO (AGI) FDO BL OVE LIP', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2472, 'E2.5434', 'RIZADO GIGANTE ITALIANO (AGI) FDO BL OVE MEL', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2473, 'E2.5435', 'RIZADO GIGANTE ITALIANO (AGI) FDO INT LIP', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2474, 'E2.5436', 'RIZADO GIGANTE ITALIANO (AGI) FDO INT MEL', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2475, 'E2.5437', 'RIZADO GIGANTE ITALIANO (AGI) FDO INT OVE LIP', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2476, 'E2.5438', 'RIZADO GIGANTE ITALIANO (AGI) FDO INT OVE MEL', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2477, 'E2.5439', 'RIZADO GIGANTE ITALIANO (AGI) FDO NEV LIP', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2478, 'E2.5440', 'RIZADO GIGANTE ITALIANO (AGI) FDO NEV MEL', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2479, 'E2.5441', 'RIZADO GIGANTE ITALIANO (AGI) FDO NEV OVE LIP', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2480, 'E2.5442', 'RIZADO GIGANTE ITALIANO (AGI) FDO NEV OVE MEL', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2481, 'E2.5443', 'RIZADO GIGANTE ITALIANO (AGI) FDO BRUNO INT MEL', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2482, 'E2.5444', 'RIZADO GIGANTE ITALIANO (AGI) FDO BRUNO BL MEL', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2483, 'E2.5445', 'RIZADO GIGANTE ITALIANO (AGI) FDO BRUNO BL OVE LIP', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2484, 'E2.5446', 'RIZADO GIGANTE ITALIANO (AGI) FDO BRUNO BL OVE MEL', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2485, 'E2.5447', 'RIZADO GIGANTE ITALIANO (AGI) FDO BRUNO INT OVE LIP', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2486, 'E2.5448', 'RIZADO GIGANTE ITALIANO (AGI) FDO BRUNO INT OVE MEL', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2487, 'E2.5449', 'RIZADO GIGANTE ITALIANO (AGI) FDO BRUNO NEV MEL', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2488, 'E2.5450', 'RIZADO GIGANTE ITALIANO (AGI) FDO BRUNO NEV OVE LIP', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2489, 'E2.5451', 'RIZADO GIGANTE ITALIANO (AGI) FDO BRUNO NEV OVE MEL', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2490, 'E2.5452', 'RIZADO GIGANTE ITALIANO (AGI) FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2491, 'E2.5453', 'RIZADO GIGANTE ITALIANO (AGI) FDO OTRAS MUTACIONES INT TODOS', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2492, 'E2.5454', 'RIZADO GIGANTE ITALIANO (AGI) FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'RIZADO GIGANTE ITALIANO', DEFAULT);
INSERT INTO public.variedad VALUES (2493, 'E2.5481', 'PADOVANO SIN COPETE FDO BL LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2494, 'E2.5482', 'PADOVANO SIN COPETE FDO BL MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2495, 'E2.5483', 'PADOVANO SIN COPETE FDO BL OVE LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2496, 'E2.5484', 'PADOVANO SIN COPETE FDO BL OVE MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2497, 'E2.5485', 'PADOVANO SIN COPETE FDO INT LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2498, 'E2.5486', 'PADOVANO SIN COPETE FDO INT MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2499, 'E2.5487', 'PADOVANO SIN COPETE FDO INT OVE LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2500, 'E2.5488', 'PADOVANO SIN COPETE FDO INT OVE MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2501, 'E2.5489', 'PADOVANO SIN COPETE FDO NEV LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2502, 'E2.5490', 'PADOVANO SIN COPETE FDO NEV MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2503, 'E2.5491', 'PADOVANO SIN COPETE FDO NEV OVE LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2504, 'E2.5492', 'PADOVANO SIN COPETE FDO NEV OVE MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2505, 'E2.5493', 'PADOVANO SIN COPETE FDO BRUNO BL MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2506, 'E2.5494', 'PADOVANO SIN COPETE FDO BRUNO BL OVE LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2507, 'E2.5495', 'PADOVANO SIN COPETE FDO BRUNO BL OVE MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2508, 'E2.5496', 'PADOVANO SIN COPETE FDO BRUNO INT MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2509, 'E2.5497', 'PADOVANO SIN COPETE FDO BRUNO INT OVE LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2510, 'E2.5498', 'PADOVANO SIN COPETE FDO BRUNO INT OVE MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2511, 'E2.5499', 'PADOVANO SIN COPETE FDO BRUNO NEV MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2512, 'E2.5500', 'PADOVANO SIN COPETE FDO BRUNO NEV OVE LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2513, 'E2.5501', 'PADOVANO SIN COPETE FDO BRUNO NEV OVE MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2514, 'E2.5502', 'PADOVANO SIN COPETE FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2515, 'E2.5503', 'PADOVANO SIN COPETE FDO OTRAS MUTACIONES INT TODOS', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2516, 'E2.5504', 'PADOVANO SIN COPETE FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2517, 'E2.5505', 'PADOVANO CON COPETE FDO BL LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2518, 'E2.5506', 'PADOVANO CON COPETE FDO BL MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2519, 'E2.5507', 'PADOVANO CON COPETE FDO BL OVE LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2520, 'E2.5508', 'PADOVANO CON COPETE FDO BL OVE MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2521, 'E2.5509', 'PADOVANO CON COPETE FDO INT LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2522, 'E2.5510', 'PADOVANO CON COPETE FDO INT MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2523, 'E2.5511', 'PADOVANO CON COPETE FDO INT OVE LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2524, 'E2.5512', 'PADOVANO CON COPETE FDO INT OVE MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2525, 'E2.5513', 'PADOVANO CON COPETE FDO NEV LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2526, 'E2.5514', 'PADOVANO CON COPETE FDO NEV MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2527, 'E2.5515', 'PADOVANO CON COPETE FDO NEV OVE LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2528, 'E2.5516', 'PADOVANO CON COPETE FDO NEV OVE MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2529, 'E2.5517', 'PADOVANO CON COPETE FDO BRUNO BL MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2530, 'E2.5518', 'PADOVANO CON COPETE FDO BRUNO BL OVE LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2531, 'E2.5519', 'PADOVANO CON COPETE FDO BRUNO BL OVE MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2532, 'E2.5520', 'PADOVANO CON COPETE FDO BRUNO INT MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2533, 'E2.5521', 'PADOVANO CON COPETE FDO BRUNO INT OVE LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2534, 'E2.5522', 'PADOVANO CON COPETE FDO BRUNO INT OVE MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2535, 'E2.5523', 'PADOVANO CON COPETE FDO BRUNO NEV MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2536, 'E2.5524', 'PADOVANO CON COPETE FDO BRUNO NEV OVE LIP', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2537, 'E2.5525', 'PADOVANO CON COPETE FDO BRUNO NEV OVE MEL', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2538, 'E2.5526', 'PADOVANO CON COPETE OTRAS MUTACIONES BLANCO TODOS', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2539, 'E2.5527', 'PADOVANO CON COPETE FDO OTRAS MUTACIONES INT TODOS', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2540, 'E2.5528', 'PADOVANO CON COPETE FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'PADOVANO', DEFAULT);
INSERT INTO public.variedad VALUES (2541, 'E2.5551', 'RIZADO DEL NORTE FDO BL LIP', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2542, 'E2.5552', 'RIZADO DEL NORTE FDO BL MEL', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2543, 'E2.5553', 'RIZADO DEL NORTE FDO BL OVE LIP', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2544, 'E2.5554', 'RIZADO DEL NORTE FDO BL OVE MEL', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2545, 'E2.5555', 'RIZADO DEL NORTE FDO INT LIP', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2546, 'E2.5556', 'RIZADO DEL NORTE FDO INT MEL', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2547, 'E2.5557', 'RIZADO DEL NORTE FDO INT OVE LIP', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2548, 'E2.5558', 'RIZADO DEL NORTE FDO INT OVE MEL', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2549, 'E2.5559', 'RIZADO DEL NORTE FDO NEV LIP', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2550, 'E2.5560', 'RIZADO DEL NORTE FDO NEV MEL', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2551, 'E2.5561', 'RIZADO DEL NORTE FDO NEV OVE LIP', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2552, 'E2.5562', 'RIZADO DEL NORTE FDO NEV OVE MEL', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2553, 'E2.5563', 'RIZADO DEL NORTE FDO BRUNO BL MEL', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2554, 'E2.5564', 'RIZADO DEL NORTE FDO BRUNO BL OVE LIP', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2555, 'E2.5565', 'RIZADO DEL NORTE FDO BRUNO BL OVE MEL', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2556, 'E2.5566', 'RIZADO DEL NORTE FDO BRUNO INT MEL', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2557, 'E2.5567', 'RIZADO DEL NORTE FDO BRUNO INT OVE LIP', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2558, 'E2.5568', 'RIZADO DEL NORTE FDO BRUNO INT OVE MEL', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2559, 'E2.5569', 'RIZADO DEL NORTE FDO BRUNO NEV MEL', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2560, 'E2.5570', 'RIZADO DEL NORTE FDO BRUNO NEV OVE LIP', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2561, 'E2.5571', 'RIZADO DEL NORTE FDO BRUNO NEV OVE MEL', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2562, 'E2.5572', 'RIZADO DEL NORTE FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2563, 'E2.5573', 'RIZADO DEL NORTE FDO OTRAS MUTACIONES INT TODOS', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2564, 'E2.5574', 'RIZADO DEL NORTE FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'RIZADO DEL NORTE', DEFAULT);
INSERT INTO public.variedad VALUES (2565, 'E2.5601', 'FIORINO SIN COPETE FDO BL LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2566, 'E2.5602', 'FIORINO SIN COPETE FDO BL MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2567, 'E2.5603', 'FIORINO SIN COPETE FDO BL OVE LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2568, 'E2.5604', 'FIORINO SIN COPETE FDO BL OVE MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2569, 'E2.5605', 'FIORINO SIN COPETE FDO INT LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2570, 'E2.5606', 'FIORINO SIN COPETE FDO INT MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2571, 'E2.5607', 'FIORINO SIN COPETE FDO INT OVE LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2572, 'E2.5608', 'FIORINO SIN COPETE FDO INT OVE MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2573, 'E2.5609', 'FIORINO SIN COPETE FDO NEV LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2574, 'E2.5610', 'FIORINO SIN COPETE FDO NEV MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2575, 'E2.5611', 'FIORINO SIN COPETE FDO NEV OVE LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2576, 'E2.5612', 'FIORINO SIN COPETE FDO NEV OVE MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2577, 'E2.5613', 'FIORINO SIN COPETE FDO BRUNO BL MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2578, 'E2.5614', 'FIORINO SIN COPETE FDO BRUNO BL OVE LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2579, 'E2.5615', 'FIORINO SIN COPETE FDO BRUNO BL OVE MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2580, 'E2.5616', 'FIORINO SIN COPETE FDO BRUNO INT MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2581, 'E2.5617', 'FIORINO SIN COPETE FDO BRUNO INT OVE LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2582, 'E2.5618', 'FIORINO SIN COPETE FDO BRUNO INT OVE MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2583, 'E2.5619', 'FIORINO SIN COPETE FDO BRUNO NEV MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2584, 'E2.5620', 'FIORINO SIN COPETE FDO BRUNO NEV OVE LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2585, 'E2.5621', 'FIORINO SIN COPETE FDO BRUNO NEV OVE MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2586, 'E2.5622', 'FIORINO SIN COPETE OTRAS MUTACIONES BLANCO TODOS', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2587, 'E2.5623', 'FIORINO SIN COPETE FDO OTRAS MUTACIONES INT TODOS', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2588, 'E2.5624', 'FIORINO SIN COPETE FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2589, 'E2.5625', 'FIORINO CON COPETE FDO BL LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2590, 'E2.5626', 'FIORINO CON COPETE FDO BL MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2591, 'E2.5627', 'FIORINO CON COPETE FDO BL OVE LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2592, 'E2.5628', 'FIORINO CON COPETE FDO BL OVE MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2593, 'E2.5629', 'FIORINO CON COPETE FDO INT LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2594, 'E2.5630', 'FIORINO CON COPETE FDO INT MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2595, 'E2.5631', 'FIORINO CON COPETE FDO INT OVE LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2596, 'E2.5632', 'FIORINO CON COPETE FDO INT OVE MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2597, 'E2.5633', 'FIORINO CON COPETE FDO NEV LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2598, 'E2.5634', 'FIORINO CON COPETE FDO NEV MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2599, 'E2.5635', 'FIORINO CON COPETE FDO NEV OVE LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2600, 'E2.5636', 'FIORINO CON COPETE FDO NEV OVE MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2601, 'E2.5637', 'FIORINO CON COPETE FDO BRUNO BL MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2602, 'E2.5638', 'FIORINO CON COPETE FDO BRUNO BL OVE LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2603, 'E2.5639', 'FIORINO CON COPETE FDO BRUNO BL OVE MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2604, 'E2.5640', 'FIORINO CON COPETE FDO BRUNO INT MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2605, 'E2.5641', 'FIORINO CON COPETE FDO BRUNO INT OVE LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2606, 'E2.5642', 'FIORINO CON COPETE FDO BRUNO INT OVE MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2607, 'E2.5643', 'FIORINO CON COPETE FDO BRUNO NEV MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2608, 'E2.5644', 'FIORINO CON COPETE FDO BRUNO NEV OVE LIP', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2609, 'E2.5645', 'FIORINO CON COPETE FDO BRUNO NEV OVE MEL', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2610, 'E2.5646', 'FIORINO CON COPETE OTRAS MUTACIONES BLANCO TODOS', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2611, 'E2.5647', 'FIORINO CON COPETE FDO OTRAS MUTACIONES INT TODOS', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2612, 'E2.5648', 'FIORINO CON COPETE FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'FIORINO', DEFAULT);
INSERT INTO public.variedad VALUES (2613, 'E2.5681', 'MEHRINGER FDO BL LIP', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2614, 'E2.5682', 'MEHRINGER FDO BL MEL', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2615, 'E2.5683', 'MEHRINGER FDO BL OVE LIP', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2616, 'E2.5684', 'MEHRINGER FDO BL OVE MEL', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2617, 'E2.5685', 'MEHRINGER FDO INT LIP', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2618, 'E2.5686', 'MEHRINGER FDO INT MEL', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2619, 'E2.5687', 'MEHRINGER FDO INT OVE LIP', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2620, 'E2.5688', 'MEHRINGER FDO INT OVE MEL', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2621, 'E2.5689', 'MEHRINGER FDO NEV LIP', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2622, 'E2.5690', 'MEHRINGER FDO NEV MEL', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2623, 'E2.5691', 'MEHRINGER FDO NEV OVE LIP', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2624, 'E2.5692', 'MEHRINGER FDO NEV OVE MEL', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2625, 'E2.5693', 'MEHRINGER FDO BRUNO BL MEL', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2626, 'E2.5694', 'MEHRINGER FDO BRUNO BL OVE LIP', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2627, 'E2.5695', 'MEHRINGER FDO BRUNO BL OVE MEL', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2628, 'E2.5696', 'MEHRINGER FDO BRUNO INT MEL', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2629, 'E2.5697', 'MEHRINGER FDO BRUNO INT OVE LIP', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2630, 'E2.5698', 'MEHRINGER FDO BRUNO INT OVE MEL', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2631, 'E2.5699', 'MEHRINGER FDO BRUNO NEV MEL', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2632, 'E2.5700', 'MEHRINGER FDO BRUNO NEV OVE LIP', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2633, 'E2.5701', 'MEHRINGER FDO BRUNO NEV OVE MEL', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2634, 'E2.5702', 'MEHRINGER OTRAS MUTACIONES BLANCO TODOS', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2635, 'E2.5703', 'MEHRINGER FDO OTRAS MUTACIONES INT TODOS', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2636, 'E2.5704', 'MEHRINGER FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'MEHRINGER', DEFAULT);
INSERT INTO public.variedad VALUES (2637, 'E2.5731', 'ROGETTO FDO BL LIP', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2638, 'E2.5732', 'ROGETTO FDO BL MEL', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2639, 'E2.5733', 'ROGETTO FDO BL OVE LIP', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2640, 'E2.5734', 'ROGETTO FDO BL OVE MEL', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2641, 'E2.5735', 'ROGETTO FDO INT LIP', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2642, 'E2.5736', 'ROGETTO FDO INT MEL', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2643, 'E2.5737', 'ROGETTO FDO INT OVE LIP', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2644, 'E2.5738', 'ROGETTO FDO INT OVE MEL', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2645, 'E2.5739', 'ROGETTO FDO NEV LIP', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2646, 'E2.5740', 'ROGETTO FDO NEV MEL', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2647, 'E2.5741', 'ROGETTO FDO NEV OVE LIP', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2648, 'E2.5742', 'ROGETTO FDO NEV OVE MEL', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2649, 'E2.5743', 'ROGETTO FDO BRUNO BL MEL', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2650, 'E2.5744', 'ROGETTO FDO BRUNO BL OVE LIP', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2651, 'E2.5745', 'ROGETTO FDO BRUNO BL OVE MEL', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2652, 'E2.5746', 'ROGETTO FDO BRUNO INT MEL', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2653, 'E2.5747', 'ROGETTO FDO BRUNO INT OVE LIP', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2654, 'E2.5748', 'ROGETTO FDO BRUNO INT OVE MEL', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2655, 'E2.5749', 'ROGETTO FDO BRUNO NEV MEL', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2656, 'E2.5750', 'ROGETTO FDO BRUNO NEV OVE LIP', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2657, 'E2.5751', 'ROGETTO FDO BRUNO NEV OVE MEL', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2658, 'E2.5752', 'ROGETTO FDO OTRAS MUTACIONES BLANCO TODOS', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2659, 'E2.5753', 'ROGETTO FDO OTRAS MUTACIONES INT TODOS', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2660, 'E2.5754', 'ROGETTO FDO OTRAS MUTACIONES NEV TODOS', 'CP', 'ROGETTO', DEFAULT);
INSERT INTO public.variedad VALUES (2661, 'E2.5801', 'RAZAS EN ESTUDIO - PLUMA RIZADA', 'CP', 'RAZA EN ESTUDIO - PLUMA RIZADA', DEFAULT);


--
-- Name: auditoria_id_auditoria_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditoria_id_auditoria_seq', 1, false);


--
-- Name: canario_id_canario_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.canario_id_canario_seq', 1, false);


--
-- Name: club_id_club_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.club_id_club_seq', 4, true);


--
-- Name: cria_id_cria_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.cria_id_cria_seq', 1, false);


--
-- Name: criador_id_criador_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.criador_id_criador_seq', 1, false);


--
-- Name: cruce_id_cruce_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.cruce_id_cruce_seq', 1, false);


--
-- Name: jaula_id_jaula_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.jaula_id_jaula_seq', 1, false);


--
-- Name: modo_operacion_id_modo_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.modo_operacion_id_modo_seq', 1, false);


--
-- Name: mutacion_id_mutacion_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.mutacion_id_mutacion_seq', 7, true);


--
-- Name: nidada_id_nidada_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.nidada_id_nidada_seq', 1, false);


--
-- Name: pareja_id_pareja_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pareja_id_pareja_seq', 1, false);


--
-- Name: respaldo_id_respaldo_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.respaldo_id_respaldo_seq', 1, false);


--
-- Name: simulacion_id_simulacion_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.simulacion_id_simulacion_seq', 1, false);


--
-- Name: simulacion_resultado_id_resultado_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.simulacion_resultado_id_resultado_seq', 1, false);


--
-- Name: solicitud_correccion_id_solicitud_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.solicitud_correccion_id_solicitud_seq', 1, false);


--
-- Name: titulo_id_titulo_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.titulo_id_titulo_seq', 1, false);


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.usuario_id_usuario_seq', 1, false);


--
-- Name: variedad_id_variedad_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.variedad_id_variedad_seq', 2661, true);


--
-- Name: auditoria auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria
    ADD CONSTRAINT auditoria_pkey PRIMARY KEY (id_auditoria);


--
-- Name: canario canario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.canario
    ADD CONSTRAINT canario_pkey PRIMARY KEY (id_canario);


--
-- Name: club club_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club
    ADD CONSTRAINT club_pkey PRIMARY KEY (id_club);


--
-- Name: club club_sigla_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club
    ADD CONSTRAINT club_sigla_key UNIQUE (sigla);


--
-- Name: cria cria_id_canario_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cria
    ADD CONSTRAINT cria_id_canario_key UNIQUE (id_canario);


--
-- Name: cria cria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cria
    ADD CONSTRAINT cria_pkey PRIMARY KEY (id_cria);


--
-- Name: criador criador_id_usuario_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.criador
    ADD CONSTRAINT criador_id_usuario_key UNIQUE (id_usuario);


--
-- Name: criador criador_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.criador
    ADD CONSTRAINT criador_pkey PRIMARY KEY (id_criador);


--
-- Name: cruce cruce_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cruce
    ADD CONSTRAINT cruce_pkey PRIMARY KEY (id_cruce);


--
-- Name: jaula jaula_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jaula
    ADD CONSTRAINT jaula_pkey PRIMARY KEY (id_jaula);


--
-- Name: modo_operacion modo_operacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modo_operacion
    ADD CONSTRAINT modo_operacion_pkey PRIMARY KEY (id_modo);


--
-- Name: mutacion mutacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mutacion
    ADD CONSTRAINT mutacion_pkey PRIMARY KEY (id_mutacion);


--
-- Name: nidada nidada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nidada
    ADD CONSTRAINT nidada_pkey PRIMARY KEY (id_nidada);


--
-- Name: pareja pareja_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pareja
    ADD CONSTRAINT pareja_pkey PRIMARY KEY (id_pareja);


--
-- Name: php_sesion php_sesion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.php_sesion
    ADD CONSTRAINT php_sesion_pkey PRIMARY KEY (id);


--
-- Name: respaldo respaldo_archivo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.respaldo
    ADD CONSTRAINT respaldo_archivo_key UNIQUE (archivo);


--
-- Name: respaldo respaldo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.respaldo
    ADD CONSTRAINT respaldo_pkey PRIMARY KEY (id_respaldo);


--
-- Name: simulacion simulacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulacion
    ADD CONSTRAINT simulacion_pkey PRIMARY KEY (id_simulacion);


--
-- Name: simulacion_resultado simulacion_resultado_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulacion_resultado
    ADD CONSTRAINT simulacion_resultado_pkey PRIMARY KEY (id_resultado);


--
-- Name: solicitud_correccion solicitud_correccion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solicitud_correccion
    ADD CONSTRAINT solicitud_correccion_pkey PRIMARY KEY (id_solicitud);


--
-- Name: titulo titulo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.titulo
    ADD CONSTRAINT titulo_pkey PRIMARY KEY (id_titulo);


--
-- Name: canario uq_canario_criador; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.canario
    ADD CONSTRAINT uq_canario_criador UNIQUE (id_canario, id_criador);


--
-- Name: jaula uq_jaula_criador; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jaula
    ADD CONSTRAINT uq_jaula_criador UNIQUE (id_criador, numero_jaula);


--
-- Name: jaula uq_jaula_id_criador; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jaula
    ADD CONSTRAINT uq_jaula_id_criador UNIQUE (id_jaula, id_criador);


--
-- Name: simulacion_resultado uq_simulacion_resultado; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulacion_resultado
    ADD CONSTRAINT uq_simulacion_resultado UNIQUE NULLS NOT DISTINCT (id_simulacion, sexo_cria, genotipo_resultado);


--
-- Name: titulo uq_titulo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.titulo
    ADD CONSTRAINT uq_titulo UNIQUE (id_canario, nombre, fecha);


--
-- Name: usuario usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_pkey PRIMARY KEY (id_usuario);


--
-- Name: variedad variedad_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variedad
    ADD CONSTRAINT variedad_codigo_key UNIQUE (codigo);


--
-- Name: variedad variedad_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variedad
    ADD CONSTRAINT variedad_pkey PRIMARY KEY (id_variedad);


--
-- Name: idx_auditoria_criador; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_criador ON public.auditoria USING btree (id_criador_solicitante);


--
-- Name: idx_auditoria_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_fecha ON public.auditoria USING btree (fecha_hora);


--
-- Name: idx_auditoria_solicitud; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_solicitud ON public.auditoria USING btree (id_solicitud);


--
-- Name: idx_auditoria_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_usuario ON public.auditoria USING btree (id_usuario);


--
-- Name: idx_canario_club; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_canario_club ON public.canario USING btree (id_club);


--
-- Name: idx_canario_criador; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_canario_criador ON public.canario USING btree (id_criador);


--
-- Name: idx_canario_variedad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_canario_variedad ON public.canario USING btree (id_variedad);


--
-- Name: idx_cria_mutacion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cria_mutacion ON public.cria USING btree (factor_genetico);


--
-- Name: idx_cria_nidada; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cria_nidada ON public.cria USING btree (id_nidada);


--
-- Name: idx_cruce_pareja; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cruce_pareja ON public.cruce USING btree (id_pareja);


--
-- Name: idx_jaula_criador; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jaula_criador ON public.jaula USING btree (id_criador);


--
-- Name: idx_modo_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_modo_usuario ON public.modo_operacion USING btree (id_usuario);


--
-- Name: idx_modo_usuario_cierre; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_modo_usuario_cierre ON public.modo_operacion USING btree (id_usuario_cierre);


--
-- Name: idx_nidada_cruce; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_nidada_cruce ON public.nidada USING btree (id_cruce);


--
-- Name: idx_pareja_criador; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pareja_criador ON public.pareja USING btree (id_criador);


--
-- Name: idx_pareja_hembra; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pareja_hembra ON public.pareja USING btree (id_hembra);


--
-- Name: idx_pareja_jaula; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pareja_jaula ON public.pareja USING btree (id_jaula);


--
-- Name: idx_pareja_macho; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pareja_macho ON public.pareja USING btree (id_macho);


--
-- Name: idx_respaldo_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_respaldo_usuario ON public.respaldo USING btree (id_usuario);


--
-- Name: idx_simulacion_criador; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_simulacion_criador ON public.simulacion USING btree (id_criador);


--
-- Name: idx_simulacion_hembra; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_simulacion_hembra ON public.simulacion USING btree (id_hembra);


--
-- Name: idx_simulacion_macho; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_simulacion_macho ON public.simulacion USING btree (id_macho);


--
-- Name: idx_simulacion_mutacion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_simulacion_mutacion ON public.simulacion USING btree (id_mutacion);


--
-- Name: idx_solicitud_canario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_solicitud_canario ON public.solicitud_correccion USING btree (id_canario);


--
-- Name: idx_solicitud_criador; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_solicitud_criador ON public.solicitud_correccion USING btree (id_criador);


--
-- Name: uq_anillo; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_anillo ON public.canario USING btree (((anillo)::integer), id_club, ((numero_socio)::integer), temporada);


--
-- Name: uq_modo_activo; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_modo_activo ON public.modo_operacion USING btree ((true)) WHERE (fecha_desactivacion IS NULL);


--
-- Name: uq_mutacion_nombre_lower; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_mutacion_nombre_lower ON public.mutacion USING btree (lower((nombre)::text));


--
-- Name: uq_pareja_hembra_activa; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_pareja_hembra_activa ON public.pareja USING btree (id_hembra) WHERE ((estado)::text = 'activa'::text);


--
-- Name: uq_pareja_jaula_activa; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_pareja_jaula_activa ON public.pareja USING btree (id_jaula) WHERE ((estado)::text = 'activa'::text);


--
-- Name: uq_solicitud_pendiente; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_solicitud_pendiente ON public.solicitud_correccion USING btree (id_canario) WHERE ((estado)::text = 'pendiente'::text);


--
-- Name: uq_usuario_correo_lower; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_usuario_correo_lower ON public.usuario USING btree (lower((correo)::text));


--
-- Name: auditoria trg_auditoria_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_auditoria_inmutable BEFORE DELETE OR UPDATE ON public.auditoria FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_inmutable();


--
-- Name: canario trg_canario_criador_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_canario_criador_inmutable BEFORE UPDATE OF id_criador ON public.canario FOR EACH ROW WHEN ((old.id_criador IS DISTINCT FROM new.id_criador)) EXECUTE FUNCTION public.fn_inmutable('id_criador');


--
-- Name: cria trg_cria_canario_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cria_canario_inmutable BEFORE UPDATE OF id_canario ON public.cria FOR EACH ROW WHEN ((old.id_canario IS DISTINCT FROM new.id_canario)) EXECUTE FUNCTION public.fn_inmutable('id_canario');


--
-- Name: cria trg_cria_nidada_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cria_nidada_inmutable BEFORE UPDATE OF id_nidada ON public.cria FOR EACH ROW WHEN ((old.id_nidada IS DISTINCT FROM new.id_nidada)) EXECUTE FUNCTION public.fn_inmutable('id_nidada');


--
-- Name: criador trg_criador_rol; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_criador_rol BEFORE INSERT ON public.criador FOR EACH ROW EXECUTE FUNCTION public.fn_exigir_rol('criador', 'id_usuario');


--
-- Name: criador trg_criador_usuario_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_criador_usuario_inmutable BEFORE UPDATE OF id_usuario ON public.criador FOR EACH ROW WHEN ((old.id_usuario IS DISTINCT FROM new.id_usuario)) EXECUTE FUNCTION public.fn_inmutable('id_usuario');


--
-- Name: cruce trg_cruce_pareja_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cruce_pareja_inmutable BEFORE UPDATE OF id_pareja ON public.cruce FOR EACH ROW WHEN ((old.id_pareja IS DISTINCT FROM new.id_pareja)) EXECUTE FUNCTION public.fn_inmutable('id_pareja');


--
-- Name: pareja trg_estado_pareja; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_estado_pareja BEFORE INSERT OR UPDATE OF estado ON public.pareja FOR EACH ROW EXECUTE FUNCTION public.fn_estado_pareja();


--
-- Name: jaula trg_jaula_criador_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_jaula_criador_inmutable BEFORE UPDATE OF id_criador ON public.jaula FOR EACH ROW WHEN ((old.id_criador IS DISTINCT FROM new.id_criador)) EXECUTE FUNCTION public.fn_inmutable('id_criador');


--
-- Name: variedad trg_marcar_revision; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_marcar_revision AFTER UPDATE OF nombre ON public.variedad FOR EACH ROW EXECUTE FUNCTION public.fn_marcar_revision();


--
-- Name: modo_operacion trg_modo_rol_activa; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_modo_rol_activa BEFORE INSERT OR UPDATE OF id_usuario ON public.modo_operacion FOR EACH ROW EXECUTE FUNCTION public.fn_exigir_rol('administrador', 'id_usuario');


--
-- Name: modo_operacion trg_modo_rol_cierra; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_modo_rol_cierra BEFORE INSERT OR UPDATE OF id_usuario_cierre ON public.modo_operacion FOR EACH ROW EXECUTE FUNCTION public.fn_exigir_rol('administrador', 'id_usuario_cierre');


--
-- Name: nidada trg_nidada_cruce_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_nidada_cruce_inmutable BEFORE UPDATE OF id_cruce ON public.nidada FOR EACH ROW WHEN ((old.id_cruce IS DISTINCT FROM new.id_cruce)) EXECUTE FUNCTION public.fn_inmutable('id_cruce');


--
-- Name: pareja trg_pareja_criador_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_pareja_criador_inmutable BEFORE UPDATE OF id_criador ON public.pareja FOR EACH ROW WHEN ((old.id_criador IS DISTINCT FROM new.id_criador)) EXECUTE FUNCTION public.fn_inmutable('id_criador');


--
-- Name: respaldo trg_respaldo_rol; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_respaldo_rol BEFORE INSERT OR UPDATE OF id_usuario ON public.respaldo FOR EACH ROW EXECUTE FUNCTION public.fn_exigir_rol('administrador', 'id_usuario');


--
-- Name: titulo trg_titulo_canario_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_titulo_canario_inmutable BEFORE UPDATE OF id_canario ON public.titulo FOR EACH ROW WHEN ((old.id_canario IS DISTINCT FROM new.id_canario)) EXECUTE FUNCTION public.fn_inmutable('id_canario');


--
-- Name: usuario trg_usuario_rol_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_usuario_rol_inmutable BEFORE UPDATE OF rol ON public.usuario FOR EACH ROW WHEN (((old.rol)::text IS DISTINCT FROM (new.rol)::text)) EXECUTE FUNCTION public.fn_inmutable('rol');


--
-- Name: cria trg_validar_baja_cria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER trg_validar_baja_cria AFTER DELETE ON public.cria DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.fn_validar_pendiente_cria();


--
-- Name: criador trg_validar_baja_criador; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER trg_validar_baja_criador AFTER DELETE ON public.criador DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.fn_validar_baja_criador();


--
-- Name: canario trg_validar_cambio_sexo; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_cambio_sexo BEFORE UPDATE OF sexo ON public.canario FOR EACH ROW EXECUTE FUNCTION public.fn_validar_cambio_sexo();


--
-- Name: cria trg_validar_cria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_cria BEFORE INSERT ON public.cria FOR EACH ROW EXECUTE FUNCTION public.fn_validar_cria();


--
-- Name: usuario trg_validar_criadero; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER trg_validar_criadero AFTER INSERT ON public.usuario DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.fn_validar_criadero();


--
-- Name: cruce trg_validar_cruce; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_cruce BEFORE INSERT OR UPDATE OF fecha_cruce ON public.cruce FOR EACH ROW EXECUTE FUNCTION public.fn_validar_cruce();


--
-- Name: nidada trg_validar_nidada; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_nidada BEFORE INSERT OR UPDATE OF fecha_nacimiento ON public.nidada FOR EACH ROW EXECUTE FUNCTION public.fn_validar_nidada();


--
-- Name: pareja trg_validar_pareja; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_pareja BEFORE INSERT OR UPDATE OF id_macho, id_hembra, id_jaula, estado ON public.pareja FOR EACH ROW EXECUTE FUNCTION public.fn_validar_pareja();


--
-- Name: canario trg_validar_pendiente_cria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER trg_validar_pendiente_cria AFTER INSERT OR UPDATE OF sexo, id_variedad ON public.canario DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.fn_validar_pendiente_cria();


--
-- Name: canario trg_validar_sexo_variedad; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_sexo_variedad BEFORE INSERT OR UPDATE OF sexo, id_variedad, requiere_revision ON public.canario FOR EACH ROW EXECUTE FUNCTION public.fn_validar_sexo_variedad();


--
-- Name: simulacion trg_validar_simulacion; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_simulacion BEFORE INSERT OR UPDATE ON public.simulacion FOR EACH ROW EXECUTE FUNCTION public.fn_validar_simulacion();


--
-- Name: auditoria auditoria_id_criador_solicitante_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria
    ADD CONSTRAINT auditoria_id_criador_solicitante_fkey FOREIGN KEY (id_criador_solicitante) REFERENCES public.criador(id_criador);


--
-- Name: auditoria auditoria_id_solicitud_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria
    ADD CONSTRAINT auditoria_id_solicitud_fkey FOREIGN KEY (id_solicitud) REFERENCES public.solicitud_correccion(id_solicitud);


--
-- Name: auditoria auditoria_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria
    ADD CONSTRAINT auditoria_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: canario canario_id_club_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.canario
    ADD CONSTRAINT canario_id_club_fkey FOREIGN KEY (id_club) REFERENCES public.club(id_club);


--
-- Name: canario canario_id_criador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.canario
    ADD CONSTRAINT canario_id_criador_fkey FOREIGN KEY (id_criador) REFERENCES public.criador(id_criador);


--
-- Name: canario canario_id_variedad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.canario
    ADD CONSTRAINT canario_id_variedad_fkey FOREIGN KEY (id_variedad) REFERENCES public.variedad(id_variedad);


--
-- Name: cria cria_factor_genetico_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cria
    ADD CONSTRAINT cria_factor_genetico_fkey FOREIGN KEY (factor_genetico) REFERENCES public.mutacion(id_mutacion);


--
-- Name: cria cria_id_canario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cria
    ADD CONSTRAINT cria_id_canario_fkey FOREIGN KEY (id_canario) REFERENCES public.canario(id_canario);


--
-- Name: cria cria_id_nidada_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cria
    ADD CONSTRAINT cria_id_nidada_fkey FOREIGN KEY (id_nidada) REFERENCES public.nidada(id_nidada);


--
-- Name: criador criador_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.criador
    ADD CONSTRAINT criador_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: cruce cruce_id_pareja_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cruce
    ADD CONSTRAINT cruce_id_pareja_fkey FOREIGN KEY (id_pareja) REFERENCES public.pareja(id_pareja);


--
-- Name: pareja fk_pareja_hembra; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pareja
    ADD CONSTRAINT fk_pareja_hembra FOREIGN KEY (id_hembra, id_criador) REFERENCES public.canario(id_canario, id_criador);


--
-- Name: pareja fk_pareja_jaula; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pareja
    ADD CONSTRAINT fk_pareja_jaula FOREIGN KEY (id_jaula, id_criador) REFERENCES public.jaula(id_jaula, id_criador);


--
-- Name: pareja fk_pareja_macho; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pareja
    ADD CONSTRAINT fk_pareja_macho FOREIGN KEY (id_macho, id_criador) REFERENCES public.canario(id_canario, id_criador);


--
-- Name: simulacion fk_simulacion_hembra; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulacion
    ADD CONSTRAINT fk_simulacion_hembra FOREIGN KEY (id_hembra, id_criador) REFERENCES public.canario(id_canario, id_criador);


--
-- Name: simulacion fk_simulacion_macho; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulacion
    ADD CONSTRAINT fk_simulacion_macho FOREIGN KEY (id_macho, id_criador) REFERENCES public.canario(id_canario, id_criador);


--
-- Name: solicitud_correccion fk_solicitud_canario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solicitud_correccion
    ADD CONSTRAINT fk_solicitud_canario FOREIGN KEY (id_canario, id_criador) REFERENCES public.canario(id_canario, id_criador);


--
-- Name: jaula jaula_id_criador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jaula
    ADD CONSTRAINT jaula_id_criador_fkey FOREIGN KEY (id_criador) REFERENCES public.criador(id_criador);


--
-- Name: modo_operacion modo_operacion_id_usuario_cierre_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modo_operacion
    ADD CONSTRAINT modo_operacion_id_usuario_cierre_fkey FOREIGN KEY (id_usuario_cierre) REFERENCES public.usuario(id_usuario);


--
-- Name: modo_operacion modo_operacion_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modo_operacion
    ADD CONSTRAINT modo_operacion_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: nidada nidada_id_cruce_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nidada
    ADD CONSTRAINT nidada_id_cruce_fkey FOREIGN KEY (id_cruce) REFERENCES public.cruce(id_cruce);


--
-- Name: pareja pareja_id_criador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pareja
    ADD CONSTRAINT pareja_id_criador_fkey FOREIGN KEY (id_criador) REFERENCES public.criador(id_criador);


--
-- Name: respaldo respaldo_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.respaldo
    ADD CONSTRAINT respaldo_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: simulacion simulacion_id_criador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulacion
    ADD CONSTRAINT simulacion_id_criador_fkey FOREIGN KEY (id_criador) REFERENCES public.criador(id_criador);


--
-- Name: simulacion simulacion_id_mutacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulacion
    ADD CONSTRAINT simulacion_id_mutacion_fkey FOREIGN KEY (id_mutacion) REFERENCES public.mutacion(id_mutacion);


--
-- Name: simulacion_resultado simulacion_resultado_id_simulacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulacion_resultado
    ADD CONSTRAINT simulacion_resultado_id_simulacion_fkey FOREIGN KEY (id_simulacion) REFERENCES public.simulacion(id_simulacion) ON DELETE CASCADE;


--
-- Name: solicitud_correccion solicitud_correccion_id_criador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solicitud_correccion
    ADD CONSTRAINT solicitud_correccion_id_criador_fkey FOREIGN KEY (id_criador) REFERENCES public.criador(id_criador);


--
-- Name: titulo titulo_id_canario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.titulo
    ADD CONSTRAINT titulo_id_canario_fkey FOREIGN KEY (id_canario) REFERENCES public.canario(id_canario);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO canariapp;


--
-- Name: TABLE auditoria; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT ON TABLE public.auditoria TO canariapp;


--
-- Name: SEQUENCE auditoria_id_auditoria_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.auditoria_id_auditoria_seq TO canariapp;


--
-- Name: TABLE canario; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.canario TO canariapp;


--
-- Name: SEQUENCE canario_id_canario_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.canario_id_canario_seq TO canariapp;


--
-- Name: TABLE club; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.club TO canariapp;


--
-- Name: SEQUENCE club_id_club_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.club_id_club_seq TO canariapp;


--
-- Name: TABLE cria; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.cria TO canariapp;


--
-- Name: SEQUENCE cria_id_cria_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.cria_id_cria_seq TO canariapp;


--
-- Name: TABLE criador; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.criador TO canariapp;


--
-- Name: SEQUENCE criador_id_criador_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.criador_id_criador_seq TO canariapp;


--
-- Name: TABLE cruce; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.cruce TO canariapp;


--
-- Name: SEQUENCE cruce_id_cruce_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.cruce_id_cruce_seq TO canariapp;


--
-- Name: TABLE jaula; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.jaula TO canariapp;


--
-- Name: SEQUENCE jaula_id_jaula_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.jaula_id_jaula_seq TO canariapp;


--
-- Name: TABLE modo_operacion; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.modo_operacion TO canariapp;


--
-- Name: SEQUENCE modo_operacion_id_modo_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.modo_operacion_id_modo_seq TO canariapp;


--
-- Name: TABLE mutacion; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.mutacion TO canariapp;


--
-- Name: SEQUENCE mutacion_id_mutacion_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.mutacion_id_mutacion_seq TO canariapp;


--
-- Name: TABLE nidada; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.nidada TO canariapp;


--
-- Name: SEQUENCE nidada_id_nidada_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.nidada_id_nidada_seq TO canariapp;


--
-- Name: TABLE pareja; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.pareja TO canariapp;


--
-- Name: SEQUENCE pareja_id_pareja_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.pareja_id_pareja_seq TO canariapp;


--
-- Name: TABLE php_sesion; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.php_sesion TO canariapp;


--
-- Name: TABLE respaldo; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE ON TABLE public.respaldo TO canariapp;


--
-- Name: SEQUENCE respaldo_id_respaldo_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.respaldo_id_respaldo_seq TO canariapp;


--
-- Name: TABLE simulacion; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE ON TABLE public.simulacion TO canariapp;


--
-- Name: SEQUENCE simulacion_id_simulacion_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.simulacion_id_simulacion_seq TO canariapp;


--
-- Name: TABLE simulacion_resultado; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE ON TABLE public.simulacion_resultado TO canariapp;


--
-- Name: SEQUENCE simulacion_resultado_id_resultado_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.simulacion_resultado_id_resultado_seq TO canariapp;


--
-- Name: TABLE solicitud_correccion; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.solicitud_correccion TO canariapp;


--
-- Name: SEQUENCE solicitud_correccion_id_solicitud_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.solicitud_correccion_id_solicitud_seq TO canariapp;


--
-- Name: TABLE titulo; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.titulo TO canariapp;


--
-- Name: SEQUENCE titulo_id_titulo_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.titulo_id_titulo_seq TO canariapp;


--
-- Name: TABLE usuario; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.usuario TO canariapp;


--
-- Name: SEQUENCE usuario_id_usuario_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.usuario_id_usuario_seq TO canariapp;


--
-- Name: TABLE v_genealogia; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.v_genealogia TO canariapp;


--
-- Name: TABLE variedad; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.variedad TO canariapp;


--
-- Name: SEQUENCE variedad_id_variedad_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.variedad_id_variedad_seq TO canariapp;


--
-- PostgreSQL database dump complete
--



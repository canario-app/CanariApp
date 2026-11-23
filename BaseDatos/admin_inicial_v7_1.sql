-- =====================================================================
-- CanariApp - Primer usuario administrador (esquema v7.1)
--
-- La base parte sin usuarios y la API no puede crear el primer
-- administrador (las altas de criadores las hace un administrador). Este
-- script lo crea directamente en la base, sin necesitar PHP.
--
-- La contraseña se guarda como hash bcrypt con pgcrypto. PHP la acepta igual
-- que una creada con password_hash(): el login usa password_verify().
-- La contraseña nunca queda escrita en este archivo ni en el repositorio.
--
-- Uso (lo ejecuta el dueño de las tablas, después de canarios_v7_1.sql):
--   psql -d canariapp_db -v nombre='Administrador' -v correo=admin@canariapp.cl -f admin_inicial_v7_1.sql
-- El script pide la contraseña (mínimo 8 caracteres). También se puede
-- pasar con -v clave=..., pero así queda en el historial de la terminal.
--
-- Si ya existe un usuario con ese correo, no cambia nada.
-- =====================================================================

\set ON_ERROR_STOP on

\if :{?correo}
\else
    \echo 'Falta el correo: agregue -v correo=admin@ejemplo.cl'
    DO $$ BEGIN RAISE EXCEPTION 'Falta -v correo=...'; END $$;
\endif

\if :{?nombre}
\else
    \set nombre 'Administrador'
\endif

\if :{?clave}
\else
    \prompt 'Contraseña del administrador (mínimo 8 caracteres): ' clave
\endif

-- Validaciones antes de tocar la base
SELECT length(:'clave') >= 8 AS clave_ok,
       EXISTS (SELECT 1 FROM usuario WHERE lower(correo) = lower(btrim(:'correo'))) AS ya_existe
\gset

\if :clave_ok
\else
    \echo 'La contraseña debe tener al menos 8 caracteres.'
    DO $$ BEGIN RAISE EXCEPTION 'Contraseña demasiado corta'; END $$;
\endif

\if :ya_existe
    \echo 'Ya existe un usuario con ese correo: no se cambió nada.'
    \quit
\endif

BEGIN;

-- pgcrypto es una extensión «trusted» desde PostgreSQL 13: la puede crear el
-- dueño de la base sin ser superusuario.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- El correo se guarda en minúsculas, igual que lo normaliza el backend.
INSERT INTO usuario (nombre, correo, password_hash, rol)
VALUES (btrim(:'nombre'), lower(btrim(:'correo')),
        crypt(:'clave', gen_salt('bf', 10)), 'administrador')
RETURNING id_usuario, nombre, correo, rol;

COMMIT;

\unset clave
\echo 'Administrador creado. Inicie sesión en POST /api/login con ese correo y contraseña.'

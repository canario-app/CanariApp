-- =====================================================================
-- CanariApp - Permisos del rol de la aplicación (SEG-001, SEG-003, DAT-002)
--
-- PHP no debe conectarse como dueño de las tablas. Se conecta con un rol que
-- solo puede hacer lo que la aplicación necesita:
--   * leer, insertar y actualizar los datos;
--   * NO borrar historial (esta versión no elimina registros, sección 1.2);
--   * en auditoria, solo agregar y leer.
--
-- El rol debe existir antes. Lo crea una vez un superusuario, con la
-- contraseña fuera del repositorio:
--   CREATE ROLE canariapp LOGIN PASSWORD '...';
--
-- Uso (lo ejecuta el dueño de las tablas, después de canarios_v7_1.sql):
--   psql -v ON_ERROR_STOP=1 -d canariapp_test -f permisos_v7_1.sql
--   psql -v ON_ERROR_STOP=1 -v rol_app=otro_rol -d canariapp_test -f permisos_v7_1.sql
-- =====================================================================

\if :{?rol_app}
\else
    \set rol_app canariapp
\endif

BEGIN;

REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM :"rol_app";
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM :"rol_app";

GRANT USAGE ON SCHEMA public TO :"rol_app";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :"rol_app";

-- Datos de crianza, cuentas y catálogos: leer, insertar y actualizar
GRANT SELECT, INSERT, UPDATE ON
    usuario, criador, club, variedad, mutacion, jaula, canario, pareja,
    cruce, nidada, cria, titulo, solicitud_correccion, modo_operacion
    TO :"rol_app";

-- Auditoría: solo se agrega y se lee (SEG-003)
GRANT SELECT, INSERT ON auditoria TO :"rol_app";

-- Respaldos: se registran y se retiran de la lista al rotar los 7 más
-- recientes (DAT-003)
GRANT SELECT, INSERT, DELETE ON respaldo TO :"rol_app";

-- Simulaciones guardadas: no son historial de crianza, se pueden borrar
GRANT SELECT, INSERT, DELETE ON simulacion, simulacion_resultado TO :"rol_app";

GRANT SELECT ON v_genealogia TO :"rol_app";

COMMIT;

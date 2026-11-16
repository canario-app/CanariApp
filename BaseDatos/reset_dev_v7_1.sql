-- =====================================================================
-- CanariApp - Reinicio de la base (SOLO DESARROLLO)
--
-- BORRA TODAS LAS TABLAS Y SUS DATOS. Nunca se ejecuta contra la base de
-- pruebas compartida ni contra la final (DAT-002). Uso en su máquina:
--
--   psql -v ON_ERROR_STOP=1 -d canariapp_test -f reset_dev_v7_1.sql
--   psql -v ON_ERROR_STOP=1 -d canariapp_test -f canarios_v7_1.sql
--   psql -v ON_ERROR_STOP=1 -d canariapp_test -f permisos_v7_1.sql
--
-- La lista incluye tablas y funciones de versiones anteriores (v5 y v6) para
-- que una base vieja también quede limpia.
-- =====================================================================

BEGIN;

DROP VIEW IF EXISTS v_genealogia, v_parejas_activas CASCADE;

DROP TABLE IF EXISTS
    simulacion_resultado, simulacion, monitoreo_salud, consumo_alimento,
    cruce_competicion, competicion, alimento, arbol_genealogico, cria,
    nidada, cruce, pareja, titulo, solicitud_correccion, auditoria,
    respaldo, modo_operacion, jaula, canario, color, variedad, club,
    criador, mutacion, usuario CASCADE;

DROP FUNCTION IF EXISTS
    fn_inmutable(), fn_exigir_rol(), fn_validar_criadero(), fn_validar_baja_criador(),
    fn_auditoria_inmutable(), fn_estado_pareja(), fn_validar_pareja(),
    fn_validar_cruce(), fn_validar_nidada(), fn_validar_sexo_variedad(),
    fn_marcar_revision(), fn_validar_cambio_sexo(),
    fn_validar_pendiente_cria(), fn_validar_cria(), fn_validar_solicitud(),
    fn_validar_simulacion() CASCADE;

-- Función auxiliar de pruebas_v7_1.sql
DROP FUNCTION IF EXISTS t(text, boolean, text);
DROP FUNCTION IF EXISTS t(text, text, text);
DROP TABLE IF EXISTS resultado_pruebas;

COMMIT;

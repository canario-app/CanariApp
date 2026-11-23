-- =====================================================================
-- CanariApp v7.1 - Parche: sin límite de parejas activas por macho
--
-- Solo para bases que ya se crearon con una versión anterior de
-- canarios_v7_1.sql (la que rechazaba la 7.ª pareja activa del macho).
-- Reemplaza fn_validar_pareja sin tocar tablas ni datos. Una base nueva,
-- creada con el canarios_v7_1.sql actual, no lo necesita.
--
-- Uso (lo ejecuta el dueño de las tablas):
--   psql -v ON_ERROR_STOP=1 -d canariapp_db -f parche_sin_limite_parejas_v7_1.sql
-- Se puede ejecutar varias veces.
-- =====================================================================

BEGIN;

-- Igual que en canarios_v7_1.sql. La hembra y la jaula siguen admitiendo
-- una sola pareja activa (uq_pareja_hembra_activa, uq_pareja_jaula_activa).
CREATE OR REPLACE FUNCTION fn_validar_pareja() RETURNS trigger AS $$
DECLARE
    v_sexo_m  CHAR(1);
    v_sexo_h  CHAR(1);
BEGIN
    SELECT sexo INTO v_sexo_m FROM canario WHERE id_canario = NEW.id_macho;
    SELECT sexo INTO v_sexo_h FROM canario WHERE id_canario = NEW.id_hembra;

    IF v_sexo_m IS DISTINCT FROM 'M' THEN
        RAISE EXCEPTION 'El ejemplar % no está registrado como macho', NEW.id_macho;
    END IF;
    IF v_sexo_h IS DISTINCT FROM 'H' THEN
        RAISE EXCEPTION 'El ejemplar % no está registrado como hembra', NEW.id_hembra;
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

COMMIT;

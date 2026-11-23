#!/bin/bash
# Inicializa la base de CanariApp con los scripts oficiales de BaseDatos/ (orden del README v7.1).
# Solo corre cuando el volumen está vacío: NUNCA borra datos existentes.
set -Eeuo pipefail
PSQL=(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB")
SQL=/opt/canariapp/sql

echo ">> 1/6 Esquema v7.1"
"${PSQL[@]}" -f "$SQL/canarios_v7_1.sql"

echo ">> 2/6 Rol técnico de la aplicación (sin permiso de borrar historial)"
"${PSQL[@]}" --set=app_pass="$APP_DB_PASSWORD" <<'SQL'
CREATE ROLE canariapp LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'app_pass';
SQL

echo ">> 3/6 Permisos"
"${PSQL[@]}" -f "$SQL/permisos_v7_1.sql"

echo ">> 4/6 Nomenclador 2026 (2.661 variedades)"
"${PSQL[@]}" -f "$SQL/catalogo/seeds/variedad_2026_v7_1.sql"

echo ">> 5/6 Administrador inicial ($ADMIN_EMAIL)"
"${PSQL[@]}" -v correo="$ADMIN_EMAIL" -v clave="$ADMIN_PASSWORD" -v nombre="Administrador" -f "$SQL/admin_inicial_v7_1.sql"

if [ "${SEED_MUTACIONES_PROPUESTA:-0}" = "1" ]; then
  echo ">> 6/6 Mutaciones PROPUESTAS (BaseDatos/catalogo/mutacion.csv, estado=propuesta) solo para demo"
  "${PSQL[@]}" <<'SQL'
INSERT INTO mutacion (nombre, tipo_herencia) VALUES
 ('Pastel','ligada al sexo recesiva'), ('Satiné','ligada al sexo recesiva'),
 ('Opal','autosómica recesiva'), ('Ino','autosómica recesiva'),
 ('Topacio','autosómica recesiva'), ('Eumo','autosómica recesiva'),
 ('Cobalto','autosómica recesiva')
ON CONFLICT DO NOTHING;
SQL
else
  echo ">> 6/6 Mutaciones: no se cargan (pendiente validación del cliente, DAT-006)"
fi
echo ">> Base CanariApp lista"

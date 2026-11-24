#!/bin/sh
# Arranque del contenedor de la API.
#   api-start.sh            -> cron (respaldo cada 2 días) + Apache   (servicio api)
#   api-start.sh respaldo   -> solo cron, sin web                     (servicio respaldo-neon)
set -e

if [ "${1:-web}" = "respaldo" ]; then
  missing=""
  [ -n "$DB_HOST" ] || missing="$missing NEON_DB_HOST"
  [ -n "$DB_PASSWORD" ] || missing="$missing NEON_DB_PASSWORD"
  [ -n "$DB_RESTORE_PASS" ] || missing="$missing NEON_DB_OWNER_PASSWORD"
  [ ${#BACKUP_ENCRYPTION_KEY} -ge 32 ] || missing="$missing BACKUP_ENCRYPTION_KEY(32+)"
  if [ -n "$missing" ]; then
    echo "respaldo-neon: faltan variables en .env:$missing (ver docs/respaldos_neon.md)" >&2
    exit 1
  fi
  case "$DB_HOST" in
    *-pooler*) echo "respaldo-neon: use el host DIRECTO de Neon (sin -pooler); pg_dump no funciona por el pooler." >&2; exit 1 ;;
  esac
fi

mkdir -p /var/www/app/storage/logs /var/www/app/storage/backups
chown -R www-data:www-data /var/www/app/storage
chmod 0750 /var/www/app/storage/backups

# cron no hereda el entorno del contenedor: se guarda en un archivo legible solo por www-data
printenv | grep -E '^(DB_|APP_|TZ=|BACKUP_)' \
  | sed "s/'/'\\\\''/g; s/=\(.*\)/='\1'/; s/^/export /" > /etc/canariapp.env
chown root:www-data /etc/canariapp.env
chmod 0640 /etc/canariapp.env

if [ "${1:-web}" = "respaldo" ]; then
  echo "CanariApp: servicio de respaldo de ${DB_HOST}/${DB_NAME} (cron diario 03:00, respalda si pasaron 48 h)"
  exec cron -f
fi

cron
exec apache2-foreground

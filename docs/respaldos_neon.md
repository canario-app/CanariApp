# Respaldo y restauración de la base de Neon (DAT-003, RF029)

El sitio público corre en **Vercel** con la base en **Neon**. Vercel no tiene `pg_dump` ni un disco
que se conserve entre peticiones, así que los respaldos de Neon los hace un **proceso en Docker**
(servicio `respaldo-neon` de `compose.yaml`) y se **restauran desde ese mismo Docker**.

| Qué | Dónde |
|---|---|
| Respaldo automático cada 2 días | Docker `respaldo-neon` (cron diario a las 03:00; respalda si pasaron 48 h desde el último) |
| Archivos de respaldo (cifrados `.sql.enc`) | Volumen Docker `canariapp_backups_neon` del PC que corre el servicio |
| Registro de cada respaldo | Tabla `respaldo` de Neon (se ve en el panel del administrador en Vercel) |
| Restauración | Desde el Docker `respaldo-neon`, con el sistema en **mantenimiento** o emergencia |
| Retención | 7 respaldos más recientes (los anteriores se borran del volumen y de la tabla) |

## 1. Configurar (una vez)

1. En Neon: proyecto → **Connect**. Desactivar *Connection pooling* para ver el host **directo**
   (sin `-pooler`). `pg_dump` no funciona por el pooler.
2. Revisar la versión del servidor en el SQL Editor de Neon: `SHOW server_version;`.
   La imagen trae `pg_dump` 16, 17 y 18 y usa automáticamente el de la versión del servidor.
   Si Neon fuera 19 o más, agregar `postgresql-client-19` en `docker/php.Dockerfile`.
3. Completar en `.env` (nunca subirlo a GitHub):

   ```ini
   NEON_DB_HOST=ep-xxxxx.us-east-2.aws.neon.tech   # host directo, sin -pooler
   NEON_DB_NAME=neondb
   NEON_DB_USER=canariapp                          # mismo DB_USER de Vercel
   NEON_DB_PASSWORD=...                            # mismo DB_PASSWORD de Vercel
   NEON_DB_OWNER_USER=neondb_owner                 # dueño de las tablas (para restaurar)
   NEON_DB_OWNER_PASSWORD=...
   BACKUP_ENCRYPTION_KEY=...                       # 32+ caracteres (o NEON_BACKUP_ENCRYPTION_KEY aparte)
   ```

4. Levantar el servicio:

   ```sh
   docker compose --profile neon up -d --build respaldo-neon
   ```

   Si falta un dato, el contenedor se detiene y `docker compose logs respaldo-neon` dice cuál.

5. Primer respaldo inmediato (prueba de conexión):

   ```sh
   docker compose --profile neon exec -u www-data respaldo-neon sh -c ". /etc/canariapp.env && php bin/auto_backup.php --force"
   ```

   Debe responder `[OK] Respaldo automático generado: canariapp_auto_backup_...sql.enc`.
   Errores: `docker compose --profile neon exec respaldo-neon cat storage/logs/backup.log`.

## 2. Cifrado

- Cada archivo se cifra con **AES-256-GCM**; la clave se deriva de `BACKUP_ENCRYPTION_KEY`
  (PBKDF2-SHA256, sal aleatoria por archivo). GCM además detecta si el archivo fue alterado.
- El SQL en texto plano solo existe en memoria: nunca queda en disco.
- **Guardar `BACKUP_ENCRYPTION_KEY` fuera del PC** (gestor de contraseñas del equipo). Sin ella los
  respaldos no se pueden restaurar.
- Para revisar un respaldo a mano:
  `php bin/decrypt_backup.php storage/backups/ARCHIVO.sql.enc > revisar.sql` (y borrar `revisar.sql` después).

## 3. Restaurar Neon (RF029)

Desde el sitio en Vercel **no** se puede restaurar (el botón responde que el archivo no está en
el servidor). El procedimiento es:

1. El administrador entra al sitio en Vercel y activa **modo mantenimiento** (los criadores no
   pueden entrar mientras dure).
2. En el PC donde corre el Docker de respaldo, ver los respaldos disponibles:

   ```sh
   docker compose --profile neon exec -u www-data respaldo-neon sh -c ". /etc/canariapp.env && php bin/restore_backup.php"
   ```

3. Restaurar el elegido:

   ```sh
   docker compose --profile neon exec -u www-data respaldo-neon sh -c ". /etc/canariapp.env && php bin/restore_backup.php --id=12 --admin=admin@canariapp.cl --motivo='Recuperación tras incidente'"
   ```

   - Se rechaza si el sistema está en modo normal.
   - Usa el dueño de las tablas (`NEON_DB_OWNER_USER`) y `psql --single-transaction`: si algo
     falla, Neon queda exactamente como estaba. Detalle en `storage/logs/restore.log`.
   - Queda registrada en `auditoria` (acción `restauracion`) a nombre del administrador indicado.
4. Revisar los datos en el sitio y volver a **modo normal** desde el panel (si el respaldo era
   anterior a la activación del mantenimiento, la base restaurada ya vuelve sin modo activo).

## 4. Docker local

El servicio `api` del Docker local hace lo mismo con su propia base (`db`): respaldos cifrados en
el volumen `canariapp_backups` y restauración desde el panel en `http://localhost:8080`.

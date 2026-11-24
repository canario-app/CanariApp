# CanariApp con Docker (BD + API + Frontend)

Levanta el sistema completo tal como está en GitHub: base de datos v7.1 del equipo de BD, backend PHP y frontend PHP (diseño de Figma).

| Servicio | Qué es | Dirección |
|---|---|---|
| `web` | Frontend del equipo (`frontend/`) | http://localhost:8080 |
| `api` | Backend (`backend/`) | http://localhost:8081/api/health |
| `db`  | PostgreSQL 16 con `BaseDatos/` | `localhost:5433` (pgAdmin, solo este PC) |

## Windows

1. Abrir Docker Desktop y esperar «Engine running».
2. Doble clic en `Iniciar_CanariApp.cmd`. La primera vez crea `.env` con claves aleatorias y `ACCESO_LOCAL.txt` con la clave del administrador (`admin@canariapp.cl`).
3. Entrar como administrador y crear criadores en **Criadores**.
4. `Detener_CanariApp.cmd` detiene todo y conserva los datos.

## Linux / macOS

```sh
cp .env.example .env   # cambiar las claves
docker compose up -d --build --wait
```

## Respaldos (DAT-003, RF029)

- La API respalda su base cada 2 días en el volumen `canariapp_backups`, **cifrado** (`.sql.enc`, AES-256-GCM) con `BACKUP_ENCRYPTION_KEY` del `.env`. `Iniciar_CanariApp.cmd` genera esa clave si falta: guárdela fuera del PC.
- La base de **Neon** (Vercel) la respalda el servicio `respaldo-neon`: `docker compose --profile neon up -d --build respaldo-neon`. Configuración y restauración en [`docs/respaldos_neon.md`](docs/respaldos_neon.md).

## Qué hace la base al crearse (solo con volumen vacío)

`docker/db/01-canariapp.sh` ejecuta, en el orden de `BaseDatos/README.md`:
`canarios_v7_1.sql` → rol `canariapp` → `permisos_v7_1.sql` → `catalogo/seeds/variedad_2026_v7_1.sql` (2.661 variedades) → `admin_inicial_v7_1.sql`.
Con `SEED_MUTACIONES_PROPUESTA=1` carga además las 7 mutaciones en estado *propuesta* de `catalogo/mutacion.csv` (solo para demo del simulador; el cliente aún no las valida, DAT-006).

**No ejecutar `docker compose down -v`**: borra el volumen con los datos. Para recrear la base desde cero a propósito, sí se usa `down -v` y luego `up`.

## Verificación (23-11-2026)

- `BaseDatos/pruebas_v7_1.sql`: 136/136 casos OK (en base aparte).
- Recorrido por el frontend: login admin y criador, 18 pantallas, registrar canarios, anillo duplicado rechazado, pareja, cruce, nidada con crías, título, ficha, simulación, finalizar pareja, logout: todo OK.

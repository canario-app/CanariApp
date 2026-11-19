# Guía de inicio rápido: Backend CanariApp

Pasos para levantar la base de datos en local, encender el servidor PHP y probar todos los endpoints documentados en `api.md` sin frontend.

---

## 1. ¿Cómo levanto la base de datos en local?

### Requisitos previos
- Tener instalado **PostgreSQL** junto con **pgAdmin 4**.
- Tener habilitadas las extensiones de PostgreSQL en tu archivo `php.ini` (`extension=pdo_pgsql` y `extension=pgsql`).

### Pasos de configuración
1. **Crear base de datos y propietario:** Abre **pgAdmin 4**, crea la base de datos y el usuario propietario (*owner*) respetando los nombres definidos en `.env.example`.
2. **Crear tablas y permisos:** Haz clic derecho sobre tu base de datos en pgAdmin 4, abre **Query Tool** y ejecuta en orden los scripts SQL del esquema (`canarios_v7_1.sql` y `permisos_v7_1.sql`).
3. **Generar el hash de la contraseña:** Abre la terminal en VS Code y ejecuta el siguiente comando para encriptar la clave del administrador:
   ```bash
   php -r "echo password_hash('Admin1234', PASSWORD_DEFAULT) . PHP_EOL;"
   ```
4. **Registrar el usuario administrador:** Copia el hash generado en el paso anterior, reemplaza `<HASH_GENERADO>` en la siguiente consulta y ejecútala en el **Query Tool** de pgAdmin 4:
   ```sql
   INSERT INTO usuario (nombre, correo, password_hash, rol)
   VALUES ('Administrador', 'admin@canariapp.cl', '<HASH_GENERADO>', 'administrador');
   ```

Con esto ya tienes la base de datos operativa y una cuenta de administrador lista.

---

## 2. ¿Cómo enciendo el servidor?

1. Dentro de la carpeta `backend/`, crea un archivo `.env` copiando el contenido de `.env.example` (ajusta credenciales de BD, `APP_TIMEZONE` y `JWT_EXPIRATION`, que por defecto dura `7200` segundos / 2 horas).
2. Abre una terminal en VS Code y verifica que estés ubicado en `...\Canarios-app\backend`. Si estás en la raíz del proyecto, muévete con:
   ```bash
   cd backend
   ```
3. Regenera el autocargador de clases de Composer:
   ```bash
   composer dump-autoload
   ```
4. Inicia el servidor local de PHP apuntando a la carpeta `public`:
   ```bash
   php -S localhost:8000 -t public
   ```

El backend quedará escuchando en `http://localhost:8000`.

---

## 3. ¿Cómo pruebo la API si no existe frontend?

Puedes usar la extensión **Postmate** directamente dentro de VS Code para enviar peticiones HTTP en formato JSON.

### 1. Probar rutas públicas (sin token)
1. Abre **Postmate** en VS Code y crea un nuevo **HTTP Request**.
2. Prueba el estado del servidor con `GET http://localhost:8000/api/health` o consulta el mapa general en `GET http://localhost:8000/api/v1` y presiona **Send**.
3. En el desplegable izquierdo de la URL puedes cambiar el método HTTP (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`) según el endpoint que vayas a probar.

### 2. Iniciar sesión y obtener el token
1. Cambia el método HTTP de **GET** a **POST** e ingresa la URL:
   ```text
   http://localhost:8000/api/login
   ```
2. Debajo de la URL, abre la pestaña **Body**, selecciona formato **JSON** y envía las credenciales del administrador:
   ```json
   {
     "correo": "admin@canariapp.cl",
     "password": "Admin1234"
   }
   ```
3. Presiona **Send**. La respuesta devolverá `data.token`; cópialo completo (sin comillas).

### 3. Autenticarse en rutas privadas y cerrar sesión
1. En cualquier ruta bajo `/api/v1/...`, abre la pestaña **Auth** (ubicada a la izquierda de **Body**).
2. Cambia **Auth Type** de `No Auth` a **`Bearer Token`** y pega el token copiado.
3. Puedes comprobar los datos de tu sesión activa enviando `GET http://localhost:8000/api/v1/me`.
4. Para cerrar sesión por iniciativa propia, envía `POST http://localhost:8000/api/v1/logout` con el mismo token. El sistema revoca el hash del token en la tabla `auditoria` y cualquier petición posterior con ese token devolverá `401 Unauthorized`.

---

## 4. Referencia rápida de endpoints (`api.md`)

Base URL local: `http://localhost:8000`

| Módulo | Método y ruta | Acceso | Descripción rápida |
|---|---|---|---|
| **Acceso** | `POST /api/login` | Público | Inicia sesión con `correo` y `password`; devuelve el JWT |
| **Sesión** | `GET /api/v1/me` | Autenticado | Devuelve los claims del token activo (`sub`, `correo`, `rol`, `exp`) |
| **Sesión** | `POST /api/v1/logout` | Autenticado | Invalida el token actual en `auditoria` |
| **Perfil** | `GET /api/v1/criador/perfil` | Criador | Consulta los datos del criador autenticado |
| **Perfil** | `PUT /api/v1/criador/perfil` | Criador | Cambia solo su `password` (mín. 8 caracteres; `numero_socio` no es editable) |
| **Admin** | `GET /api/v1/admin/criadores` | Admin | Lista criadores; admite filtro opcional `?buscar=termino` |
| **Admin** | `GET /api/v1/admin/criadores/{id}` | Admin | Muestra el detalle de un criador por `id_criador` |
| **Admin** | `POST /api/v1/admin/criadores` | Admin | Crea usuario + criador (`nombre`, `correo`, `password`, `numero_socio`) |
| **Admin** | `PUT /api/v1/admin/criadores/{id}` | Admin | Actualiza datos o contraseña de un criador |
| **Admin** | `DELETE /api/v1/admin/criadores/{id}` | Admin | Elimina criador (`204`), o devuelve `403`/`409` si la BD lo bloquea |
| **Canarios** | `GET /api/v1/canarios` | Criador / Admin | Lista canarios (criador ve solo los suyos; admin ve todos). Filtros: `buscar`, `id_club`, `id_variedad`, `temporada` |
| **Canarios** | `GET /api/v1/canarios/{id}` | Criador / Admin | Detalle de un ejemplar (criador solo si es suyo) |
| **Canarios** | `POST /api/v1/canarios` | Criador / Admin | Registra un canario adulto (admin debe enviar además `id_criador`) |
| **Canarios** | `PUT` / `PATCH /api/v1/canarios/{id}` | Criador / Admin | Actualiza datos del canario (no permite cambiar `id_criador`) |

### Reglas clave a tener en cuenta al probar
- **Diferencia entre roles:** Si creas un criador desde `/api/v1/admin/criadores` e inicias sesión con su correo en `/api/login`, tendrás acceso restringido a su propio perfil (`/api/v1/criador/perfil`) y a sus propios ejemplares (`/api/v1/canarios`).
- **Formatos esperados:**
  - `anillo`: 1 a 6 dígitos numéricos (único en todo el sistema junto con `id_club`, `numero_socio` y `temporada`).
  - `numero_socio`: 1 a 5 dígitos numéricos.
  - `password`: mínimo 8 caracteres.
  - Fechas de calendario: `YYYY-MM-DD`.
- **Eliminación de registros:** No existe `DELETE /api/v1/canarios/{id}` por regla del SRS 1.2. Al intentar eliminar un criador en `DELETE /api/v1/admin/criadores/{id}`, si tiene registros o historial en `auditoria` asociado, la API responderá `409 Conflict` (o `403 Forbidden` si los permisos de BD lo restringen).
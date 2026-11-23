# Acuerdo de API

Borrador a completar por Frontend y Backend. Si cambia la estructura de los datos, coordinarlo con BD.
La API es la forma en que la pantalla pide y guarda información en el servidor.

Antes de programar, acordar nombres de campos, tipos, obligatorios, fechas y mensajes de error.
Fechas de calendario en `YYYY-MM-DD`; horas y eventos de monitoreo en la zona horaria configurada en `APP_TIMEZONE`.

## Convenciones generales

- Base: `/api/v1` (salvo `GET /api/health` y `POST /api/login`).
- Autenticación: `Authorization: Bearer <token>` en todas las rutas privadas (`/api/v1/...`).
- Cuerpo y respuesta: JSON.
- Formato de éxito:
  ```json
  { "status": "success", "message": "...", "data": { } }
  ```
- Formato de error:
  ```json
  { "status": "error", "message": "...", "errors": { "campo": "mensaje" } }
  ```
- Errores: `400` JSON/ID inválido, `401` sin token o sesión cerrada, `403` sin permiso, `404` no encontrado, `409` conflicto, `422` validación, `500` error interno.

## Acceso y sesión

La autenticación utiliza tokens JWT firmados (`HS256`) cuya duración en segundos se configura mediante `JWT_EXPIRATION` en `.env` (por defecto `7200`). El cierre de sesión revoca el hash SHA-256 del token actual en la tabla inmutable `auditoria`.

### 1. Iniciar sesión

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/login` |
| Quién puede usarla | Pública (cualquier usuario registrado: `criador` o `administrador`) |
| Campos, tipos y obligatoriedad | Obligatorios: `correo` (texto), `password` (texto) |
| Ejemplo de petición | `{"correo": "criador@canariapp.cl", "password": "********"}` |
| Ejemplo de respuesta | `200` con `data` = `{"token": "<jwt>", "user": {"id_usuario": 2, "nombre": "...", "correo": "...", "rol": "criador"}}` |
| Errores esperados | `400` correo o contraseña faltantes, `401` credenciales incorrectas, `500` |
| Reglas de validación | El correo se normaliza a minúsculas antes de consultar |

### 2. Ver sesión actual

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/me` |
| Quién puede usarla | Cualquier usuario autenticado (`criador` o `administrador`) |
| Campos, tipos y obligatoriedad | Sin cuerpo. Requiere cabecera `Authorization: Bearer <token>` |
| Ejemplo de petición | `GET /api/v1/me` |
| Ejemplo de respuesta | `200` con `data` = `{"user": {"jti": "...", "iat": 1700000000, "exp": 1700007200, "sub": 2, "correo": "...", "rol": "criador"}}` |
| Errores esperados | `401` token ausente, expirado, alterado o con sesión cerrada, `500` |
| Reglas de validación | Devuelve los claims decodificados del token JWT activo |

### 3. Cerrar sesión

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/logout` |
| Quién puede usarla | Cualquier usuario autenticado (`criador` o `administrador`) |
| Campos, tipos y obligatoriedad | Sin cuerpo. Requiere cabecera `Authorization: Bearer <token>` |
| Ejemplo de petición | `POST /api/v1/logout` |
| Ejemplo de respuesta | `200` con `data = null` y `message = "Sesión cerrada exitosamente."` |
| Errores esperados | `401` token ausente, inválido, expirado o sesión ya cerrada, `500` |
| Reglas de validación | Invalida de inmediato el token enviado registrando su hash SHA-256 en `auditoria` (`accion = 'logout'`, `entidad = 'sesion'`); no afecta sesiones abiertas en otros dispositivos |

*(Rutas auxiliares públicas disponibles: `GET /api/health` para estado del servicio y `GET /api/v1` para el índice general de endpoints).*

## Perfil del criador

### Objeto `criador`

| Campo | Tipo | Origen |
|---|---|---|
| `id_criador` | entero | `criador.id_criador` |
| `id_usuario` | entero | `criador.id_usuario` / `usuario.id_usuario` |
| `numero_socio` | texto (1–5 dígitos) | `criador.numero_socio` |
| `fecha_creacion` | fecha y hora | `criador.fecha_creacion` |
| `nombre` | texto | `usuario.nombre` |
| `correo` | texto | `usuario.correo` |
| `rol` | `"criador"` | `usuario.rol` |

### 1. Ver perfil propio

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/criador/perfil` |
| Quién puede usarla | Usuario autenticado con perfil en `criador` |
| Campos, tipos y obligatoriedad | Sin cuerpo |
| Ejemplo de petición | `GET /api/v1/criador/perfil` |
| Ejemplo de respuesta | `200` con `data` = objeto `criador` |
| Errores esperados | `401`, `404` usuario sin perfil de criador asociado, `500` |
| Reglas de validación | Toma el `id_usuario` directamente del claim `sub` del token JWT |

### 2. Actualizar contraseña del perfil propio

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT /api/v1/criador/perfil` |
| Quién puede usarla | Usuario autenticado con perfil en `criador` |
| Campos, tipos y obligatoriedad | Obligatorio: `password` (texto, mínimo 8 caracteres) |
| Ejemplo de petición | `{"password": "NuevaPassword123"}` |
| Ejemplo de respuesta | `200` con `data` = objeto `criador` |
| Errores esperados | `400` JSON inválido o intento de enviar `numero_socio`, `401`, `404` sin perfil asociado, `422` contraseña faltante o menor a 8 caracteres, `500` |
| Reglas de validación | El criador solo puede actualizar su contraseña; `numero_socio` no es modificable desde este endpoint |

## Administración de criadores

Todas las rutas bajo `/api/v1/admin/...` requieren autenticación y `rol = "administrador"`.

### 1. Listar criadores

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/criadores` |
| Quién puede usarla | Administrador |
| Campos, tipos y obligatoriedad | Sin cuerpo. Filtro opcional por query string: `buscar` |
| Ejemplo de petición | `GET /api/v1/admin/criadores?buscar=456` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `criador` ordenados del más reciente al más antiguo |
| Errores esperados | `401`, `403` rol distinto a administrador, `500` |
| Reglas de validación | `buscar` filtra por coincidencia parcial (`ILIKE`) en `nombre`, `numero_socio` o `correo` |

### 2. Ver detalle de un criador

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/criadores/{id}` |
| Quién puede usarla | Administrador |
| Campos, tipos y obligatoriedad | `{id}` entero positivo correspondiente a `id_criador` |
| Ejemplo de petición | `GET /api/v1/admin/criadores/5` |
| Ejemplo de respuesta | `200` con `data` = objeto `criador` |
| Errores esperados | `400` ID inválido, `401`, `403`, `404` criador inexistente, `500` |
| Reglas de validación | `{id}` debe ser un entero mayor a `0` |

### 3. Crear criador

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/admin/criadores` *(alias compatible: `POST /api/v1/admin/register`)* |
| Quién puede usarla | Administrador |
| Campos, tipos y obligatoriedad | Obligatorios: `nombre`, `correo`, `password`, `numero_socio` |
| Ejemplo de petición | Ver bloque siguiente |
| Ejemplo de respuesta | `201` con `data` = objeto `criador` creado *(en `/admin/register` devuelve `{"user": {...}}`)* |
| Errores esperados | `400` JSON inválido, `401`, `403`, `409` correo o número de socio duplicado, `422` error de validación, `500` |
| Reglas de validación | Crea usuario con `rol = "criador"` y su fila en `criador` dentro de una misma transacción |

```json
{
  "nombre": "Carlos Mendoza",
  "correo": "carlos.mendoza@canariapp.cl",
  "password": "Password123",
  "numero_socio": "456"
}
```

### 4. Actualizar criador

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT /api/v1/admin/criadores/{id}` |
| Quién puede usarla | Administrador |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_criador`). Opcionales en cuerpo: `nombre`, `correo`, `numero_socio`, `password` (los omitidos conservan su valor) |
| Ejemplo de petición | `{"nombre": "Carlos A. Mendoza", "numero_socio": "457"}` |
| Ejemplo de respuesta | `200` con `data` = objeto `criador` actualizado |
| Errores esperados | `400` ID o JSON inválido, `401`, `403`, `404` criador inexistente, `409` correo o número de socio ocupado por otro registro, `422` validación, `500` |
| Reglas de validación | Si se envía `password` no vacía, debe tener al menos 8 caracteres |

### 5. Eliminar criador

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `DELETE /api/v1/admin/criadores/{id}` |
| Quién puede usarla | Administrador |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_criador`), sin cuerpo |
| Ejemplo de petición | `DELETE /api/v1/admin/criadores/5` |
| Ejemplo de respuesta | `204 No Content` |
| Errores esperados | `400` ID inválido, `401`, `403` política de permisos de BD impide borrar (`SQLSTATE 42501`), `404` criador inexistente, `409` criador con canarios, jaulas, simulaciones o historial de auditoría asociado (`SQLSTATE 23503`), `500` |
| Reglas de validación | Ejecuta el borrado en transacción (`criador` y luego `usuario` por trigger `trg_validar_baja_criador`); si la BD rechaza por privilegios o integridad referencial, devuelve `403` o `409` en lugar de `500` |

## Canario

El ejemplar se identifica por el **anillo completo**: número de anillo (1 a 6 dígitos), sigla del club, número de socio (1 a 5 dígitos) y temporada (año de 4 dígitos). La combinación es única en todo el sistema, sin importar el criadero. La BD compara los números como enteros: `0005` y `5` son el mismo anillo.

En el esquema v7.1 **no existen** `nombre`, `fecha_nacimiento`, `disponibilidad`, `id_color` ni una tabla `color`. La temporada define el año y el color del anillo; no se registra un color por ejemplar.

### Objeto `canario`

| Campo | Tipo | Origen |
|---|---|---|
| `id_canario` | entero | `canario.id_canario` |
| `anillo` | texto (1–6 dígitos) | `canario.anillo` |
| `id_club` | entero | `canario.id_club` |
| `club_sigla` | texto | `club.sigla` |
| `numero_socio` | texto (1–5 dígitos) | `canario.numero_socio` (se ingresa al registrar) |
| `temporada` | entero | `canario.temporada` |
| `sexo` | `"M"` o `"H"` | `canario.sexo` |
| `id_variedad` | entero | `canario.id_variedad` |
| `variedad_nombre` | texto | `variedad.nombre` |
| `id_criador` | entero | `canario.id_criador` |
| `criador_nombre` | texto | `usuario.nombre` |
| `fecha_registro` | fecha y hora | `canario.fecha_registro` |
| `requiere_revision` | booleano | `canario.requiere_revision` (lo calcula la BD) |

`id_canario`, `fecha_registro` y `requiere_revision` **no** se aceptan en el cuerpo. `id_criador` tampoco: se toma del usuario autenticado. El administrador es la excepción: debe indicar `id_criador` al crear un ejemplar, porque no tiene criadero propio.

### 1. Listar canarios

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/canarios` |
| Quién puede usarla | Criador (solo los suyos) y administrador (todos) |
| Campos, tipos y obligatoriedad | Sin cuerpo. Filtros opcionales: `buscar`, `id_club`, `id_variedad`, `temporada` |
| Ejemplo de petición | `GET /api/v1/canarios?buscar=2901&id_club=4&temporada=2026` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `canario` |
| Errores esperados | `401`, `500` |
| Reglas de validación | `buscar` coincide parcialmente con el anillo o el número de socio; filtros vacíos se ignoran |

### 2. Ver detalle de un canario

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/canarios/{id}` |
| Quién puede usarla | Criador dueño del canario y administrador |
| Campos, tipos y obligatoriedad | `{id}` entero positivo |
| Ejemplo de petición | `GET /api/v1/canarios/12` |
| Ejemplo de respuesta | `200` con `data` = objeto `canario` |
| Errores esperados | `400` ID inválido, `401`, `403` canario ajeno, `404` inexistente |
| Reglas de validación | Un criador no puede ver canarios de otro criadero |

### 3. Crear canario

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/canarios` |
| Quién puede usarla | Criador y administrador |
| Campos, tipos y obligatoriedad | Obligatorios: `anillo`, `id_club`, `numero_socio`, `temporada`, `sexo`, `id_variedad`. El administrador además debe enviar `id_criador` |
| Ejemplo de petición | Ver bloque siguiente |
| Ejemplo de respuesta | `201` con `data` = objeto `canario` creado |
| Errores esperados | `400`, `401`, `403`, `409` anillo no disponible, `422` validación o referencia inexistente |
| Reglas de validación | Ver tabla de campos. El sexo debe coincidir con el de la variedad |

```json
{
  "anillo": "2901",
  "id_club": 4,
  "numero_socio": "456",
  "temporada": 2026,
  "sexo": "M",
  "id_variedad": 12
}
```

### 4. Actualizar canario

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT` o `PATCH /api/v1/canarios/{id}` |
| Quién puede usarla | Criador dueño del canario y administrador |
| Campos, tipos y obligatoriedad | Mismos campos que crear; los omitidos conservan su valor |
| Ejemplo de petición | `PATCH /api/v1/canarios/12` con `{"temporada": 2027}` |
| Ejemplo de respuesta | `200` con `data` = objeto `canario` actualizado |
| Errores esperados | `400`, `401`, `403`, `404`, `409`, `422` |
| Reglas de validación | No se puede cambiar `id_criador`. `numero_socio` sí se puede cambiar: es parte del anillo. `anillo`, si viene, no puede quedar vacío |

### 5. Eliminar canario

**No existe.** El SRS 1.2 excluye la eliminación de registros y la BD v7.1 no concede `DELETE` al rol de la aplicación. No se documenta ni se registra la ruta.

## Pareja

Cada pareja asocia un macho (`sexo = 'M'`) y una hembra (`sexo = 'H'`) del mismo criadero con una jaula (`id_jaula`) del mismo criadero. Toda pareja nace en estado `activa` con `fecha_fin = null`; un macho admite hasta 6 parejas activas, mientras que una hembra y una jaula admiten solo una pareja activa a la vez.

`id_pareja` e `id_criador` **no** se aceptan en el cuerpo (el criadero se toma del usuario autenticado). Al crear una pareja tampoco se envían `estado` ni `fecha_fin`.

### Objeto `pareja`

| Campo | Tipo | Origen |
|---|---|---|
| `id_pareja` | entero | `pareja.id_pareja` |
| `id_criador` | entero | `pareja.id_criador` |
| `id_macho` | entero | `pareja.id_macho` |
| `anillo_macho` | texto | `canario.anillo` (macho) |
| `id_hembra` | entero | `pareja.id_hembra` |
| `anillo_hembra` | texto | `canario.anillo` (hembra) |
| `id_jaula` | entero | `pareja.id_jaula` |
| `numero_jaula` | entero | `jaula.numero_jaula` |
| `fecha_formacion` | fecha (`YYYY-MM-DD`) | `pareja.fecha_formacion` |
| `estado` | `"activa"`, `"finalizada"` o `"anulada"` | `pareja.estado` |
| `fecha_fin` | fecha (`YYYY-MM-DD`) o `null` | `pareja.fecha_fin` |

### 1. Listar parejas

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/parejas` |
| Quién puede usarla | Criador autenticado (solo las parejas de su criadero) |
| Campos, tipos y obligatoriedad | Sin cuerpo. Filtros opcionales por query string: `estado`, `id_macho`, `id_hembra`, `id_jaula` |
| Ejemplo de petición | `GET /api/v1/parejas?estado=activa` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `pareja` |
| Errores esperados | `401`, `403` rol distinto a criador, `404` sin perfil de criador asociado, `500` |
| Reglas de validación | Filtra estrictamente por el `id_criador` del usuario autenticado; filtros vacíos o inválidos se ignoran |

### 2. Ver detalle de una pareja

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/parejas/{id}` |
| Quién puede usarla | Criador dueño de la pareja |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_pareja`) |
| Ejemplo de petición | `GET /api/v1/parejas/3` |
| Ejemplo de respuesta | `200` con `data` = objeto `pareja` |
| Errores esperados | `400` ID inválido, `401`, `403` pareja ajena o rol distinto a criador, `404` pareja o perfil inexistente, `500` |
| Reglas de validación | Un criador no puede consultar parejas pertenecientes a otro criadero |

### 3. Crear pareja

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/parejas` |
| Quién puede usarla | Criador autenticado |
| Campos, tipos y obligatoriedad | Obligatorios: `id_macho`, `id_hembra`, `id_jaula`. Opcional: `fecha_formacion` (`YYYY-MM-DD`, por defecto fecha actual) |
| Ejemplo de petición | Ver bloque siguiente |
| Ejemplo de respuesta | `201` con `data` = objeto `pareja` creado en estado `"activa"` |
| Errores esperados | `400` JSON inválido, `401`, `403`, `409` máximo 6 parejas activas por macho, hembra con pareja activa o jaula ocupada, `422` validación o referencia ajena/inexistente, `500` |
| Reglas de validación | Macho (`M`) y hembra (`H`) deben ser distintos, pertenecer al criador y coincidir en criadero con la jaula; `fecha_formacion` no puede ser posterior a la fecha actual |

```json
{
  "id_macho": 10,
  "id_hembra": 14,
  "id_jaula": 2,
  "fecha_formacion": "2026-11-22"
}
```

### 4. Actualizar pareja

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT` o `PATCH /api/v1/parejas/{id}` |
| Quién puede usarla | Criador dueño de la pareja |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_pareja`). Opcionales en cuerpo: `id_jaula`, `estado`, `fecha_fin` |
| Ejemplo de petición | `PATCH /api/v1/parejas/3` con `{"estado": "finalizada"}` |
| Ejemplo de respuesta | `200` con `data` = objeto `pareja` actualizado |
| Errores esperados | `400` ID o JSON inválido, `401`, `403`, `404`, `409` jaula ocupada o restricción de ciclo de vida en BD, `422` validación o referencia inválida, `500` |
| Reglas de validación | `id_criador`, `id_macho` e `id_hembra` no se modifican por este endpoint. Al pasar a `"finalizada"` o `"anulada"` se libera la jaula y se exige `fecha_fin >= fecha_formacion` (si no se envía `fecha_fin`, se asigna la fecha actual). Una pareja cerrada no puede volver a cambiar de estado y una pareja con cruces no puede anularse |

### 5. Eliminar pareja

**No existe.** El SRS 1.2 excluye la eliminación física de registros; las parejas se finalizan o anulan según las reglas del ciclo de vida y la BD v7.1.

## Cruces

Un cruce es el apareamiento fechado de una pareja. Según SRS-RF016 una pareja puede tener **varios cruces**, siempre que esté `activa`. La fecha es obligatoria, se expresa como `YYYY-MM-DD` y no puede ser posterior a la fecha actual. El vínculo con la pareja es inmutable (revisión SQL-01), por lo que no hay `PUT`, `PATCH` ni `DELETE`.

`id_cruce` e `id_criador` **no** se aceptan en el cuerpo. El criadero se toma de la pareja, que debe pertenecer al usuario autenticado.

### Objeto `cruce`

| Campo | Tipo | Origen |
|---|---|---|
| `id_cruce` | entero | `cruce.id_cruce` |
| `id_pareja` | entero | `cruce.id_pareja` |
| `fecha_cruce` | fecha (`YYYY-MM-DD`) | `cruce.fecha_cruce` |
| `id_criador` | entero | `pareja.id_criador` |
| `id_macho` | entero | `pareja.id_macho` |
| `anillo_macho` | texto | `canario.anillo` (macho) |
| `id_hembra` | entero | `pareja.id_hembra` |
| `anillo_hembra` | texto | `canario.anillo` (hembra) |

### 1. Listar cruces

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/cruces` |
| Quién puede usarla | Criador autenticado (solo los cruces de su criadero) |
| Campos, tipos y obligatoriedad | Sin cuerpo. Filtros opcionales: `id_pareja`, `fecha_cruce` |
| Ejemplo de petición | `GET /api/v1/cruces?id_pareja=3&fecha_cruce=2026-11-22` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `cruce`, ordenados por fecha y ID descendente |
| Errores esperados | `401`, `403`, `404` perfil de criador inexistente, `500` |
| Reglas de validación | Filtros inválidos se ignoran; no se acepta `id_criador` enviado por el cliente |

### 2. Listar cruces de una pareja

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/cruces/pareja/{id}` |
| Quién puede usarla | Criador dueño de la pareja |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_pareja`) |
| Ejemplo de petición | `GET /api/v1/cruces/pareja/3` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `cruce` de esa pareja |
| Errores esperados | `400` ID inválido, `401`, `403`, `404` perfil de criador inexistente, `500` |
| Reglas de validación | Devuelve lista vacía si la pareja no existe, es ajena o aún no tiene cruces |

### 3. Ver detalle de un cruce

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/cruces/{id}` |
| Quién puede usarla | Criador dueño del cruce |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_cruce`) |
| Ejemplo de petición | `GET /api/v1/cruces/7` |
| Ejemplo de respuesta | `200` con `data` = objeto `cruce` |
| Errores esperados | `400` ID inválido, `401`, `403` cruce ajeno, `404` inexistente, `500` |
| Reglas de validación | La consulta filtra por `id_criador` de la pareja asociada |

### 4. Registrar cruce

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/cruces` |
| Quién puede usarla | Criador autenticado |
| Campos, tipos y obligatoriedad | Obligatorios: `id_pareja` (entero positivo), `fecha_cruce` (`YYYY-MM-DD`) |
| Ejemplo de petición | `{"id_pareja": 3, "fecha_cruce": "2026-11-22"}` |
| Ejemplo de respuesta | `201` con `data` = objeto `cruce` creado |
| Errores esperados | `400` JSON inválido, `401`, `403`, `404` pareja no encontrada en el criadero, `409` pareja no activa o restricción de BD, `422` validación, `500` |
| Reglas de validación | Solo se registran cruces en parejas activas; la fecha no puede estar vacía ni ser futura; una pareja admite varios cruces |

### 5. Editar o eliminar cruce

**No existe.** El SRS 1.2 excluye la edición y eliminación general de registros, y la BD v7.1 hace inmutable `cruce.id_pareja` (SQL-01). Para corregir un progenitor se reasigna la pareja (SRS-RF031), no el cruce.

## Campos y validaciones

### Usuario y criador

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `nombre` | texto | Sí (al crear) | Máximo 100 caracteres; solo letras, espacios y signos básicos (`.'-`), sin etiquetas HTML |
| `correo` | texto | Sí (al crear / login) | Formato de correo válido, máximo 100 caracteres; único sin distinguir mayúsculas (`uq_usuario_correo_lower`) |
| `password` | texto | Sí (al crear / login) | Mínimo 8 caracteres al crear o actualizar |
| `numero_socio` | texto | Sí (al crear criador) | 1–5 dígitos numéricos; único entre criadores y no editable desde `/criador/perfil` |

### Canario

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `anillo` | texto | Sí (al crear) | 1–6 dígitos; único en el sistema junto con club, socio y temporada |
| `id_club` | entero | Sí (al crear) | Entero positivo; debe existir en `club` |
| `numero_socio` | texto | Sí (al crear) | 1–5 dígitos; se ingresa, no se copia del criador |
| `temporada` | entero | Sí (al crear) | Entre 1000 y 9999 |
| `sexo` | texto | Sí (al crear un adulto) | `M` o `H`; debe coincidir con el sexo de la variedad |
| `id_variedad` | entero | Sí (al crear un adulto) | Debe existir en `variedad` |
| `requiere_revision` | booleano | No | No escribible: lo calcula la BD |
| `fecha_registro` | fecha y hora | No | La asigna la BD |

### Pareja

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `id_macho` | entero | Sí (al crear) | Entero positivo; ejemplar con `sexo = 'M'` del mismo criadero; máximo 6 parejas activas |
| `id_hembra` | entero | Sí (al crear) | Entero positivo; ejemplar con `sexo = 'H'` del mismo criadero; distinto de `id_macho`; máximo 1 pareja activa |
| `id_jaula` | entero | Sí (al crear) | Entero positivo; jaula del mismo criadero; máximo 1 pareja activa |
| `fecha_formacion` | fecha | No | Formato `YYYY-MM-DD`; menor o igual a la fecha actual (por defecto hoy) |
| `estado` | texto | No | `"activa"` (al crear), `"finalizada"` o `"anulada"` (al cerrar) |
| `fecha_fin` | fecha | No | Formato `YYYY-MM-DD`; `null` mientras esté `"activa"`, obligatoria y `>= fecha_formacion` al cerrar |

### Cruce

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `id_pareja` | entero | Sí (al crear) | Entero positivo; pareja `activa` del criadero autenticado |
| `fecha_cruce` | fecha | Sí (al crear) | Formato `YYYY-MM-DD`; no puede ser posterior a la fecha actual |
| `id_cruce` | entero | No | No escribible: lo genera la BD |
| `id_criador` | entero | No | No escribible: se toma de la pareja |

### Cría

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `id_nidada` | entero | Sí (al crear) | Entero positivo; nidada perteneciente al criadero autenticado; inmutable tras el registro |
| `id_canario` | entero | Sí (al crear) | Entero positivo; ejemplar del mismo criadero distinto de los progenitores; inmutable tras el registro |
| `factor_genetico` | entero o `null` | No | Entero positivo existente en `mutacion` o `null` |
| `es_portadora` | booleano | No | No escribible: lo calcula la BD (`factor_genetico IS NOT NULL`) |
| `reservada` | booleano | No | Booleano (`false` por defecto) |
| `id_cria` | entero | No | No escribible: lo genera la BD |
| `id_criador` | entero | No | No escribible: se toma de la pareja asociada a la nidada |

### Simulación

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `id_macho` | entero | Sí (al crear) | Entero positivo; ejemplar con `sexo = 'M'` del mismo criadero; distinto de `id_hembra` |
| `id_hembra` | entero | Sí (al crear) | Entero positivo; ejemplar con `sexo = 'H'` del mismo criadero; distinto de `id_macho` |
| `id_mutacion` | entero | Sí (al crear) | Entero positivo; debe existir en `mutacion` |
| `genotipo_macho` | texto | Sí (al crear) | `"visual"`, `"portador"` o `"sin factor"` |
| `genotipo_hembra` | texto | Sí (al crear) | `"visual"`, `"portador"` o `"sin factor"`; si la mutación es `"ligada al sexo recesiva"`, no puede ser `"portador"` (`trg_validar_simulacion`) |
| `id_simulacion` | entero | No | No escribible: lo genera la BD |
| `id_criador` | entero | No | No escribible: se toma del criador autenticado |
| `fecha` | fecha y hora | No | No escribible: lo asigna la BD (`CURRENT_TIMESTAMP`) |
| `resultados` | arreglo | No | No escribible: lo calcula y guarda el servidor en `simulacion_resultado` |

## Catálogos (wiki)

Endpoints de **solo lectura** que exponen los catálogos oficiales necesarios para registrar ejemplares y usar el simulador. No son una wiki de cuidados o alimentación: ese contenido queda fuera de alcance según la sección 1.2 del SRS. Requieren Bearer como el resto de `/api/v1`.

Traza: SRS-RF002 (siglas de club), SRS-RF007/RF008/RF009 (nomenclador y sexo de la variedad), SRS-RF011 (alta de clubes), SRS-RF025/RF027 (mutaciones). La carga administrativa de estos catálogos no está incluida aquí.

| Método y ruta | Respuesta | Descripción |
|---|---|---|
| `GET /api/v1/wiki` | `data` con `clubes`, `variedades`, `mutaciones` | Paquete completo para inicializar los desplegables. |
| `GET /api/v1/wiki/clubes` | lista de clubes | Siglas disponibles para el anillo. |
| `GET /api/v1/wiki/variedades` | lista de variedades | Nomenclador completo; admite filtros. |
| `GET /api/v1/wiki/variedades/codigo/{codigo}` | una variedad | Selección exacta por código (SRS-RF008). |
| `GET /api/v1/wiki/variedades/{id}` | una variedad | Detalle por `id_variedad`. |
| `GET /api/v1/wiki/mutaciones` | lista de mutaciones | Catálogo disponible en el simulador. |

Filtros opcionales de `GET /variedades`:

| Query param | Regla |
|---|---|
| `buscar` | Coincidencia parcial (ILIKE) en `codigo` o `nombre`; máximo 150 caracteres. |
| `codigo` | Código exacto del nomenclador; máximo 10 caracteres. |
| `tipo` | `CC` (color) o `CP` (forma y postura). |
| `sexo` | `M` u `H` (también en minúsculas). Si no se envía, la BD lo deriva de MACHO/HEMBRA en el nombre; cualquier otro valor se ignora. |

Errores propios: `400` ID o código inválido, `404` variedad inexistente, `422` filtro inválido (`tipo`, `codigo`, `buscar`). No se aceptan `POST`, `PUT`, `PATCH` ni `DELETE` en estas rutas.

Ejemplos de objetos devueltos:

```json
{ "id_club": 4, "sigla": "SOCH" }
```

```json
{ "id_variedad": 2, "codigo": "D.007", "nombre": "AMARILLO MOSAICO MACHO", "tipo": "CC", "serie": null, "sexo": "M" }
```

```json
{ "id_mutacion": 1, "nombre": "Ágata", "tipo_herencia": "ligada al sexo recesiva" }
```

`variedad.sexo` y `mutacion.tipo_herencia` los fija la BD (`CHAR(1)` derivado y `CHECK` de dos valores respectivamente). El cliente solo los lee en la respuesta; `sexo` además puede usarse como filtro.


## Códigos de dominio del backend

| Código del modelo | Respuesta HTTP | Significado |
|---|---|---|
| `conflict_anillo` | `409` | El anillo completo ya existe en cualquier criadero |
| `invalid_data` | `422` | Formato inválido o una regla de la BD rechazó el registro |
| `invalid_reference` | `422` | Club, variedad, ejemplar, jaula o criador inexistente o de otro criadero |
| `not_found` | `404` | Recurso inexistente o que no pertenece al criador |
| `conflict_email` | `409` | El correo electrónico ya está registrado en `usuario` |
| `conflict_member_number` | `409` | El número de socio ya está registrado por otro criador |
| `conflict` | `409` | Restricción de negocio o integridad referencial (`SQLSTATE 23503`, `23505` o trigger `P0001`) |
| `forbidden` | `403` | Política de permisos de BD impide la operación (`SQLSTATE 42501`) o recurso ajeno |

El mensaje de conflicto de anillo es genérico: no revela en qué criadero está registrado ni quién es su dueño (SRS-RF003).

## Gestión de jaulas

La gestión de jaulas está disponible para el usuario autenticado con rol `criador` y queda limitada a su propio criadero (StRS-004, SEG-001). La tabla `jaula` de la BD v7.1 contiene `id_jaula` (generado por la BD), `numero_jaula` e `id_criador`.

### Objeto `jaula`

| Campo | Tipo | Origen |
|---|---|---|
| `id_jaula` | entero | `jaula.id_jaula` |
| `numero_jaula` | entero | `jaula.numero_jaula` |
| `id_criador` | entero | `jaula.id_criador`, tomado del usuario autenticado |
| `ocupada` | booleano | Calculado: existe una pareja con `estado = 'activa'` asignada a esa jaula |

`ocupada` no es una columna de la base de datos; se calcula al consultar. Una jaula se considera ocupada mientras tenga una pareja activa. Al finalizar o anular la pareja, queda disponible (SRS-RF017 y SRS-RF031).

### 1. Listar jaulas

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/jaulas` |
| Quién puede usarla | Criador autenticado (solo las jaulas de su criadero) |
| Campos, tipos y obligatoriedad | Sin cuerpo |
| Ejemplo de petición | `GET /api/v1/jaulas` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `jaula`, ordenados por `numero_jaula` |
| Errores esperados | `401`, `403`, `500` |
| Reglas de validación | No se aceptan filtros de `id_criador` enviados por el cliente |

### 2. Ver detalle de una jaula

| Campo o decisión | Valor |
|---|---|
| Método y ruta | `GET /api/v1/jaulas/{id}` |
| Quién puede usarla | Criador dueño de la jaula |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_jaula`) |
| Ejemplo de petición | `GET /api/v1/jaulas/3` |
| Ejemplo de respuesta | `200` con `data` = objeto `jaula` |
| Errores esperados | `400` ID inválido, `401`, `403`, `404` jaula inexistente o de otro criadero |
| Reglas de validación | La consulta siempre filtra por `id_jaula` e `id_criador` del usuario autenticado |

### 3. Registrar jaula

| Campo o decisión | Valor |
|---|---|
| Método y ruta | `POST /api/v1/jaulas` |
| Quién puede usarla | Criador autenticado |
| Campos, tipos y obligatoriedad | Obligatorio: `numero_jaula` (entero entre 1 y 2.147.483.647) |
| Ejemplo de petición | `{"numero_jaula": 3}` |
| Ejemplo de respuesta | `201` con `data` = objeto `jaula` creado |
| Errores esperados | `400` JSON inválido, `401`, `403`, `409` número ya registrado en el criadero, `422` número inválido o restricción de BD, `500` |
| Reglas de validación | `id_jaula` lo genera la BD e `id_criador` se obtiene del token; no se aceptan en el cuerpo. El número debe ser positivo y único dentro del criadero (`uq_jaula_criador`). |

### Alcance de esta versión

No se implementan `PUT`, `PATCH` ni `DELETE` para jaulas. La versión 1.2 del SRS excluye la edición y eliminación general de registros; además, la base de datos hace inmutable `id_criador` en `jaula`. La ocupación se libera mediante el ciclo de vida de la pareja, no eliminando la jaula: una pareja se crea activa y al finalizarse libera su jaula (SRS-RF017).

## Gestión de nidadas

La gestión de nidadas está disponible para el usuario autenticado con rol `criador`. Cada nidada pertenece a un cruce, y el criadero propietario se determina mediante la relación `nidada -> cruce -> pareja`; el cliente no envía `id_criador` (SEG-001, DAT-001).

La tabla `nidada` de la BD v7.1 contiene `id_nidada` (generado por la BD), `id_cruce` y `fecha_nacimiento`. La fecha debe ser obligatoria, no puede ser anterior a `cruce.fecha_cruce` ni posterior a la fecha actual (SRS-RF018). La base de datos refuerza estas reglas mediante `NOT NULL`, `CHECK` y el trigger `trg_validar_nidada`.

### Objeto `nidada`

| Campo | Tipo | Origen |
|---|---|---|
| `id_nidada` | entero | `nidada.id_nidada`, generado por la BD |
| `id_cruce` | entero | `nidada.id_cruce`, cruce al que pertenece |
| `fecha_nacimiento` | fecha (`YYYY-MM-DD`) | `nidada.fecha_nacimiento` |
| `fecha_cruce` | fecha (`YYYY-MM-DD`) | `cruce.fecha_cruce`, dato relacionado de consulta |
| `id_pareja` | entero | `pareja.id_pareja`, dato relacionado de consulta |
| `anillo_macho` | texto | Anillo del macho de la pareja del cruce |
| `anillo_hembra` | texto | Anillo de la hembra de la pareja del cruce |

### 1. Listar nidadas

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/nidadas` |
| Quién puede usarla | Criador autenticado; solo devuelve nidadas de su criadero |
| Filtros opcionales | `id_cruce`, `fecha_nacimiento` |
| Ejemplo | `GET /api/v1/nidadas?id_cruce=12` |
| Respuesta | `200` con `data` = lista de objetos `nidada`, ordenados por fecha de nacimiento descendente |
| Errores esperados | `401`, `403`, `500` |

### 2. Listar nidadas de un cruce

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/nidadas/cruce/{id}` |
| Quién puede usarla | Criador autenticado; el cruce debe pertenecer a su criadero |
| Campos | `{id}` es el identificador positivo del cruce |
| Ejemplo | `GET /api/v1/nidadas/cruce/12` |
| Respuesta | `200` con `data` = lista de nidadas asociadas a ese cruce |
| Errores esperados | `400` ID inválido, `401`, `403`, `500` |

### 3. Ver detalle de una nidada

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/nidadas/{id}` |
| Quién puede usarla | Criador autenticado; solo puede consultar nidadas de su criadero |
| Campos | `{id}` es el identificador positivo de la nidada |
| Ejemplo | `GET /api/v1/nidadas/8` |
| Respuesta | `200` con `data` = objeto `nidada` con datos de su cruce y anillos de los progenitores |
| Errores esperados | `400` ID inválido, `401`, `403`, `404`, `500` |

### 4. Registrar una nidada

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/nidadas` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `id_cruce` (entero positivo), `fecha_nacimiento` (fecha `YYYY-MM-DD`) |
| Campos no aceptados | `id_nidada` e `id_criador` (los asigna o determina el servidor) |
| Ejemplo de petición | `{"id_cruce": 12, "fecha_nacimiento": "2026-11-20"}` |
| Respuesta | `201` con `data` = objeto `nidada` creado |
| Errores esperados | `400` JSON inválido, `401`, `403`, `404` cruce inexistente o ajeno, `422` fecha faltante, inválida, anterior al cruce o futura, `500` |
| Reglas de validación | El cruce debe existir y pertenecer al criadero autenticado. `fecha_nacimiento` debe ser igual o posterior a `fecha_cruce` y no posterior a la fecha actual (SRS-RF018). |

### Alcance de esta versión

No se implementan `PUT`, `PATCH` ni `DELETE` para nidadas. El SRS define su registro y consulta; además, la BD v7.1 hace inmutable `id_cruce` en una nidada mediante `trg_nidada_cruce_inmutable` (SQL-01).

## Gestión de crías

La gestión de crías está disponible para el usuario autenticado con rol `criador` y queda limitada a su propio criadero (SEG-001, DAT-004). Cada cría vincula una `nidada` (a través de `nidada -> cruce -> pareja`) con un ejemplar en `canario` y, opcionalmente, una mutación (`factor_genetico`).

`id_cria`, `id_criador` y `es_portadora` **no** se aceptan en el cuerpo (`es_portadora` lo calcula la BD a partir de `factor_genetico`). `id_nidada` e `id_canario` son inmutables tras el registro.

### Objeto `cria`

| Campo | Tipo | Origen |
|---|---|---|
| `id_cria` | entero | `cria.id_cria`, generado por la BD |
| `id_nidada` | entero | `cria.id_nidada`, nidada a la que pertenece |
| `id_canario` | entero | `cria.id_canario`, ejemplar asociado |
| `factor_genetico` | entero o `null` | `cria.factor_genetico` (`id_mutacion` o `null`) |
| `es_portadora` | booleano | `cria.es_portadora` (calculado/generado por la BD) |
| `reservada` | booleano | `cria.reservada` |
| `id_criador` | entero | `pareja.id_criador`, dato relacionado de consulta |
| `id_cruce` | entero | `nidada.id_cruce`, dato relacionado de consulta |
| `fecha_nacimiento` | fecha (`YYYY-MM-DD`) | `nidada.fecha_nacimiento`, dato relacionado de consulta |
| `anillo` | texto | `canario.anillo`, dato relacionado de consulta |
| `temporada` | entero | `canario.temporada`, dato relacionado de consulta |
| `sexo` | `"M"`, `"H"` o `null` | `canario.sexo`, dato relacionado de consulta |
| `id_variedad` | entero o `null` | `canario.id_variedad`, dato relacionado de consulta |
| `mutacion_nombre` | texto o `null` | `mutacion.nombre`, dato relacionado de consulta |

### 1. Listar crías

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/crias` |
| Quién puede usarla | Criador autenticado; solo devuelve crías de su criadero |
| Filtros opcionales | `id_nidada`, `id_canario`, `factor_genetico`, `reservada` |
| Ejemplo | `GET /api/v1/crias?id_nidada=8` |
| Respuesta | `200` con `data` = lista de objetos `cria` |
| Errores esperados | `401`, `403`, `404` perfil de criador inexistente, `500` |

### 2. Listar crías de una nidada

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/crias/nidada/{id}` |
| Quién puede usarla | Criador autenticado; la nidada debe pertenecer a su criadero |
| Campos | `{id}` es el identificador positivo de la nidada |
| Ejemplo | `GET /api/v1/crias/nidada/8` |
| Respuesta | `200` con `data` = lista de objetos `cria` asociados a esa nidada |
| Errores esperados | `400` ID inválido, `401`, `403`, `404` perfil de criador inexistente, `500` |

### 3. Ver detalle de una cría

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/crias/{id}` |
| Quién puede usarla | Criador autenticado; solo puede consultar crías de su criadero |
| Campos | `{id}` es el identificador positivo de la cría |
| Ejemplo | `GET /api/v1/crias/4` |
| Respuesta | `200` con `data` = objeto `cria` |
| Errores esperados | `400` ID inválido, `401`, `403`, `404`, `500` |

### 4. Registrar una cría

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/crias` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `id_nidada` (entero positivo), `id_canario` (entero positivo) |
| Campos opcionales | `factor_genetico` (entero positivo o `null`), `reservada` (booleano, por defecto `false`) |
| Campos no aceptados | `id_cria`, `id_criador`, `es_portadora` |
| Ejemplo de petición | `{"id_nidada": 8, "id_canario": 25, "factor_genetico": 1, "reservada": true}` |
| Respuesta | `201` con `data` = objeto `cria` creado |
| Errores esperados | `400` JSON inválido, `401`, `403`, `404` nidada inexistente o ajena, `409` canario ya registrado como cría o restricción de BD, `422` validación o referencia inválida, `500` |
| Reglas de validación | Tanto la nidada como el canario deben pertenecer al criadero autenticado, y `id_canario` no puede corresponder a ninguno de los progenitores de la pareja |

### 5. Actualizar una cría

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT` o `PATCH /api/v1/crias/{id}` |
| Quién puede usarla | Criador autenticado; solo sobre crías de su criadero |
| Campos opcionales | `factor_genetico` (entero positivo o `null`), `reservada` (booleano) |
| Campos no permitidos | `id_cria`, `id_criador`, `es_portadora`, `id_nidada`, `id_canario` |
| Ejemplo de petición | `PATCH /api/v1/crias/4` con `{"reservada": true, "factor_genetico": null}` |
| Respuesta | `200` con `data` = objeto `cria` actualizado |
| Errores esperados | `400` ID o JSON inválido, `401`, `403`, `404`, `409` restricción de BD, `422` validación o referencia inválida, `500` |

### Alcance de esta versión

No se implementa `DELETE` para crías. El SRS 1.2 excluye la eliminación física general de registros, y la BD v7.1 hace inmutables `id_nidada` e `id_canario` en `cria`.

## Simulación genética

La simulación genética está disponible para el usuario autenticado con rol `criador` y queda aislada por `id_criador` (SEG-001, SRS-RF025, DAT-006). Registra la simulación en `simulacion` y almacena las probabilidades calculadas en `simulacion_resultado`.

`id_simulacion`, `id_criador`, `fecha` y `resultados` **no** se aceptan en el cuerpo.

### Objeto `simulacion`

| Campo | Tipo | Origen |
|---|---|---|
| `id_simulacion` | entero | `simulacion.id_simulacion`, generado por la BD |
| `id_criador` | entero | `simulacion.id_criador`, criador autenticado |
| `id_macho` | entero | `simulacion.id_macho` (`canario` con `sexo = 'M'` del criadero) |
| `anillo_macho` | texto | `canario.anillo` (macho) |
| `id_hembra` | entero | `simulacion.id_hembra` (`canario` con `sexo = 'H'` del criadero) |
| `anillo_hembra` | texto | `canario.anillo` (hembra) |
| `id_mutacion` | entero | `simulacion.id_mutacion` (`mutacion.id_mutacion`) |
| `mutacion_nombre` | texto | `mutacion.nombre` |
| `tipo_herencia` | texto | `mutacion.tipo_herencia` (`"autosómica recesiva"` o `"ligada al sexo recesiva"`) |
| `genotipo_macho` | texto | `simulacion.genotipo_macho` (`"visual"`, `"portador"` o `"sin factor"`) |
| `genotipo_hembra` | texto | `simulacion.genotipo_hembra` (`"visual"`, `"portador"` o `"sin factor"`) |
| `fecha` | fecha y hora | `simulacion.fecha` |
| `resultados` | arreglo de objetos | Filas asociadas en `simulacion_resultado` (`sexo_cria`, `genotipo_resultado`, `probabilidad`) |

### 1. Listar simulaciones

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/simulaciones` |
| Quién puede usarla | Criador autenticado; solo devuelve simulaciones de su criadero |
| Filtros opcionales | `id_mutacion`, `id_macho`, `id_hembra` |
| Ejemplo | `GET /api/v1/simulaciones?id_mutacion=1` |
| Respuesta | `200` con `data` = lista de objetos `simulacion`, ordenados por `fecha` y `id_simulacion` descendente |
| Errores esperados | `401`, `403`, `404` perfil de criador inexistente, `500` |

### 2. Ver detalle de una simulación

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/simulaciones/{id}` |
| Quién puede usarla | Criador autenticado; solo puede consultar simulaciones de su criadero |
| Campos | `{id}` es el identificador positivo de la simulación |
| Ejemplo | `GET /api/v1/simulaciones/6` |
| Respuesta | `200` con `data` = objeto `simulacion` con su arreglo `resultados` |
| Errores esperados | `400` ID inválido, `401`, `403`, `404`, `500` |

### 3. Ejecutar y registrar simulación

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/simulaciones` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `id_macho`, `id_hembra`, `id_mutacion` (enteros positivos), `genotipo_macho`, `genotipo_hembra` (`"visual"`, `"portador"` o `"sin factor"`) |
| Ejemplo de petición | `{"id_macho": 10, "id_hembra": 14, "id_mutacion": 1, "genotipo_macho": "portador", "genotipo_hembra": "sin factor"}` |
| Respuesta | `201` con `data` = objeto `simulacion` creado junto con sus filas en `simulacion_resultado` |
| Errores esperados | `400` JSON inválido, `401`, `403`, `404` perfil de criador inexistente, `409` restricción de BD, `422` validación, sexo incorrecto, hembra portadora en mutación ligada al sexo o referencia ajena/inexistente, `500` |
| Reglas de validación | `id_macho` (`M`) y `id_hembra` (`H`) deben ser distintos y pertenecer al criadero; en herencia `"ligada al sexo recesiva"`, `genotipo_hembra` no puede ser `"portador"` (`trg_validar_simulacion`) y `sexo_cria` se informa como `"M"` o `"H"` sin `"portador"` en `"H"` (`ck_resultado_hembra`); en herencia `"autosómica recesiva"`, `sexo_cria` es `null` |

### Alcance de esta versión

No se implementan `PUT`, `PATCH` ni `DELETE` para simulaciones. El SRS 1.2 excluye la edición y eliminación general de registros, y la base de datos mantiene el historial de simulaciones por criadero.

## Gestión de títulos

La gestión de títulos de competencia está disponible para el usuario autenticado con rol `criador` y queda limitada a los ejemplares de su propio criadero (SRS-RF023, SEG-001). Los títulos se registran sobre el anillo de un ejemplar ya registrado; si el anillo no existe en el criadero, el registro se rechaza.

La tabla `titulo` de la BD v7.1 contiene `id_titulo` (generado por la BD), `id_canario`, `nombre` (obligatorio, hasta 100 caracteres, no vacío) y `fecha` (obligatoria, `YYYY-MM-DD`, no posterior a la fecha actual). Existe la restricción `uq_titulo (id_canario, nombre, fecha)` y el trigger `trg_titulo_canario_inmutable`: el ejemplar de un título no se puede cambiar.

### Objeto `titulo`

| Campo | Tipo | Origen |
|---|---|---|
| `id_titulo` | entero | `titulo.id_titulo`, generado por la BD |
| `id_canario` | entero | `titulo.id_canario`, ejemplar ganador |
| `nombre` | texto (1–100 caracteres) | `titulo.nombre` |
| `fecha` | fecha (`YYYY-MM-DD`) | `titulo.fecha` |
| `anillo` | texto | `canario.anillo`, dato relacionado de consulta |
| `numero_socio` | texto | `canario.numero_socio`, dato relacionado de consulta |
| `temporada` | entero | `canario.temporada`, dato relacionado de consulta |
| `sexo` | `"M"`, `"H"` o `null` | `canario.sexo`, dato relacionado de consulta |
| `id_club` | entero | `club.id_club`, dato relacionado de consulta |
| `club_sigla` | texto | `club.sigla`, dato relacionado de consulta |
| `id_criador` | entero | `canario.id_criador`, dato relacionado de consulta |

### 1. Listar títulos

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/titulos` |
| Quién puede usarla | Criador autenticado; solo devuelve títulos de su criadero |
| Filtros opcionales | `id_canario`, `nombre` (coincidencia parcial), `fecha` |
| Ejemplo | `GET /api/v1/titulos?id_canario=12` |
| Respuesta | `200` con `data` = lista de objetos `titulo`, ordenada por fecha descendente |
| Errores esperados | `401`, `403`, `404` perfil de criador inexistente, `500` |

### 2. Listar títulos de un ejemplar

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/titulos/canario/{id}` |
| Quién puede usarla | Criador autenticado; el ejemplar debe pertenecer a su criadero |
| Campos | `{id}` es `id_canario`, entero positivo |
| Ejemplo | `GET /api/v1/titulos/canario/12` |
| Respuesta | `200` con `data` = lista de títulos del ejemplar (lista vacía si no tiene) |
| Errores esperados | `400` ID inválido, `401`, `403`, `500` |

### 3. Ver detalle de un título

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/titulos/{id}` |
| Quién puede usarla | Criador autenticado; solo puede consultar títulos de su criadero |
| Campos | `{id}` es `id_titulo`, entero positivo |
| Ejemplo | `GET /api/v1/titulos/8` |
| Respuesta | `200` con `data` = objeto `titulo` |
| Errores esperados | `400` ID inválido, `401`, `403`, `404`, `500` |

### 4. Registrar un título

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/titulos` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `nombre` (texto de 1 a 100 caracteres), `fecha` (`YYYY-MM-DD` no futura) y el ejemplar, indicado con `id_canario` (entero positivo) **o** con el anillo completo (`anillo`, `id_club`, `numero_socio`, `temporada`) |
| Campos no aceptados | `id_titulo`, `id_criador` |
| Ejemplo de petición | `{"id_canario": 12, "nombre": "Campeón Nacional", "fecha": "2026-10-15"}` |
| Ejemplo con anillo | `{"anillo": "2901", "id_club": 4, "numero_socio": "456", "temporada": 2026, "nombre": "Campeón Nacional", "fecha": "2026-10-15"}` |
| Respuesta | `201` con `data` = objeto `titulo` creado |
| Errores esperados | `400` JSON inválido, `401`, `403`, `409` título duplicado, `422` nombre/fecha/anillo inválidos o ejemplar ajeno, `500` |
| Reglas de validación | El ejemplar debe existir en el criadero autenticado (SRS-RF023). Si se envían ambos, `id_canario` tiene prioridad sobre el anillo. No se permite repetir `(id_canario, nombre, fecha)` (`uq_titulo`). |

### 5. Actualizar un título

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT` o `PATCH /api/v1/titulos/{id}` |
| Quién puede usarla | Criador autenticado; solo sobre títulos de su criadero |
| Campos opcionales | `nombre`, `fecha` (se validan con las mismas reglas del registro) |
| Campos no permitidos | `id_titulo`, `id_criador`, `id_canario`, `anillo`, `id_club`, `numero_socio`, `temporada` |
| Ejemplo de petición | `PATCH /api/v1/titulos/8` con `{"nombre": "Campeón Regional 2026"}` |
| Respuesta | `200` con `data` = objeto `titulo` actualizado |
| Errores esperados | `400` ID/JSON inválido o sin campos editables, `401`, `403`, `404`, `409` título duplicado, `422` validación, `500` |
| Reglas de validación | `id_canario` es inmutable (`trg_titulo_canario_inmutable`); intentar cambiarlo responde `422`. |

### 6. Consultar la descendencia de un ejemplar ganador

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/titulos/canario/{id}/descendencia` |
| Quién puede usarla | Criador autenticado; el ejemplar debe pertenecer a su criadero |
| Campos | `{id}` es `id_canario`, entero positivo |
| Ejemplo | `GET /api/v1/titulos/canario/12/descendencia` |
| Respuesta | `200` con `data` = `{"id_canario": 12, "tiene_titulos": true, "grupos": [...]}`; cada grupo trae el ejemplar con que se cruzó y su lista de `crias` |
| Errores esperados | `400` ID inválido, `401`, `403`, `404` ejemplar ajeno o inexistente, `422` ejemplar sin sexo registrado, `500` |
| Reglas de validación | SRS-RF024: se agrupa por la hembra si el ganador es macho y por el macho si es hembra. Si el ejemplar no tiene títulos, `tiene_titulos` es `false` y `grupos` está vacío; si no tiene crías, se devuelve `grupos: []` y un mensaje explícito. Ninguno de los dos casos es un error HTTP. |

### Alcance de esta versión

No se implementa `DELETE` para títulos. El SRS exige conservar el historial al menos hasta el 31/12/2028 (DAT-002) y la BD v7.1 concede `SELECT, INSERT, UPDATE` sobre `titulo`, pero no `DELETE`. Tampoco se expone una entidad `concurso` separada: la BD v7.1 modela el concurso dentro de `titulo.nombre`.

## Pendiente de coordinar

- Carga administrativa del nomenclador, siglas de club y mutaciones (SRS-RF010/RF011/RF027): requiere su propio endpoint con archivo XLSX/CSV; no está en las rutas de solo lectura de esta sección.
- Avisar a Frontend que se incorporaron los endpoints de `cría` (`/api/v1/crias`) además de `pareja`, `cruce` y `nidada`.
- Avisar a Frontend que se incorporaron los endpoints de simulación genética (`/api/v1/simulaciones`) con desglose en `simulacion_resultado`.

- Avisar a Frontend que se incorporaron los endpoints de `cría` (`/api/v1/crias`) y de `título` (`/api/v1/titulos`, incluida la descendencia de un ganador) además de `pareja`, `cruce` y `nidada`.

Si una operación cambia, actualizar este documento y avisar a las áreas que la usan antes de integrar el cambio.

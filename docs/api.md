# Acuerdo de API

Borrador a completar por Frontend y Backend. Si cambia la estructura de los datos, coordinarlo con BD[cite: 24].
La API es la forma en que la pantalla pide y guarda información en el servidor[cite: 24].

Antes de programar, acordar nombres de campos, tipos, obligatorios, fechas y mensajes de error[cite: 24].
Fechas de calendario en `YYYY-MM-DD`; horas y eventos de monitoreo en la zona horaria configurada en `APP_TIMEZONE`[cite: 24].

## Convenciones generales

- Base: `/api/v1` (salvo `GET /api/health` y `POST /api/login`)[cite: 24].
- Autenticación: `Authorization: Bearer <token>` en todas las rutas privadas (`/api/v1/...`)[cite: 24].
- Cuerpo y respuesta: JSON[cite: 24].
- Formato de éxito:
  ```json
  { "status": "success", "message": "...", "data": { } }
  ```
- Formato de error:
  ```json
  { "status": "error", "message": "...", "errors": { "campo": "mensaje" } }
  ```
- Errores: `400` JSON/ID inválido, `401` sin token o sesión cerrada, `403` sin permiso, `404` no encontrado, `409` conflicto, `422` validación, `500` error interno[cite: 24].

## Acceso y sesión

La autenticación utiliza tokens JWT firmados (`HS256`) cuya duración en segundos se configura mediante `JWT_EXPIRATION` en `.env` (por defecto `7200`)[cite: 24]. El cierre de sesión revoca el hash SHA-256 del token actual en la tabla inmutable `auditoria`[cite: 23, 24].

### 1. Iniciar sesión

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/login`[cite: 24] |
| Quién puede usarla | Pública (cualquier usuario registrado: `criador` o `administrador`)[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Obligatorios: `correo` (texto), `password` (texto)[cite: 24] |
| Ejemplo de petición | `{"correo": "criador@canariapp.cl", "password": "********"}`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = `{"token": "<jwt>", "user": {"id_usuario": 2, "nombre": "...", "correo": "...", "rol": "criador"}}`[cite: 24] |
| Errores esperados | `400` correo o contraseña faltantes, `401` credenciales incorrectas, `500`[cite: 24] |
| Reglas de validación | El correo se normaliza a minúsculas antes de consultar[cite: 24] |

### 2. Ver sesión actual

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/me`[cite: 24] |
| Quién puede usarla | Cualquier usuario autenticado (`criador` o `administrador`)[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Sin cuerpo. Requiere cabecera `Authorization: Bearer <token>`[cite: 24] |
| Ejemplo de petición | `GET /api/v1/me`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = `{"user": {"jti": "...", "iat": 1700000000, "exp": 1700007200, "sub": 2, "correo": "...", "rol": "criador"}}`[cite: 24] |
| Errores esperados | `401` token ausente, expirado, alterado o con sesión cerrada, `500`[cite: 24] |
| Reglas de validación | Devuelve los claims decodificados del token JWT activo[cite: 24] |

### 3. Cerrar sesión

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/logout`[cite: 24] |
| Quién puede usarla | Cualquier usuario autenticado (`criador` o `administrador`)[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Sin cuerpo. Requiere cabecera `Authorization: Bearer <token>`[cite: 24] |
| Ejemplo de petición | `POST /api/v1/logout`[cite: 24] |
| Ejemplo de respuesta | `200` con `data = null` y `message = "Sesión cerrada exitosamente."`[cite: 24] |
| Errores esperados | `401` token ausente, inválido, expirado o sesión ya cerrada, `500`[cite: 24] |
| Reglas de validación | Invalida de inmediato el token enviado registrando su hash SHA-256 en `auditoria` (`accion = 'logout'`, `entidad = 'sesion'`); no afecta sesiones abiertas en otros dispositivos[cite: 23, 24] |

*(Rutas auxiliares públicas disponibles: `GET /api/health` para estado del servicio y `GET /api/v1` para el índice general de endpoints)*[cite: 24].

## Perfil del criador

### Objeto `criador`

| Campo | Tipo | Origen |
|---|---|---|
| `id_criador` | entero | `criador.id_criador`[cite: 23, 24] |
| `id_usuario` | entero | `criador.id_usuario` / `usuario.id_usuario`[cite: 23, 24] |
| `numero_socio` | texto (1–5 dígitos) | `criador.numero_socio`[cite: 23, 24] |
| `fecha_creacion` | fecha y hora | `criador.fecha_creacion`[cite: 23, 24] |
| `nombre` | texto | `usuario.nombre`[cite: 23, 24] |
| `correo` | texto | `usuario.correo`[cite: 23, 24] |
| `rol` | `"criador"` | `usuario.rol`[cite: 23, 24] |

### 1. Ver perfil propio

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/criador/perfil`[cite: 24] |
| Quién puede usarla | Usuario autenticado con perfil en `criador`[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Sin cuerpo[cite: 24] |
| Ejemplo de petición | `GET /api/v1/criador/perfil`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = objeto `criador`[cite: 24] |
| Errores esperados | `401`, `404` usuario sin perfil de criador asociado, `500`[cite: 24] |
| Reglas de validación | Toma el `id_usuario` directamente del claim `sub` del token JWT[cite: 24] |

### 2. Actualizar contraseña del perfil propio

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT /api/v1/criador/perfil`[cite: 24] |
| Quién puede usarla | Usuario autenticado con perfil en `criador`[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Obligatorio: `password` (texto, mínimo 8 caracteres)[cite: 24] |
| Ejemplo de petición | `{"password": "NuevaPassword123"}`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = objeto `criador`[cite: 24] |
| Errores esperados | `400` JSON inválido o intento de enviar `numero_socio`, `401`, `404` sin perfil asociado, `422` contraseña faltante o menor a 8 caracteres, `500`[cite: 24] |
| Reglas de validación | El criador solo puede actualizar su contraseña; `numero_socio` no es modificable desde este endpoint[cite: 24] |

## Administración de criadores

Todas las rutas bajo `/api/v1/admin/...` requieren autenticación y `rol = "administrador"`[cite: 23, 24].

### 1. Listar criadores

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/criadores`[cite: 24] |
| Quién puede usarla | Administrador[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Sin cuerpo. Filtro opcional por query string: `buscar`[cite: 24] |
| Ejemplo de petición | `GET /api/v1/admin/criadores?buscar=456`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `criador` ordenados del más reciente al más antiguo[cite: 24] |
| Errores esperados | `401`, `403` rol distinto a administrador, `500`[cite: 23, 24] |
| Reglas de validación | `buscar` filtra por coincidencia parcial (`ILIKE`) en `nombre`, `numero_socio` o `correo`[cite: 24] |

### 2. Ver detalle de un criador

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/criadores/{id}`[cite: 24] |
| Quién puede usarla | Administrador[cite: 23, 24] |
| Campos, tipos y obligatoriedad | `{id}` entero positivo correspondiente a `id_criador`[cite: 23, 24] |
| Ejemplo de petición | `GET /api/v1/admin/criadores/5`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = objeto `criador`[cite: 24] |
| Errores esperados | `400` ID inválido, `401`, `403`, `404` criador inexistente, `500`[cite: 24] |
| Reglas de validación | `{id}` debe ser un entero mayor a `0`[cite: 24] |

### 3. Crear criador

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/admin/criadores` *(alias compatible: `POST /api/v1/admin/register`)*[cite: 24] |
| Quién puede usarla | Administrador[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Obligatorios: `nombre`, `correo`, `password`, `numero_socio`[cite: 23, 24] |
| Ejemplo de petición | Ver bloque siguiente[cite: 24] |
| Ejemplo de respuesta | `201` con `data` = objeto `criador` creado *(en `/admin/register` devuelve `{"user": {...}}`)*[cite: 24] |
| Errores esperados | `400` JSON inválido, `401`, `403`, `409` correo o número de socio duplicado, `422` error de validación, `500`[cite: 24] |
| Reglas de validación | Crea usuario con `rol = "criador"` y su fila en `criador` dentro de una misma transacción[cite: 23, 24] |

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
| Método y ruta | `PUT /api/v1/admin/criadores/{id}`[cite: 24] |
| Quién puede usarla | Administrador[cite: 23, 24] |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_criador`). Opcionales en cuerpo: `nombre`, `correo`, `numero_socio`, `password` (los omitidos conservan su valor)[cite: 23, 24] |
| Ejemplo de petición | `{"nombre": "Carlos A. Mendoza", "numero_socio": "457"}`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = objeto `criador` actualizado[cite: 24] |
| Errores esperados | `400` ID o JSON inválido, `401`, `403`, `404` criador inexistente, `409` correo o número de socio ocupado por otro registro, `422` validación, `500`[cite: 24] |
| Reglas de validación | Si se envía `password` no vacía, debe tener al menos 8 caracteres[cite: 24] |

### 5. Eliminar criador

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `DELETE /api/v1/admin/criadores/{id}`[cite: 24] |
| Quién puede usarla | Administrador[cite: 23, 24] |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_criador`), sin cuerpo[cite: 23, 24] |
| Ejemplo de petición | `DELETE /api/v1/admin/criadores/5`[cite: 24] |
| Ejemplo de respuesta | `204 No Content`[cite: 24] |
| Errores esperados | `400` ID inválido, `401`, `403` política de permisos de BD impide borrar (`SQLSTATE 42501`), `404` criador inexistente, `409` criador con canarios, jaulas, simulaciones o historial de auditoría asociado (`SQLSTATE 23503`), `500`[cite: 23, 24] |
| Reglas de validación | Ejecuta el borrado en transacción (`criador` y luego `usuario` por trigger `trg_validar_baja_criador`); si la BD rechaza por privilegios o integridad referencial, devuelve `403` o `409` en lugar de `500`[cite: 23, 24] |

## Canario

El ejemplar se identifica por el **anillo completo**: número de anillo (1 a 6 dígitos), sigla del club, número de socio (1 a 5 dígitos) y temporada (año de 4 dígitos)[cite: 23, 24]. La combinación es única en todo el sistema, sin importar el criadero[cite: 23, 24]. La BD compara los números como enteros: `0005` y `5` son el mismo anillo[cite: 23, 24].

En el esquema v7.1 **no existen** `nombre`, `fecha_nacimiento`, `disponibilidad`, `id_color` ni una tabla `color`[cite: 23, 24]. La temporada define el año y el color del anillo; no se registra un color por ejemplar[cite: 24].

### Objeto `canario`

| Campo | Tipo | Origen |
|---|---|---|
| `id_canario` | entero | `canario.id_canario`[cite: 23, 24] |
| `anillo` | texto (1–6 dígitos) | `canario.anillo`[cite: 23, 24] |
| `id_club` | entero | `canario.id_club`[cite: 23, 24] |
| `club_sigla` | texto | `club.sigla`[cite: 23, 24] |
| `numero_socio` | texto (1–5 dígitos) | `canario.numero_socio` (se ingresa al registrar)[cite: 23, 24] |
| `temporada` | entero | `canario.temporada`[cite: 23, 24] |
| `sexo` | `"M"` o `"H"` | `canario.sexo`[cite: 23, 24] |
| `id_variedad` | entero | `canario.id_variedad`[cite: 23, 24] |
| `variedad_nombre` | texto | `variedad.nombre`[cite: 23, 24] |
| `id_criador` | entero | `canario.id_criador`[cite: 23, 24] |
| `criador_nombre` | texto | `usuario.nombre`[cite: 23, 24] |
| `fecha_registro` | fecha y hora | `canario.fecha_registro`[cite: 23, 24] |
| `requiere_revision` | booleano | `canario.requiere_revision` (lo calcula la BD)[cite: 23, 24] |

`id_canario`, `fecha_registro` y `requiere_revision` **no** se aceptan en el cuerpo[cite: 24]. `id_criador` tampoco: se toma del usuario autenticado[cite: 24]. El administrador es la excepción: debe indicar `id_criador` al crear un ejemplar, porque no tiene criadero propio[cite: 24].

### 1. Listar canarios

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/canarios`[cite: 24] |
| Quién puede usarla | Criador (solo los suyos) y administrador (todos)[cite: 24] |
| Campos, tipos y obligatoriedad | Sin cuerpo. Filtros opcionales: `buscar`, `id_club`, `id_variedad`, `temporada`[cite: 24] |
| Ejemplo de petición | `GET /api/v1/canarios?buscar=2901&id_club=4&temporada=2026`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `canario`[cite: 24] |
| Errores esperados | `401`, `500`[cite: 24] |
| Reglas de validación | `buscar` coincide parcialmente con el anillo o el número de socio; filtros vacíos se ignoran[cite: 24] |

### 2. Ver detalle de un canario

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/canarios/{id}`[cite: 24] |
| Quién puede usarla | Criador dueño del canario y administrador[cite: 24] |
| Campos, tipos y obligatoriedad | `{id}` entero positivo[cite: 24] |
| Ejemplo de petición | `GET /api/v1/canarios/12`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = objeto `canario`[cite: 24] |
| Errores esperados | `400` ID inválido, `401`, `403` canario ajeno, `404` inexistente[cite: 24] |
| Reglas de validación | Un criador no puede ver canarios de otro criadero[cite: 24] |

### 3. Crear canario

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/canarios`[cite: 24] |
| Quién puede usarla | Criador y administrador[cite: 24] |
| Campos, tipos y obligatoriedad | Obligatorios: `anillo`, `id_club`, `numero_socio`, `temporada`, `sexo`, `id_variedad`. El administrador además debe enviar `id_criador`[cite: 23, 24] |
| Ejemplo de petición | Ver bloque siguiente[cite: 24] |
| Ejemplo de respuesta | `201` con `data` = objeto `canario` creado[cite: 24] |
| Errores esperados | `400`, `401`, `403`, `409` anillo no disponible, `422` validación o referencia inexistente[cite: 24] |
| Reglas de validación | Ver tabla de campos. El sexo debe coincidir con el de la variedad[cite: 23, 24] |

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
| Método y ruta | `PUT` o `PATCH /api/v1/canarios/{id}`[cite: 24] |
| Quién puede usarla | Criador dueño del canario y administrador[cite: 24] |
| Campos, tipos y obligatoriedad | Mismos campos que crear; los omitidos conservan su valor[cite: 24] |
| Ejemplo de petición | `PATCH /api/v1/canarios/12` con `{"temporada": 2027}`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = objeto `canario` actualizado[cite: 24] |
| Errores esperados | `400`, `401`, `403`, `404`, `409`, `422`[cite: 24] |
| Reglas de validación | No se puede cambiar `id_criador`. `numero_socio` sí se puede cambiar: es parte del anillo. `anillo`, si viene, no puede quedar vacío[cite: 23, 24] |

### 5. Eliminar canario

**No existe.** El SRS 1.2 excluye la eliminación de registros y la BD v7.1 no concede `DELETE` al rol de la aplicación[cite: 24]. No se documenta ni se registra la ruta[cite: 24].

## Pareja

Cada pareja asocia un macho (`sexo = 'M'`) y una hembra (`sexo = 'H'`) del mismo criadero con una jaula (`id_jaula`) del mismo criadero[cite: 23, 24]. Toda pareja nace en estado `activa` con `fecha_fin = null`; un macho admite hasta 6 parejas activas, mientras que una hembra y una jaula admiten solo una pareja activa a la vez[cite: 23, 24].

`id_pareja` e `id_criador` **no** se aceptan en el cuerpo (el criadero se toma del usuario autenticado)[cite: 24]. Al crear una pareja tampoco se envían `estado` ni `fecha_fin`[cite: 24].

### Objeto `pareja`

| Campo | Tipo | Origen |
|---|---|---|
| `id_pareja` | entero | `pareja.id_pareja`[cite: 23, 24] |
| `id_criador` | entero | `pareja.id_criador`[cite: 23, 24] |
| `id_macho` | entero | `pareja.id_macho`[cite: 23, 24] |
| `anillo_macho` | texto | `canario.anillo` (macho)[cite: 23, 24] |
| `id_hembra` | entero | `pareja.id_hembra`[cite: 23, 24] |
| `anillo_hembra` | texto | `canario.anillo` (hembra)[cite: 23, 24] |
| `id_jaula` | entero | `pareja.id_jaula`[cite: 23, 24] |
| `numero_jaula` | entero | `jaula.numero_jaula`[cite: 23, 24] |
| `fecha_formacion` | fecha (`YYYY-MM-DD`) | `pareja.fecha_formacion`[cite: 23, 24] |
| `estado` | `"activa"`, `"finalizada"` o `"anulada"` | `pareja.estado`[cite: 23, 24] |
| `fecha_fin` | fecha (`YYYY-MM-DD`) o `null` | `pareja.fecha_fin`[cite: 23, 24] |

### 1. Listar parejas

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/parejas`[cite: 24] |
| Quién puede usarla | Criador autenticado (solo las parejas de su criadero)[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Sin cuerpo. Filtros opcionales por query string: `estado`, `id_macho`, `id_hembra`, `id_jaula`[cite: 24] |
| Ejemplo de petición | `GET /api/v1/parejas?estado=activa`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `pareja`[cite: 24] |
| Errores esperados | `401`, `403` rol distinto a criador, `404` sin perfil de criador asociado, `500`[cite: 23, 24] |
| Reglas de validación | Filtra estrictamente por el `id_criador` del usuario autenticado; filtros vacíos o inválidos se ignoran[cite: 23, 24] |

### 2. Ver detalle de una pareja

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/parejas/{id}`[cite: 24] |
| Quién puede usarla | Criador dueño de la pareja[cite: 23, 24] |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_pareja`)[cite: 23, 24] |
| Ejemplo de petición | `GET /api/v1/parejas/3`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = objeto `pareja`[cite: 24] |
| Errores esperados | `400` ID inválido, `401`, `403` pareja ajena o rol distinto a criador, `404` pareja o perfil inexistente, `500`[cite: 23, 24] |
| Reglas de validación | Un criador no puede consultar parejas pertenecientes a otro criadero[cite: 23, 24] |

### 3. Crear pareja

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/parejas`[cite: 24] |
| Quién puede usarla | Criador autenticado[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Obligatorios: `id_macho`, `id_hembra`, `id_jaula`. Opcional: `fecha_formacion` (`YYYY-MM-DD`, por defecto fecha actual)[cite: 23, 24] |
| Ejemplo de petición | Ver bloque siguiente[cite: 24] |
| Ejemplo de respuesta | `201` con `data` = objeto `pareja` creado en estado `"activa"`[cite: 23, 24] |
| Errores esperados | `400` JSON inválido, `401`, `403`, `409` máximo 6 parejas activas por macho, hembra con pareja activa o jaula ocupada, `422` validación o referencia ajena/inexistente, `500`[cite: 23, 24] |
| Reglas de validación | Macho (`M`) y hembra (`H`) deben ser distintos, pertenecer al criador y coincidir en criadero con la jaula; `fecha_formacion` no puede ser posterior a la fecha actual[cite: 23, 24] |

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
| Método y ruta | `PUT` o `PATCH /api/v1/parejas/{id}`[cite: 24] |
| Quién puede usarla | Criador dueño de la pareja[cite: 23, 24] |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_pareja`). Opcionales en cuerpo: `id_jaula`, `estado`, `fecha_fin`[cite: 23, 24] |
| Ejemplo de petición | `PATCH /api/v1/parejas/3` con `{"estado": "finalizada"}`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = objeto `pareja` actualizado[cite: 24] |
| Errores esperados | `400` ID o JSON inválido, `401`, `403`, `404`, `409` jaula ocupada o restricción de ciclo de vida en BD, `422` validación o referencia inválida, `500`[cite: 23, 24] |
| Reglas de validación | `id_criador`, `id_macho` e `id_hembra` no se modifican por este endpoint. Al pasar a `"finalizada"` o `"anulada"` se libera la jaula y se exige `fecha_fin >= fecha_formacion` (si no se envía `fecha_fin`, se asigna la fecha actual). Una pareja cerrada no puede volver a cambiar de estado y una pareja con cruces no puede anularse[cite: 23, 24] |

### 5. Eliminar pareja

**No existe.** El SRS 1.2 excluye la eliminación física de registros; las parejas se finalizan o anulan según las reglas del ciclo de vida y la BD v7.1[cite: 23, 24].

## Cruces

Un cruce es el apareamiento fechado de una pareja[cite: 23, 24]. Según SRS-RF016 una pareja puede tener **varios cruces**, siempre que esté `activa`[cite: 23, 24]. La fecha es obligatoria, se expresa como `YYYY-MM-DD` y no puede ser posterior a la fecha actual[cite: 23, 24]. El vínculo con la pareja es inmutable (revisión SQL-01), por lo que no hay `PUT`, `PATCH` ni `DELETE`[cite: 23, 24].

`id_cruce` e `id_criador` **no** se aceptan en el cuerpo[cite: 24]. El criadero se toma de la pareja, que debe pertenecer al usuario autenticado[cite: 23, 24].

### Objeto `cruce`

| Campo | Tipo | Origen |
|---|---|---|
| `id_cruce` | entero | `cruce.id_cruce`[cite: 23, 24] |
| `id_pareja` | entero | `cruce.id_pareja`[cite: 23, 24] |
| `fecha_cruce` | fecha (`YYYY-MM-DD`) | `cruce.fecha_cruce`[cite: 23, 24] |
| `id_criador` | entero | `pareja.id_criador`[cite: 23, 24] |
| `id_macho` | entero | `pareja.id_macho`[cite: 23, 24] |
| `anillo_macho` | texto | `canario.anillo` (macho)[cite: 23, 24] |
| `id_hembra` | entero | `pareja.id_hembra`[cite: 23, 24] |
| `anillo_hembra` | texto | `canario.anillo` (hembra)[cite: 23, 24] |

### 1. Listar cruces

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/cruces`[cite: 24] |
| Quién puede usarla | Criador autenticado (solo los cruces de su criadero)[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Sin cuerpo. Filtros opcionales: `id_pareja`, `fecha_cruce`[cite: 24] |
| Ejemplo de petición | `GET /api/v1/cruces?id_pareja=3&fecha_cruce=2026-11-22`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `cruce`, ordenados por fecha y ID descendente[cite: 24] |
| Errores esperados | `401`, `403`, `404` perfil de criador inexistente, `500`[cite: 24] |
| Reglas de validación | Filtros inválidos se ignoran; no se acepta `id_criador` enviado por el cliente[cite: 24] |

### 2. Listar cruces de una pareja

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/cruces/pareja/{id}`[cite: 24] |
| Quién puede usarla | Criador dueño de la pareja[cite: 23, 24] |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_pareja`)[cite: 23, 24] |
| Ejemplo de petición | `GET /api/v1/cruces/pareja/3`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `cruce` de esa pareja[cite: 24] |
| Errores esperados | `400` ID inválido, `401`, `403`, `404` perfil de criador inexistente, `500`[cite: 24] |
| Reglas de validación | Devuelve lista vacía si la pareja no existe, es ajena o aún no tiene cruces[cite: 24] |

### 3. Ver detalle de un cruce

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/cruces/{id}`[cite: 24] |
| Quién puede usarla | Criador dueño del cruce[cite: 23, 24] |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_cruce`)[cite: 23, 24] |
| Ejemplo de petición | `GET /api/v1/cruces/7`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = objeto `cruce`[cite: 24] |
| Errores esperados | `400` ID inválido, `401`, `403` cruce ajeno, `404` inexistente, `500`[cite: 24] |
| Reglas de validación | La consulta filtra por `id_criador` de la pareja asociada[cite: 23, 24] |

### 4. Registrar cruce

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/cruces`[cite: 24] |
| Quién puede usarla | Criador autenticado[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Obligatorios: `id_pareja` (entero positivo), `fecha_cruce` (`YYYY-MM-DD`)[cite: 23, 24] |
| Ejemplo de petición | `{"id_pareja": 3, "fecha_cruce": "2026-11-22"}`[cite: 24] |
| Ejemplo de respuesta | `201` con `data` = objeto `cruce` creado[cite: 24] |
| Errores esperados | `400` JSON inválido, `401`, `403`, `404` pareja no encontrada en el criadero, `409` pareja no activa o restricción de BD, `422` validación, `500`[cite: 23, 24] |
| Reglas de validación | Solo se registran cruces en parejas activas; la fecha no puede estar vacía ni ser futura; una pareja admite varios cruces[cite: 23, 24] |

### 5. Editar o eliminar cruce

**No existe.** El SRS 1.2 excluye la edición y eliminación general de registros, y la BD v7.1 hace inmutable `cruce.id_pareja` (SQL-01)[cite: 23, 24]. Para corregir un progenitor se reasigna la pareja (SRS-RF031), no el cruce[cite: 23, 24].

## Campos y validaciones

### Usuario y criador

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `nombre` | texto | Sí (al crear) | Máximo 100 caracteres; solo letras, espacios y signos básicos (`.'-`), sin etiquetas HTML[cite: 23, 24] |
| `correo` | texto | Sí (al crear / login) | Formato de correo válido, máximo 100 caracteres; único sin distinguir mayúsculas (`uq_usuario_correo_lower`)[cite: 23, 24] |
| `password` | texto | Sí (al crear / login) | Mínimo 8 caracteres al crear o actualizar[cite: 24] |
| `numero_socio` | texto | Sí (al crear criador) | 1–5 dígitos numéricos; único entre criadores y no editable desde `/criador/perfil`[cite: 23, 24] |

### Canario

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `anillo` | texto | Sí (al crear) | 1–6 dígitos; único en el sistema junto con club, socio y temporada[cite: 23, 24] |
| `id_club` | entero | Sí (al crear) | Entero positivo; debe existir en `club`[cite: 23, 24] |
| `numero_socio` | texto | Sí (al crear) | 1–5 dígitos; se ingresa, no se copia del criador[cite: 23, 24] |
| `temporada` | entero | Sí (al crear) | Entre 1000 y 9999[cite: 23, 24] |
| `sexo` | texto | Sí (al crear un adulto) | `M` o `H`; debe coincidir con el sexo de la variedad[cite: 23, 24] |
| `id_variedad` | entero | Sí (al crear un adulto) | Debe existir en `variedad`[cite: 23, 24] |
| `requiere_revision` | booleano | No | No escribible: lo calcula la BD[cite: 23, 24] |
| `fecha_registro` | fecha y hora | No | La asigna la BD[cite: 23, 24] |

### Pareja

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `id_macho` | entero | Sí (al crear) | Entero positivo; ejemplar con `sexo = 'M'` del mismo criadero; máximo 6 parejas activas[cite: 23, 24] |
| `id_hembra` | entero | Sí (al crear) | Entero positivo; ejemplar con `sexo = 'H'` del mismo criadero; distinto de `id_macho`; máximo 1 pareja activa[cite: 23, 24] |
| `id_jaula` | entero | Sí (al crear) | Entero positivo; jaula del mismo criadero; máximo 1 pareja activa[cite: 23, 24] |
| `fecha_formacion` | fecha | No | Formato `YYYY-MM-DD`; menor o igual a la fecha actual (por defecto hoy)[cite: 23, 24] |
| `estado` | texto | No | `"activa"` (al crear), `"finalizada"` o `"anulada"` (al cerrar)[cite: 23, 24] |
| `fecha_fin` | fecha | No | Formato `YYYY-MM-DD`; `null` mientras esté `"activa"`, obligatoria y `>= fecha_formacion` al cerrar[cite: 23, 24] |

### Cruce

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `id_pareja` | entero | Sí (al crear) | Entero positivo; pareja `activa` del criadero autenticado[cite: 23, 24] |
| `fecha_cruce` | fecha | Sí (al crear) | Formato `YYYY-MM-DD`; no puede ser posterior a la fecha actual[cite: 23, 24] |
| `id_cruce` | entero | No | No escribible: lo genera la BD[cite: 23, 24] |
| `id_criador` | entero | No | No escribible: se toma de la pareja[cite: 23, 24] |

### Cría

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `id_nidada` | entero | Sí (al crear) | Entero positivo; nidada perteneciente al criadero autenticado; inmutable tras el registro[cite: 23, 24] |
| `id_canario` | entero | Sí (al crear) | Entero positivo; ejemplar del mismo criadero distinto de los progenitores; inmutable tras el registro[cite: 23, 24] |
| `factor_genetico` | entero o `null` | No | Entero positivo existente en `mutacion` o `null`[cite: 23, 24] |
| `es_portadora` | booleano | No | No escribible: lo calcula la BD (`factor_genetico IS NOT NULL`)[cite: 23, 24] |
| `reservada` | booleano | No | Booleano (`false` por defecto)[cite: 23, 24] |
| `id_cria` | entero | No | No escribible: lo genera la BD[cite: 23, 24] |
| `id_criador` | entero | No | No escribible: se toma de la pareja asociada a la nidada[cite: 23, 24] |

### Simulación

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `id_macho` | entero | Sí (al crear) | Entero positivo; ejemplar con `sexo = 'M'` del mismo criadero; distinto de `id_hembra`[cite: 23] |
| `id_hembra` | entero | Sí (al crear) | Entero positivo; ejemplar con `sexo = 'H'` del mismo criadero; distinto de `id_macho`[cite: 23] |
| `id_mutacion` | entero | Sí (al crear) | Entero positivo; debe existir en `mutacion`[cite: 23] |
| `genotipo_macho` | texto | Sí (al crear) | `"visual"`, `"portador"` o `"sin factor"`[cite: 23] |
| `genotipo_hembra` | texto | Sí (al crear) | `"visual"`, `"portador"` o `"sin factor"`; si la mutación es `"ligada al sexo recesiva"`, no puede ser `"portador"` (`trg_validar_simulacion`)[cite: 23] |
| `id_simulacion` | entero | No | No escribible: lo genera la BD[cite: 23] |
| `id_criador` | entero | No | No escribible: se toma del criador autenticado[cite: 23] |
| `fecha` | fecha y hora | No | No escribible: lo asigna la BD (`CURRENT_TIMESTAMP`)[cite: 23] |
| `resultados` | arreglo | No | No escribible: lo calcula y guarda el servidor en `simulacion_resultado`[cite: 23] |

## Catálogos (wiki)

Endpoints de **solo lectura** que exponen los catálogos oficiales necesarios para registrar ejemplares y usar el simulador[cite: 23, 24]. No son una wiki de cuidados o alimentación: ese contenido queda fuera de alcance según la sección 1.2 del SRS[cite: 24]. Requieren Bearer como el resto de `/api/v1`[cite: 24].

Traza: SRS-RF002 (siglas de club), SRS-RF007/RF008/RF009 (nomenclador y sexo de la variedad), SRS-RF011 (alta de clubes), SRS-RF025/RF027 (mutaciones)[cite: 23, 24]. La carga administrativa de estos catálogos no está incluida aquí[cite: 24].

| Método y ruta | Respuesta | Descripción |
|---|---|---|
| `GET /api/v1/wiki`[cite: 24] | `data` con `clubes`, `variedades`, `mutaciones`[cite: 23, 24] | Paquete completo para inicializar los desplegables[cite: 24]. |
| `GET /api/v1/wiki/clubes`[cite: 24] | lista de clubes[cite: 23, 24] | Siglas disponibles para el anillo[cite: 23, 24]. |
| `GET /api/v1/wiki/variedades`[cite: 24] | lista de variedades[cite: 23, 24] | Nomenclador completo; admite filtros[cite: 24]. |
| `GET /api/v1/wiki/variedades/codigo/{codigo}`[cite: 24] | una variedad[cite: 23, 24] | Selección exacta por código (SRS-RF008)[cite: 24]. |
| `GET /api/v1/wiki/variedades/{id}`[cite: 24] | una variedad[cite: 23, 24] | Detalle por `id_variedad`[cite: 23, 24]. |
| `GET /api/v1/wiki/mutaciones`[cite: 24] | lista de mutaciones[cite: 23, 24] | Catálogo disponible en el simulador[cite: 23, 24]. |

Filtros opcionales de `GET /variedades`:

| Query param | Regla |
|---|---|
| `buscar` | Coincidencia parcial (ILIKE) en `codigo` o `nombre`; máximo 150 caracteres[cite: 23, 24]. |
| `codigo` | Código exacto del nomenclador; máximo 10 caracteres[cite: 23, 24]. |
| `tipo` | `CC` (color) o `CP` (forma y postura)[cite: 23, 24]. |
| `sexo` | `M` u `H` (también en minúsculas)[cite: 24]. Si no se envía, la BD lo deriva de MACHO/HEMBRA en el nombre; cualquier otro valor se ignora[cite: 23, 24]. |

Errores propios: `400` ID o código inválido, `404` variedad inexistente, `422` filtro inválido (`tipo`, `codigo`, `buscar`)[cite: 24]. No se aceptan `POST`, `PUT`, `PATCH` ni `DELETE` en estas rutas[cite: 24].

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

`variedad.sexo` y `mutacion.tipo_herencia` los fija la BD (`CHAR(1)` derivado y `CHECK` de dos valores respectivamente)[cite: 23, 24]. El cliente solo los lee en la respuesta; `sexo` además puede usarse como filtro[cite: 24].


## Códigos de dominio del backend

| Código del modelo | Respuesta HTTP | Significado |
|---|---|---|
| `conflict_anillo` | `409` | El anillo completo ya existe en cualquier criadero[cite: 23, 24] |
| `invalid_data` | `422` | Formato inválido o una regla de la BD rechazó el registro[cite: 24] |
| `invalid_reference` | `422` | Club, variedad, ejemplar, jaula o criador inexistente o de otro criadero[cite: 23, 24] |
| `not_found` | `404` | Recurso inexistente o que no pertenece al criador[cite: 24] |
| `conflict_email` | `409` | El correo electrónico ya está registrado en `usuario`[cite: 23, 24] |
| `conflict_member_number` | `409` | El número de socio ya está registrado por otro criador[cite: 23, 24] |
| `conflict` | `409` | Restricción de negocio o integridad referencial (`SQLSTATE 23503`, `23505` o trigger `P0001`)[cite: 24] |
| `forbidden` | `403` | Política de permisos de BD impide la operación (`SQLSTATE 42501`) o recurso ajeno[cite: 24] |

El mensaje de conflicto de anillo es genérico: no revela en qué criadero está registrado ni quién es su dueño (SRS-RF003)[cite: 23, 24].

## Gestión de jaulas

La gestión de jaulas está disponible para el usuario autenticado con rol `criador` y queda limitada a su propio criadero (StRS-004, SEG-001)[cite: 23, 24]. La tabla `jaula` de la BD v7.1 contiene `id_jaula` (generado por la BD), `numero_jaula` e `id_criador`[cite: 23, 24].

### Objeto `jaula`

| Campo | Tipo | Origen |
|---|---|---|
| `id_jaula` | entero | `jaula.id_jaula`[cite: 23, 24] |
| `numero_jaula` | entero | `jaula.numero_jaula`[cite: 23, 24] |
| `id_criador` | entero | `jaula.id_criador`, tomado del usuario autenticado[cite: 23, 24] |
| `ocupada` | booleano | Calculado: existe una pareja con `estado = 'activa'` asignada a esa jaula[cite: 23, 24] |

`ocupada` no es una columna de la base de datos; se calcula al consultar[cite: 23, 24]. Una jaula se considera ocupada mientras tenga una pareja activa[cite: 23, 24]. Al finalizar o anular la pareja, queda disponible (SRS-RF017 y SRS-RF031)[cite: 23, 24].

### 1. Listar jaulas

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/jaulas`[cite: 24] |
| Quién puede usarla | Criador autenticado (solo las jaulas de su criadero)[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Sin cuerpo[cite: 24] |
| Ejemplo de petición | `GET /api/v1/jaulas`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `jaula`, ordenados por `numero_jaula`[cite: 23, 24] |
| Errores esperados | `401`, `403`, `500`[cite: 24] |
| Reglas de validación | No se aceptan filtros de `id_criador` enviados por el cliente[cite: 23, 24] |

### 2. Ver detalle de una jaula

| Campo o decisión | Valor |
|---|---|
| Método y ruta | `GET /api/v1/jaulas/{id}`[cite: 24] |
| Quién puede usarla | Criador dueño de la jaula[cite: 23, 24] |
| Campos, tipos y obligatoriedad | `{id}` entero positivo (`id_jaula`)[cite: 23, 24] |
| Ejemplo de petición | `GET /api/v1/jaulas/3`[cite: 24] |
| Ejemplo de respuesta | `200` con `data` = objeto `jaula`[cite: 24] |
| Errores esperados | `400` ID inválido, `401`, `403`, `404` jaula inexistente o de otro criadero[cite: 23, 24] |
| Reglas de validación | La consulta siempre filtra por `id_jaula` e `id_criador` del usuario autenticado[cite: 23, 24] |

### 3. Registrar jaula

| Campo o decisión | Valor |
|---|---|
| Método y ruta | `POST /api/v1/jaulas`[cite: 24] |
| Quién puede usarla | Criador autenticado[cite: 23, 24] |
| Campos, tipos y obligatoriedad | Obligatorio: `numero_jaula` (entero entre 1 y 2.147.483.647)[cite: 23, 24] |
| Ejemplo de petición | `{"numero_jaula": 3}`[cite: 24] |
| Ejemplo de respuesta | `201` con `data` = objeto `jaula` creado[cite: 24] |
| Errores esperados | `400` JSON inválido, `401`, `403`, `409` número ya registrado en el criadero, `422` número inválido o restricción de BD, `500`[cite: 23, 24] |
| Reglas de validación | `id_jaula` lo genera la BD e `id_criador` se obtiene del token; no se aceptan en el cuerpo[cite: 23, 24]. El número debe ser positivo y único dentro del criadero (`uq_jaula_criador`)[cite: 23, 24]. |

### Alcance de esta versión

No se implementan `PUT`, `PATCH` ni `DELETE` para jaulas[cite: 24]. La versión 1.2 del SRS excluye la edición y eliminación general de registros; además, la base de datos hace inmutable `id_criador` en `jaula`[cite: 23, 24]. La ocupación se libera mediante el ciclo de vida de la pareja, no eliminando la jaula: una pareja se crea activa y al finalizarse libera su jaula (SRS-RF017)[cite: 23, 24].

## Gestión de nidadas

La gestión de nidadas está disponible para el usuario autenticado con rol `criador`[cite: 23, 24]. Cada nidada pertenece a un cruce, y el criadero propietario se determina mediante la relación `nidada -> cruce -> pareja`; el cliente no envía `id_criador` (SEG-001, DAT-001)[cite: 23, 24].

La tabla `nidada` de la BD v7.1 contiene `id_nidada` (generado por la BD), `id_cruce` y `fecha_nacimiento`[cite: 23, 24]. La fecha debe ser obligatoria, no puede ser anterior a `cruce.fecha_cruce` ni posterior a la fecha actual (SRS-RF018)[cite: 23, 24]. La base de datos refuerza estas reglas mediante `NOT NULL`, `CHECK` y el trigger `trg_validar_nidada`[cite: 23, 24].

### Objeto `nidada`

| Campo | Tipo | Origen |
|---|---|---|
| `id_nidada` | entero | `nidada.id_nidada`, generado por la BD[cite: 23, 24] |
| `id_cruce` | entero | `nidada.id_cruce`, cruce al que pertenece[cite: 23, 24] |
| `fecha_nacimiento` | fecha (`YYYY-MM-DD`) | `nidada.fecha_nacimiento`[cite: 23, 24] |
| `fecha_cruce` | fecha (`YYYY-MM-DD`) | `cruce.fecha_cruce`, dato relacionado de consulta[cite: 23, 24] |
| `id_pareja` | entero | `pareja.id_pareja`, dato relacionado de consulta[cite: 23, 24] |
| `anillo_macho` | texto | Anillo del macho de la pareja del cruce[cite: 23, 24] |
| `anillo_hembra` | texto | Anillo de la hembra de la pareja del cruce[cite: 23, 24] |

### 1. Listar nidadas

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/nidadas`[cite: 24] |
| Quién puede usarla | Criador autenticado; solo devuelve nidadas de su criadero[cite: 23, 24] |
| Filtros opcionales | `id_cruce`, `fecha_nacimiento`[cite: 24] |
| Ejemplo | `GET /api/v1/nidadas?id_cruce=12`[cite: 24] |
| Respuesta | `200` con `data` = lista de objetos `nidada`, ordenados por fecha de nacimiento descendente[cite: 24] |
| Errores esperados | `401`, `403`, `500`[cite: 24] |

### 2. Listar nidadas de un cruce

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/nidadas/cruce/{id}`[cite: 24] |
| Quién puede usarla | Criador autenticado; el cruce debe pertenecer a su criadero[cite: 23, 24] |
| Campos | `{id}` es el identificador positivo del cruce[cite: 24] |
| Ejemplo | `GET /api/v1/nidadas/cruce/12`[cite: 24] |
| Respuesta | `200` con `data` = lista de nidadas asociadas a ese cruce[cite: 24] |
| Errores esperados | `400` ID inválido, `401`, `403`, `500`[cite: 24] |

### 3. Ver detalle de una nidada

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/nidadas/{id}`[cite: 24] |
| Quién puede usarla | Criador autenticado; solo puede consultar nidadas de su criadero[cite: 23, 24] |
| Campos | `{id}` es el identificador positivo de la nidada[cite: 24] |
| Ejemplo | `GET /api/v1/nidadas/8`[cite: 24] |
| Respuesta | `200` con `data` = objeto `nidada` con datos de su cruce y anillos de los progenitores[cite: 23, 24] |
| Errores esperados | `400` ID inválido, `401`, `403`, `404`, `500`[cite: 24] |

### 4. Registrar una nidada

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/nidadas`[cite: 24] |
| Quién puede usarla | Criador autenticado[cite: 23, 24] |
| Campos obligatorios | `id_cruce` (entero positivo), `fecha_nacimiento` (fecha `YYYY-MM-DD`)[cite: 23, 24] |
| Campos no aceptados | `id_nidada` e `id_criador` (los asigna o determina el servidor)[cite: 23, 24] |
| Ejemplo de petición | `{"id_cruce": 12, "fecha_nacimiento": "2026-11-20"}`[cite: 24] |
| Respuesta | `201` con `data` = objeto `nidada` creado[cite: 24] |
| Errores esperados | `400` JSON inválido, `401`, `403`, `404` cruce inexistente o ajeno, `422` fecha faltante, inválida, anterior al cruce o futura, `500`[cite: 23, 24] |
| Reglas de validación | El cruce debe existir y pertenecer al criadero autenticado[cite: 23, 24]. `fecha_nacimiento` debe ser igual o posterior a `fecha_cruce` y no posterior a la fecha actual (SRS-RF018)[cite: 23, 24]. |

### Alcance de esta versión

No se implementan `PUT`, `PATCH` ni `DELETE` para nidadas[cite: 24]. El SRS define su registro y consulta; además, la BD v7.1 hace inmutable `id_cruce` en una nidada mediante `trg_nidada_cruce_inmutable` (SQL-01)[cite: 23, 24].

## Gestión de crías

La gestión de crías está disponible para el usuario autenticado con rol `criador` y queda limitada a su propio criadero (SEG-001, DAT-004)[cite: 23, 24]. Cada cría vincula una `nidada` (a través de `nidada -> cruce -> pareja`) con un ejemplar en `canario` y, opcionalmente, una mutación (`factor_genetico`)[cite: 23, 24].

`id_cria`, `id_criador` y `es_portadora` **no** se aceptan en el cuerpo (`es_portadora` lo calcula la BD a partir de `factor_genetico`)[cite: 23, 24]. `id_nidada` e `id_canario` son inmutables tras el registro[cite: 23, 24].

### Objeto `cria`

| Campo | Tipo | Origen |
|---|---|---|
| `id_cria` | entero | `cria.id_cria`, generado por la BD[cite: 23, 24] |
| `id_nidada` | entero | `cria.id_nidada`, nidada a la que pertenece[cite: 23, 24] |
| `id_canario` | entero | `cria.id_canario`, ejemplar asociado[cite: 23, 24] |
| `factor_genetico` | entero o `null` | `cria.factor_genetico` (`id_mutacion` o `null`)[cite: 23, 24] |
| `es_portadora` | booleano | `cria.es_portadora` (calculado/generado por la BD)[cite: 23, 24] |
| `reservada` | booleano | `cria.reservada`[cite: 23, 24] |
| `id_criador` | entero | `pareja.id_criador`, dato relacionado de consulta[cite: 23, 24] |
| `id_cruce` | entero | `nidada.id_cruce`, dato relacionado de consulta[cite: 23, 24] |
| `fecha_nacimiento` | fecha (`YYYY-MM-DD`) | `nidada.fecha_nacimiento`, dato relacionado de consulta[cite: 23, 24] |
| `anillo` | texto | `canario.anillo`, dato relacionado de consulta[cite: 23, 24] |
| `temporada` | entero | `canario.temporada`, dato relacionado de consulta[cite: 23, 24] |
| `sexo` | `"M"`, `"H"` o `null` | `canario.sexo`, dato relacionado de consulta[cite: 23, 24] |
| `id_variedad` | entero o `null` | `canario.id_variedad`, dato relacionado de consulta[cite: 23, 24] |
| `mutacion_nombre` | texto o `null` | `mutacion.nombre`, dato relacionado de consulta[cite: 23, 24] |

### 1. Listar crías

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/crias`[cite: 24] |
| Quién puede usarla | Criador autenticado; solo devuelve crías de su criadero[cite: 23, 24] |
| Filtros opcionales | `id_nidada`, `id_canario`, `factor_genetico`, `reservada`[cite: 24] |
| Ejemplo | `GET /api/v1/crias?id_nidada=8`[cite: 24] |
| Respuesta | `200` con `data` = lista de objetos `cria`[cite: 24] |
| Errores esperados | `401`, `403`, `404` perfil de criador inexistente, `500`[cite: 24] |

### 2. Listar crías de una nidada

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/crias/nidada/{id}`[cite: 24] |
| Quién puede usarla | Criador autenticado; la nidada debe pertenecer a su criadero[cite: 23, 24] |
| Campos | `{id}` es el identificador positivo de la nidada[cite: 24] |
| Ejemplo | `GET /api/v1/crias/nidada/8`[cite: 24] |
| Respuesta | `200` con `data` = lista de objetos `cria` asociados a esa nidada[cite: 24] |
| Errores esperados | `400` ID inválido, `401`, `403`, `404` perfil de criador inexistente, `500`[cite: 24] |

### 3. Ver detalle de una cría

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/crias/{id}`[cite: 24] |
| Quién puede usarla | Criador autenticado; solo puede consultar crías de su criadero[cite: 23, 24] |
| Campos | `{id}` es el identificador positivo de la cría[cite: 24] |
| Ejemplo | `GET /api/v1/crias/4`[cite: 24] |
| Respuesta | `200` con `data` = objeto `cria`[cite: 24] |
| Errores esperados | `400` ID inválido, `401`, `403`, `404`, `500`[cite: 24] |

### 4. Registrar una cría

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/crias`[cite: 24] |
| Quién puede usarla | Criador autenticado[cite: 23, 24] |
| Campos obligatorios | `id_nidada` (entero positivo), `id_canario` (entero positivo)[cite: 23, 24] |
| Campos opcionales | `factor_genetico` (entero positivo o `null`), `reservada` (booleano, por defecto `false`)[cite: 23, 24] |
| Campos no aceptados | `id_cria`, `id_criador`, `es_portadora`[cite: 23, 24] |
| Ejemplo de petición | `{"id_nidada": 8, "id_canario": 25, "factor_genetico": 1, "reservada": true}`[cite: 24] |
| Respuesta | `201` con `data` = objeto `cria` creado[cite: 24] |
| Errores esperados | `400` JSON inválido, `401`, `403`, `404` nidada inexistente o ajena, `409` canario ya registrado como cría o restricción de BD, `422` validación o referencia inválida, `500`[cite: 23, 24] |
| Reglas de validación | Tanto la nidada como el canario deben pertenecer al criadero autenticado, y `id_canario` no puede corresponder a ninguno de los progenitores de la pareja[cite: 23, 24] |

### 5. Actualizar una cría

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT` o `PATCH /api/v1/crias/{id}`[cite: 24] |
| Quién puede usarla | Criador autenticado; solo sobre crías de su criadero[cite: 23, 24] |
| Campos opcionales | `factor_genetico` (entero positivo o `null`), `reservada` (booleano)[cite: 23, 24] |
| Campos no permitidos | `id_cria`, `id_criador`, `es_portadora`, `id_nidada`, `id_canario`[cite: 23, 24] |
| Ejemplo de petición | `PATCH /api/v1/crias/4` con `{"reservada": true, "factor_genetico": null}`[cite: 24] |
| Respuesta | `200` con `data` = objeto `cria` actualizado[cite: 24] |
| Errores esperados | `400` ID o JSON inválido, `401`, `403`, `404`, `409` restricción de BD, `422` validación o referencia inválida, `500`[cite: 23, 24] |

### Alcance de esta versión

No se implementa `DELETE` para crías[cite: 24]. El SRS 1.2 excluye la eliminación física general de registros, y la BD v7.1 hace inmutables `id_nidada` e `id_canario` en `cria`[cite: 23, 24].

## Simulación genética

La simulación genética está disponible para el usuario autenticado con rol `criador` y queda aislada por `id_criador` (SEG-001, SRS-RF025, DAT-006)[cite: 23]. Registra la simulación en `simulacion` y almacena las probabilidades calculadas en `simulacion_resultado`[cite: 23].

`id_simulacion`, `id_criador`, `fecha` y `resultados` **no** se aceptan en el cuerpo[cite: 23].

### Objeto `simulacion`

| Campo | Tipo | Origen |
|---|---|---|
| `id_simulacion` | entero | `simulacion.id_simulacion`, generado por la BD[cite: 23] |
| `id_criador` | entero | `simulacion.id_criador`, criador autenticado[cite: 23] |
| `id_macho` | entero | `simulacion.id_macho` (`canario` con `sexo = 'M'` del criadero)[cite: 23] |
| `anillo_macho` | texto | `canario.anillo` (macho)[cite: 23] |
| `id_hembra` | entero | `simulacion.id_hembra` (`canario` con `sexo = 'H'` del criadero)[cite: 23] |
| `anillo_hembra` | texto | `canario.anillo` (hembra)[cite: 23] |
| `id_mutacion` | entero | `simulacion.id_mutacion` (`mutacion.id_mutacion`)[cite: 23] |
| `mutacion_nombre` | texto | `mutacion.nombre`[cite: 23] |
| `tipo_herencia` | texto | `mutacion.tipo_herencia` (`"autosómica recesiva"` o `"ligada al sexo recesiva"`)[cite: 23] |
| `genotipo_macho` | texto | `simulacion.genotipo_macho` (`"visual"`, `"portador"` o `"sin factor"`)[cite: 23] |
| `genotipo_hembra` | texto | `simulacion.genotipo_hembra` (`"visual"`, `"portador"` o `"sin factor"`)[cite: 23] |
| `fecha` | fecha y hora | `simulacion.fecha`[cite: 23] |
| `resultados` | arreglo de objetos | Filas asociadas en `simulacion_resultado` (`sexo_cria`, `genotipo_resultado`, `probabilidad`)[cite: 23] |

### 1. Listar simulaciones

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/simulaciones` |
| Quién puede usarla | Criador autenticado; solo devuelve simulaciones de su criadero[cite: 23] |
| Filtros opcionales | `id_mutacion`, `id_macho`, `id_hembra`[cite: 23] |
| Ejemplo | `GET /api/v1/simulaciones?id_mutacion=1` |
| Respuesta | `200` con `data` = lista de objetos `simulacion`, ordenados por `fecha` y `id_simulacion` descendente[cite: 23] |
| Errores esperados | `401`, `403`, `404` perfil de criador inexistente, `500` |

### 2. Ver detalle de una simulación

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/simulaciones/{id}` |
| Quién puede usarla | Criador autenticado; solo puede consultar simulaciones de su criadero[cite: 23] |
| Campos | `{id}` es el identificador positivo de la simulación[cite: 23] |
| Ejemplo | `GET /api/v1/simulaciones/6` |
| Respuesta | `200` con `data` = objeto `simulacion` con su arreglo `resultados`[cite: 23] |
| Errores esperados | `400` ID inválido, `401`, `403`, `404`, `500` |

### 3. Ejecutar y registrar simulación

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/simulaciones` |
| Quién puede usarla | Criador autenticado[cite: 23] |
| Campos obligatorios | `id_macho`, `id_hembra`, `id_mutacion` (enteros positivos), `genotipo_macho`, `genotipo_hembra` (`"visual"`, `"portador"` o `"sin factor"`)[cite: 23] |
| Ejemplo de petición | `{"id_macho": 10, "id_hembra": 14, "id_mutacion": 1, "genotipo_macho": "portador", "genotipo_hembra": "sin factor"}`[cite: 23] |
| Respuesta | `201` con `data` = objeto `simulacion` creado junto con sus filas en `simulacion_resultado`[cite: 23] |
| Errores esperados | `400` JSON inválido, `401`, `403`, `404` perfil de criador inexistente, `409` restricción de BD, `422` validación, sexo incorrecto, hembra portadora en mutación ligada al sexo o referencia ajena/inexistente, `500`[cite: 23] |
| Reglas de validación | `id_macho` (`M`) y `id_hembra` (`H`) deben ser distintos y pertenecer al criadero; en herencia `"ligada al sexo recesiva"`, `genotipo_hembra` no puede ser `"portador"` (`trg_validar_simulacion`) y `sexo_cria` se informa como `"M"` o `"H"` sin `"portador"` en `"H"` (`ck_resultado_hembra`); en herencia `"autosómica recesiva"`, `sexo_cria` es `null`[cite: 23] |

### Alcance de esta versión

No se implementan `PUT`, `PATCH` ni `DELETE` para simulaciones[cite: 24]. El SRS 1.2 excluye la edición y eliminación general de registros, y la base de datos mantiene el historial de simulaciones por criadero[cite: 23, 24].

## Pendiente de coordinar

- Carga administrativa del nomenclador, siglas de club y mutaciones (SRS-RF010/RF011/RF027): requiere su propio endpoint con archivo XLSX/CSV; no está en las rutas de solo lectura de esta sección[cite: 23, 24].
- Avisar a Frontend que se incorporaron los endpoints de `cría` (`/api/v1/crias`) además de `pareja`, `cruce` y `nidada`[cite: 24].
- Avisar a Frontend que se incorporaron los endpoints de simulación genética (`/api/v1/simulaciones`) con desglose en `simulacion_resultado`[cite: 23].

Si una operación cambia, actualizar este documento y avisar a las áreas que la usan antes de integrar el cambio[cite: 24].

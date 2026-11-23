# Acuerdo de API

Documento de contrato entre Frontend, Backend y Base de Datos (`canarios_v7_1.sql`). Si cambia la estructura de los datos o algún endpoint, coordinar y actualizar este acuerdo antes de integrar el cambio.

- **Fechas de calendario:** `YYYY-MM-DD`.
- **Fechas y horas de monitoreo/eventos:** zona horaria configurada en `APP_TIMEZONE` (`America/Santiago`).

---

## Índice

1. [Convenciones generales y control de acceso](#1-convenciones-generales-y-control-de-acceso)
2. [Acceso, sesión y estado operativo](#2-acceso-sesión-y-estado-operativo)
3. [Perfil del criador](#3-perfil-del-criador)
4. [Módulo de crianza (rol `criador`)](#4-módulo-de-crianza-rol-criador)
   - [4.1 Canarios (incluye Modo de Corrección y Ascendencia)](#41-canarios)
   - [4.2 Solicitudes de corrección (criador)](#42-solicitudes-de-corrección-criador)
   - [4.3 Jaulas](#43-jaulas)
   - [4.4 Parejas (incluye Modo de Corrección)](#44-parejas)
   - [4.5 Cruces](#45-cruces)
   - [4.6 Nidadas](#46-nidadas)
   - [4.7 Crías (incluye alta conjunta RF019/RF020 y Ascendencia)](#47-crías)
   - [4.8 Títulos de competencia (incluye Descendencia)](#48-títulos-de-competencia)
   - [4.9 Simulación genética](#49-simulación-genética)
5. [Catálogos oficiales (Wiki)](#5-catálogos-oficiales-wiki)
6. [Módulo de administración (rol `administrador`)](#6-módulo-de-administración-rol-administrador)
   - [6.1 Gestión de criadores](#61-gestión-de-criadores)
   - [6.2 Resolución de solicitudes de corrección](#62-resolución-de-solicitudes-de-corrección)
   - [6.3 Modos de operación (`mantenimiento` y `emergencia`)](#63-modos-de-operación-mantenimiento-y-emergencia)
   - [6.4 Auditoría del sistema](#64-auditoría-del-sistema)
   - [6.5 Respaldos y rotación](#65-respaldos-y-rotación)
7. [Referencia de campos, validaciones y códigos de dominio](#7-referencia-de-campos-validaciones-y-códigos-de-dominio)
8. [Pendiente de coordinar](#8-pendiente-de-coordinar)

---

## 1. Convenciones generales y control de acceso

- **Prefijo base:** `/api/v1` (salvo `GET /`, `GET /api/health` y `POST /api/login`).
- **Autenticación:** cabecera `Authorization: Bearer <token>` obligatoria en todas las rutas bajo `/api/v1/...`.
- **Formato de intercambio:** JSON (`Content-Type: application/json`).
- **Respuesta exitosa estándar:**
  ```json
  { "status": "success", "message": "...", "data": {} }
  ```
- **Respuesta de error estándar:**
  ```json
  { "status": "error", "message": "...", "errors": { "campo": "mensaje" } }
  ```
- **Códigos HTTP utilizados:**
  - `200 OK` / `201 Created`: operación exitosa.
  - `400 Bad Request`: JSON malformado o identificador inválido.
  - `401 Unauthorized`: token ausente, inválido, expirado, sesión cerrada o contraseña de confirmación incorrecta.
  - `403 Forbidden`: rol sin permisos, acceso a recurso de otro criadero o intento de editar campos protegidos sin Modo de Corrección.
  - `404 Not Found`: ruta o recurso inexistente.
  - `409 Conflict`: duplicidad o violación de regla de ciclo de vida / integridad en BD.
  - `422 Unprocessable Entity`: error de validación de campos o referencias.
  - `500 Internal Server Error`: error inesperado del servidor o fallo en `pg_dump`.
  - `503 Service Unavailable`: sistema en modo `mantenimiento` o `emergencia` (bloquea módulos operativos de crianza).

### Matriz de permisos por ruta

| Grupo de rutas | `criador` | `administrador` | Restricción adicional |
|---|---|---|---|
| `GET /`, `GET /api/health`, `GET /api/v1`, `POST /api/login` | Pública | Pública | Sin token |
| `GET /api/v1/me`, `POST /api/v1/logout`, `GET /api/v1/modo-operacion/estado` | Sí | Sí | Requiere Bearer |
| `GET /api/v1/wiki/...` | Sí | Sí | Solo lectura |
| `/api/v1/(criador, canarios, solicitudes-correccion, jaulas, parejas, cruces, nidadas, crias, titulos, simulaciones)` | Sí (solo su criadero) | `403 Forbidden` | Bloqueado con `503` si hay modo especial activo |
| `/api/v1/admin/...` | `403 Forbidden` | Sí | Disponible incluso durante mantenimiento o emergencia |

---

## 2. Acceso, sesión y estado operativo

La autenticación utiliza tokens JWT firmados (`HS256`) con vigencia configurable mediante `JWT_EXPIRATION` en `.env` (por defecto `7200` segundos) y clave obligatoria `JWT_SECRET`. El cierre de sesión revoca el hash SHA-256 del token actual en la tabla inmutable `auditoria`.

### 1. Iniciar sesión

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/login` |
| Quién puede usarla | Pública (`criador` o `administrador`) |
| Campos obligatorios | `correo` (texto), `password` (texto) |
| Ejemplo de petición | `{"correo": "criador@canariapp.cl", "password": "********"}` |
| Ejemplo de respuesta | `200` con `data` = `{"token": "<jwt>", "user": {"id_usuario": 2, "nombre": "...", "correo": "...", "rol": "criador"}}` |
| Errores esperados | `400` campos faltantes, `401` credenciales incorrectas, `500` |
| Reglas de validación | El correo se normaliza a minúsculas antes de consultar. Tanto los inicios exitosos (`login`) como los fallidos (`login_fallido`) se registran en `auditoria` sin almacenar jamás la contraseña ingresada (`SEG-003`) |

### 2. Ver sesión actual

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/me` |
| Quién puede usarla | Cualquier usuario autenticado (`criador` o `administrador`) |
| Campos | Sin cuerpo. Requiere `Authorization: Bearer <token>` |
| Ejemplo de respuesta | `200` con `data` = `{"user": {"jti": "...", "iat": 1700000000, "exp": 1700007200, "sub": 2, "correo": "...", "rol": "criador"}}` |
| Errores esperados | `401` token ausente, expirado, alterado o con sesión cerrada, `500` |

### 3. Cerrar sesión

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/logout` |
| Quién puede usarla | Cualquier usuario autenticado (`criador` o `administrador`) |
| Campos | Sin cuerpo. Requiere `Authorization: Bearer <token>` |
| Ejemplo de respuesta | `200` con `data = null` y `message = "Sesión cerrada exitosamente."` |
| Errores esperados | `401` token ausente, inválido, expirado o sesión ya cerrada, `500` |
| Reglas de validación | Registra el hash SHA-256 del token en `auditoria` (`accion = 'logout'`, `entidad = 'sesion'`); no invalida sesiones abiertas en otros dispositivos |

### 4. Consultar estado operativo del sistema

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/modo-operacion/estado` |
| Quién puede usarla | Cualquier usuario autenticado (`criador` o `administrador`) |
| Campos | Sin cuerpo |
| Ejemplo de respuesta | `200` con `data` = `{"estado": "normal", "activo": false, "detalle": null}` (o `"estado": "mantenimiento"` / `"emergencia"` con `detalle`) |
| Errores esperados | `401`, `500` |
| Reglas de validación | Permite al frontend mostrar avisos preventivos antes de intentar operaciones de crianza |

*(Rutas auxiliares públicas disponibles: `GET /`, `GET /api/health` y `GET /api/v1`).*

---

## 3. Perfil del criador

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
| Quién puede usarla | Criador autenticado (`administrador` recibe `403`) |
| Campos | Sin cuerpo |
| Ejemplo de respuesta | `200` con `data` = objeto `criador` |
| Errores esperados | `401`, `403`, `404` usuario sin perfil de criador asociado, `500`, `503` |
| Reglas de validación | Obtiene `id_usuario` directamente del claim `sub` del token JWT |

### 2. Actualizar contraseña del perfil propio

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT /api/v1/criador/perfil` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `password` (texto, mínimo 8 caracteres) |
| Ejemplo de petición | `{"password": "NuevaPassword123"}` |
| Ejemplo de respuesta | `200` con `data` = objeto `criador` |
| Errores esperados | `400` JSON inválido o intento de enviar `numero_socio`, `401`, `403`, `404`, `422` contraseña faltante o menor a 8 caracteres, `500`, `503` |
| Reglas de validación | El criador solo puede actualizar su contraseña; `numero_socio` no es modificable desde este endpoint |

---

## 4. Módulo de crianza (rol `criador`)

Todas las rutas de esta sección están restringidas exclusivamente al rol `criador` (el rol `administrador` recibe `403 Forbidden`), quedan aisladas al `id_criador` del usuario autenticado y devuelven `503 Service Unavailable` si existe un modo `mantenimiento` o `emergencia` activo.

---

### 4.1 Canarios

El ejemplar se identifica por el **anillo completo**: número de anillo (1 a 6 dígitos), sigla del club, número de socio (1 a 5 dígitos) y temporada (año de 4 dígitos, no mayor al año actual). La combinación es única en todo el sistema, sin importar el criadero; la BD compara los números como enteros (`0005` y `5` son el mismo anillo).

En el esquema v7.1 **no existen** `nombre`, `fecha_nacimiento`, `disponibilidad`, `id_color` ni tabla `color`. `id_canario`, `id_criador`, `fecha_registro` y `requiere_revision` no se aceptan en el cuerpo[cite: 5, 13, 15].

#### Objeto `canario`

| Campo | Tipo | Origen |
|---|---|---|
| `id_canario` | entero | `canario.id_canario` |
| `anillo` | texto (1–6 dígitos) | `canario.anillo` |
| `id_club` | entero | `canario.id_club` |
| `club_sigla` | texto | `club.sigla` |
| `numero_socio` | texto (1–5 dígitos) | `canario.numero_socio` |
| `temporada` | entero | `canario.temporada` |
| `sexo` | `"M"`, `"H"` o `null` (en cría pendiente) | `canario.sexo` |
| `id_variedad` | entero o `null` (en cría pendiente) | `canario.id_variedad` |
| `variedad_nombre` | texto o `null` | `variedad.nombre` |
| `id_criador` | entero | `canario.id_criador` |
| `criador_nombre` | texto | `usuario.nombre` |
| `fecha_registro` | fecha y hora | `canario.fecha_registro` |
| `requiere_revision` | booleano | `canario.requiere_revision` (calculado por `trg_validar_sexo_variedad`)[cite: 5] |

#### 1. Listar canarios

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/canarios` |
| Quién puede usarla | Criador autenticado (solo ejemplares de su criadero) |
| Filtros opcionales | `buscar` (coincidencia parcial en `anillo` o `numero_socio`), `id_club`, `id_variedad`, `temporada` |
| Ejemplo de petición | `GET /api/v1/canarios?buscar=2901&id_club=4&temporada=2026` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `canario` |
| Errores esperados | `401`, `403`, `500`, `503` |

#### 2. Ver detalle de un canario

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/canarios/{id}` |
| Quién puede usarla | Criador dueño del canario |
| Campos | `{id}` entero positivo (`id_canario`) |
| Ejemplo de respuesta | `200` con `data` = objeto `canario` |
| Errores esperados | `400` ID inválido, `401`, `403` canario ajeno o rol no autorizado, `404` inexistente, `503` |

#### 3. Consultar ascendencia (pedigrí) de un canario

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/canarios/{id}/ascendencia` |
| Quién puede usarla | Criador dueño del canario |
| Parámetros | `{id}` entero positivo (`id_canario`). Query opcional: `generaciones` (entero `1` a `6`, por defecto `4`) |
| Ejemplo de petición | `GET /api/v1/canarios/24/ascendencia?generaciones=3` |
| Ejemplo de respuesta | `200` con `data` = `{"generaciones_solicitadas": 3, "generaciones_encontradas": 2, "total_ejemplares_arbol": 5, "arbol": {...}}`[cite: 13] |
| Errores esperados | `400` ID o `generaciones` fuera de rango, `401`, `403` ejemplar ajeno, `404` inexistente, `500`, `503` |
| Reglas de validación | Recorre recursivamente `cria -> nidada -> cruce -> pareja` (`id_macho` e `id_hembra`). Si un ancestro no tiene fila en `cria`, se marca `"es_fundador": true` con `"padre": null` y `"madre": null`[cite: 13] |

#### 4. Crear canario adulto/sexado

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/canarios` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `anillo`, `id_club`, `numero_socio`, `temporada`, `sexo`, `id_variedad`[cite: 15] |
| Ejemplo de petición | `{"anillo": "2901", "id_club": 4, "numero_socio": "456", "temporada": 2026, "sexo": "M", "id_variedad": 12}` |
| Ejemplo de respuesta | `201` con `data` = objeto `canario` creado |
| Errores esperados | `400`, `401`, `403`, `409` anillo no disponible, `422` validación o referencia inexistente, `503` |
| Reglas de validación | `id_criador` se toma del usuario autenticado y `temporada` no puede superar el año actual. Para registrar crías con `sexo` o `id_variedad` pendientes (`null`), utilizar `POST /api/v1/crias` (`RF019`, `RF020`) |

#### 5. Actualizar canario (modo estándar y Modo de Corrección `SRS-RF031` / `SRS-RF033`)

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT` o `PATCH /api/v1/canarios/{id}` |
| Quién puede usarla | Criador dueño del canario |
| Campos editables (modo estándar) | `id_club`, `numero_socio`, `temporada` (`<=` año actual), `id_variedad` (y `sexo` solo si estaba en `null` por ser cría pendiente, `RF020`)[cite: 13] |
| Activación de Modo de Corrección | Cabecera `X-Correction-Mode: true` o `"modo_correccion": true` en el cuerpo[cite: 15] |
| Campos obligatorios en Modo de Corrección | `id_solicitud` (entero positivo de una solicitud en estado `"aprobada"` del mismo ejemplar), `password` (contraseña actual del criador, `RF031`), `motivo` (máx. 500 caracteres) y **únicamente** el campo autorizado en la solicitud (`sexo` o `id_variedad`). Opcional: `anular_parejas` (booleano)[cite: 13, 15] |
| Ejemplo de corrección | `PATCH /api/v1/canarios/12` con `{"modo_correccion": true, "id_solicitud": 1, "password": "MiPassword123", "sexo": "H", "motivo": "Error de sexaje previo"}` |
| Ejemplo de respuesta | `200` con `data` = objeto `canario` actualizado |
| Errores esperados | `400`, `401` contraseña del criador incorrecta, `403` intento de cambiar `anillo` o `sexo` sin Modo de Corrección, `404`, `409` solicitud no aprobada/ya cerrada o parejas activas/con cruces sin resolver, `422` intento de editar `anillo` u otro campo no autorizado en la solicitud, `503`[cite: 15] |
| Reglas de validación | El `anillo` no es editable mediante Modo de Corrección. Al guardar, el servidor cierra la solicitud de corrección y registra la auditoría en la misma transacción (`RF033`)[cite: 13, 15] |

#### 6. Eliminar canario

**No existe.** El SRS 1.2 excluye la eliminación de registros y la BD v7.1 no concede `DELETE`.

---

### 4.2 Solicitudes de corrección (criador)

Permite al criador solicitar formalmente al administrador la corrección de `sexo` o `variedad` de un ejemplar propio (`SRS-RF033`). Solo puede existir una solicitud `pendiente` a la vez por ejemplar (`uq_solicitud_pendiente`).

#### Objeto `solicitud_correccion`

| Campo | Tipo | Origen |
|---|---|---|
| `id_solicitud` | entero | `solicitud_correccion.id_solicitud` |
| `id_canario` | entero | `solicitud_correccion.id_canario` |
| `anillo` | texto | `canario.anillo` |
| `club_sigla` | texto | `club.sigla` |
| `numero_socio` | texto | `canario.numero_socio` |
| `temporada` | entero | `canario.temporada` |
| `sexo_actual` | `"M"`, `"H"` o `null` | `canario.sexo` |
| `id_variedad_actual` | entero o `null` | `canario.id_variedad` |
| `variedad_actual_nombre` | texto o `null` | `variedad.nombre` |
| `id_criador` | entero | `solicitud_correccion.id_criador` |
| `criador_nombre` | texto | `usuario.nombre` |
| `dato_a_corregir` | `"sexo"` o `"variedad"` | `solicitud_correccion.dato_a_corregir` |
| `motivo` | texto | `solicitud_correccion.motivo` |
| `estado` | `"pendiente"`, `"aprobada"`, `"rechazada"` o `"cancelada"` | `solicitud_correccion.estado` |
| `fecha_solicitud` | fecha y hora | `solicitud_correccion.fecha_solicitud` |
| `fecha_cierre` | fecha y hora o `null` | `solicitud_correccion.fecha_cierre` |

#### 1. Listar mis solicitudes de corrección

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/solicitudes-correccion` |
| Quién puede usarla | Criador autenticado (solo solicitudes de su criadero) |
| Filtros opcionales | `estado`, `dato_a_corregir`, `id_canario` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `solicitud_correccion` |
| Errores esperados | `401`, `403`, `500`, `503` |

#### 2. Ver detalle de una solicitud propia

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/solicitudes-correccion/{id}` |
| Quién puede usarla | Criador solicitante |
| Campos | `{id}` entero positivo (`id_solicitud`) |
| Ejemplo de respuesta | `200` con `data` = objeto `solicitud_correccion` |
| Errores esperados | `400`, `401`, `403` solicitud ajena, `404`, `503` |

#### 3. Crear solicitud de corrección

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/solicitudes-correccion` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `id_canario` (entero positivo), `dato_a_corregir` (`"sexo"` o `"variedad"`), `motivo` (texto, 1–1000 caracteres) |
| Ejemplo de petición | `{"id_canario": 12, "dato_a_corregir": "sexo", "motivo": "El ejemplar puso huevo; fue registrado como macho"}` |
| Ejemplo de respuesta | `201` con `data` = objeto `solicitud_correccion` en estado `"pendiente"` |
| Errores esperados | `400`, `401`, `403` canario de otro criadero, `404` canario inexistente, `409` ya existe una solicitud pendiente para ese ejemplar, `422` validación, `503` |

#### 4. Cancelar solicitud pendiente

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PATCH /api/v1/solicitudes-correccion/{id}/cancelar` |
| Quién puede usarla | Criador solicitante |
| Campos opcionales | `motivo` (texto explicativo de la cancelación) |
| Ejemplo de respuesta | `200` con `data` = objeto `solicitud_correccion` en estado `"cancelada"` y `fecha_cierre` asignada |
| Errores esperados | `400`, `401`, `403`, `404`, `409` la solicitud ya no está en estado `"pendiente"`, `503` |

---

### 4.3 Jaulas

La gestión de jaulas queda limitada al criadero del usuario autenticado (StRS-004, SEG-001). No se implementan `PUT`, `PATCH` ni `DELETE`; la ocupación se libera al finalizar o anular la pareja asignada (`SRS-RF017`).

#### Objeto `jaula`

| Campo | Tipo | Origen |
|---|---|---|
| `id_jaula` | entero | `jaula.id_jaula` |
| `numero_jaula` | entero | `jaula.numero_jaula` |
| `id_criador` | entero | `jaula.id_criador` |
| `ocupada` | booleano | Calculado: existe una pareja con `estado = 'activa'` en esa jaula |

#### 1. Listar jaulas

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/jaulas` |
| Quién puede usarla | Criador autenticado (solo jaulas de su criadero) |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `jaula` ordenados por `numero_jaula` |
| Errores esperados | `401`, `403`, `500`, `503` |

#### 2. Ver detalle de una jaula

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/jaulas/{id}` |
| Quién puede usarla | Criador dueño de la jaula |
| Campos | `{id}` entero positivo (`id_jaula`) |
| Ejemplo de respuesta | `200` con `data` = objeto `jaula` |
| Errores esperados | `400`, `401`, `403`, `404` jaula inexistente o ajena, `503` |

#### 3. Registrar jaula

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/jaulas` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `numero_jaula` (entero entre `1` y `2147483647`) |
| Ejemplo de petición | `{"numero_jaula": 3}` |
| Ejemplo de respuesta | `201` con `data` = objeto `jaula` creado |
| Errores esperados | `400`, `401`, `403`, `409` número de jaula duplicado en el criadero (`uq_jaula_criador`), `422` validación, `503` |

---

### 4.4 Parejas

Asocia un macho (`sexo = 'M'`) y una hembra (`sexo = 'H'`) del mismo criadero con una jaula (`id_jaula`) del mismo criadero. Toda pareja nace en estado `"activa"` con `fecha_fin = null`; una hembra y una jaula admiten solo una pareja activa a la vez (`uq_pareja_hembra_activa`, `uq_pareja_jaula_activa`)[cite: 5].

#### Objeto `pareja`

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

#### 1. Listar parejas

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/parejas` |
| Quién puede usarla | Criador autenticado (solo parejas de su criadero) |
| Filtros opcionales | `estado`, `id_macho`, `id_hembra`, `id_jaula` |
| Ejemplo de petición | `GET /api/v1/parejas?estado=activa` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `pareja` |
| Errores esperados | `401`, `403`, `404`, `500`, `503` |

#### 2. Ver detalle de una pareja

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/parejas/{id}` |
| Quién puede usarla | Criador dueño de la pareja |
| Campos | `{id}` entero positivo (`id_pareja`) |
| Ejemplo de respuesta | `200` con `data` = objeto `pareja` |
| Errores esperados | `400`, `401`, `403` pareja ajena, `404`, `503` |

#### 3. Crear pareja

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/parejas` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `id_macho`, `id_hembra`, `id_jaula`. Opcional: `fecha_formacion` (`YYYY-MM-DD`, por defecto fecha actual) |
| Ejemplo de petición | `{"id_macho": 10, "id_hembra": 14, "id_jaula": 2, "fecha_formacion": "2026-11-22"}` |
| Ejemplo de respuesta | `201` con `data` = objeto `pareja` creado en estado `"activa"` |
| Errores esperados | `400`, `401`, `403`, `409` `"La jaula ya está ocupada por una pareja activa."` o `"La hembra ya tiene pareja activa."`[cite: 16], `422` validación o referencia ajena/inexistente, `503` |

#### 4. Actualizar pareja (modo estándar y Modo de Corrección `SRS-RF031`)

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT` o `PATCH /api/v1/parejas/{id}` |
| Quién puede usarla | Criador dueño de la pareja |
| Campos editables (modo estándar) | `id_jaula`, `estado` (`"activa"`, `"finalizada"`, `"anulada"`), `fecha_fin` (`YYYY-MM-DD`) |
| Campos protegidos (Modo de Corrección) | `id_macho`, `id_hembra`. Requiere cabecera `X-Correction-Mode: true` o `"modo_correccion": true` en el cuerpo |
| Metadatos de corrección | `motivo` (obligatorio en Modo de Corrección, máx. 500 caracteres), `id_solicitud` (opcional, entero positivo) |
| Ejemplo estándar | `PATCH /api/v1/parejas/3` con `{"estado": "finalizada"}` |
| Ejemplo de corrección | `PATCH /api/v1/parejas/3` con `{"modo_correccion": true, "id_macho": 18, "motivo": "Reasignación por error de sexaje en ejemplar #12"}` |
| Ejemplo de respuesta | `200` con `data` = objeto `pareja` actualizado |
| Errores esperados | `400`, `401`, `403` intento de cambiar `id_macho` o `id_hembra` sin Modo de Corrección, `404`, `409` jaula ocupada, hembra con pareja activa, intento de anular pareja con cruces (`fn_estado_pareja`) o consanguinidad directa[cite: 11, 16], `422` validación, `503` |
| Reglas de validación | Al pasar a `"finalizada"` o `"anulada"` se libera la jaula y se exige `fecha_fin >= fecha_formacion` (si se omite `fecha_fin`, se asigna hoy en `APP_TIMEZONE`). Una pareja cerrada no vuelve a abrirse y una pareja con cruces no puede anularse |

#### 5. Eliminar pareja

**No existe.** El SRS 1.2 excluye la eliminación física; las parejas se finalizan o anulan según su ciclo de vida.

---

### 4.5 Cruces

Un cruce es el apareamiento fechado de una pareja (`SRS-RF016`). Una pareja admite varios cruces mientras esté `"activa"`. `id_pareja` es inmutable (`SQL-01`); no existen `PUT`, `PATCH` ni `DELETE`.

#### Objeto `cruce`

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

#### 1. Listar cruces

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/cruces` |
| Quién puede usarla | Criador autenticado (solo cruces de su criadero) |
| Filtros opcionales | `id_pareja`, `fecha_cruce` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `cruce` |
| Errores esperados | `401`, `403`, `404`, `500`, `503` |

#### 2. Listar cruces de una pareja

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/cruces/pareja/{id}` |
| Quién puede usarla | Criador dueño de la pareja |
| Campos | `{id}` entero positivo (`id_pareja`) |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `cruce` de esa pareja |
| Errores esperados | `400`, `401`, `403`, `404`, `500`, `503` |

#### 3. Ver detalle de un cruce

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/cruces/{id}` |
| Quién puede usarla | Criador dueño del cruce |
| Campos | `{id}` entero positivo (`id_cruce`) |
| Ejemplo de respuesta | `200` con `data` = objeto `cruce` |
| Errores esperados | `400`, `401`, `403`, `404`, `500`, `503` |

#### 4. Registrar cruce

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/cruces` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `id_pareja` (entero positivo), `fecha_cruce` (`YYYY-MM-DD`, no futura) |
| Ejemplo de petición | `{"id_pareja": 3, "fecha_cruce": "2026-11-22"}` |
| Ejemplo de respuesta | `201` con `data` = objeto `cruce` creado |
| Errores esperados | `400`, `401`, `403`, `404` pareja no encontrada en el criadero, `409` pareja no activa, `422` validación, `503` |

---

### 4.6 Nidadas

Cada nidada pertenece a un cruce (`SRS-RF018`). `id_cruce` es inmutable (`trg_nidada_cruce_inmutable`); no existen `PUT`, `PATCH` ni `DELETE`.

#### Objeto `nidada`

| Campo | Tipo | Origen |
|---|---|---|
| `id_nidada` | entero | `nidada.id_nidada` |
| `id_cruce` | entero | `nidada.id_cruce` |
| `fecha_nacimiento` | fecha (`YYYY-MM-DD`) | `nidada.fecha_nacimiento` |
| `fecha_cruce` | fecha (`YYYY-MM-DD`) | `cruce.fecha_cruce` |
| `id_pareja` | entero | `pareja.id_pareja` |
| `anillo_macho` | texto | `canario.anillo` (macho) |
| `anillo_hembra` | texto | `canario.anillo` (hembra) |

#### 1. Listar nidadas

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/nidadas` |
| Quién puede usarla | Criador autenticado |
| Filtros opcionales | `id_cruce`, `fecha_nacimiento` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `nidada` ordenados por `fecha_nacimiento` descendente |
| Errores esperados | `401`, `403`, `500`, `503` |

#### 2. Listar nidadas de un cruce

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/nidadas/cruce/{id}` |
| Quién puede usarla | Criador dueño del cruce |
| Campos | `{id}` entero positivo (`id_cruce`) |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `nidada` del cruce |
| Errores esperados | `400`, `401`, `403`, `500`, `503` |

#### 3. Ver detalle de una nidada

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/nidadas/{id}` |
| Quién puede usarla | Criador dueño de la nidada |
| Campos | `{id}` entero positivo (`id_nidada`) |
| Ejemplo de respuesta | `200` con `data` = objeto `nidada` |
| Errores esperados | `400`, `401`, `403`, `404`, `500`, `503` |

#### 4. Registrar nidada

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/nidadas` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `id_cruce` (entero positivo), `fecha_nacimiento` (`YYYY-MM-DD`, `>= fecha_cruce` y no futura) |
| Ejemplo de petición | `{"id_cruce": 12, "fecha_nacimiento": "2026-11-20"}` |
| Ejemplo de respuesta | `201` con `data` = objeto `nidada` creado |
| Errores esperados | `400`, `401`, `403`, `404` cruce inexistente o ajeno, `422` validación, `503` |

---

### 4.7 Crías

Vincula una `nidada` con un ejemplar en `canario` y, opcionalmente, con una mutación (`factor_genetico`). Para cumplir el trigger diferido `trg_validar_pendiente_cria` de PostgreSQL v7.1 (`RF019`, `RF020`), `POST /api/v1/crias` permite crear **en una sola transacción** tanto el ejemplar en `canario` (con `sexo` e `id_variedad` opcionales / `null`) como su registro en `cria`[cite: 5, 12, 14].

`es_portadora` lo calcula la BD (`factor_genetico IS NOT NULL`). `id_nidada` e `id_canario` son inmutables tras el registro; no existe `DELETE`[cite: 5].

#### Objeto `cria`

| Campo | Tipo | Origen |
|---|---|---|
| `id_cria` | entero | `cria.id_cria` |
| `id_nidada` | entero | `cria.id_nidada` |
| `id_canario` | entero | `cria.id_canario` |
| `factor_genetico` | entero o `null` | `cria.factor_genetico` (`id_mutacion` o `null`) |
| `es_portadora` | booleano | `cria.es_portadora` (calculado por la BD) |
| `reservada` | booleano | `cria.reservada` |
| `id_criador` | entero | `pareja.id_criador` |
| `id_pareja` | entero | `pareja.id_pareja` |
| `id_macho` | entero | `pareja.id_macho` |
| `anillo_macho` | texto | `canario.anillo` (padre) |
| `id_hembra` | entero | `pareja.id_hembra` |
| `anillo_hembra` | texto | `canario.anillo` (madre) |
| `id_cruce` | entero | `nidada.id_cruce` |
| `fecha_nacimiento` | fecha (`YYYY-MM-DD`) | `nidada.fecha_nacimiento` |
| `anillo` | texto | `canario.anillo` (cría) |
| `temporada` | entero | `canario.temporada` |
| `sexo` | `"M"`, `"H"` o `null` | `canario.sexo` |
| `id_variedad` | entero o `null` | `canario.id_variedad` |
| `mutacion_nombre` | texto o `null` | `mutacion.nombre` |

#### 1. Listar crías

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/crias` |
| Quién puede usarla | Criador autenticado (solo crías de su criadero) |
| Filtros opcionales | `id_nidada`, `id_canario`, `factor_genetico`, `reservada` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `cria` |
| Errores esperados | `401`, `403`, `404`, `500`, `503` |

#### 2. Listar crías de una nidada

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/crias/nidada/{id}` |
| Quién puede usarla | Criador dueño de la nidada |
| Campos | `{id}` entero positivo (`id_nidada`) |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `cria` de esa nidada |
| Errores esperados | `400`, `401`, `403`, `404`, `500`, `503` |

#### 3. Ver detalle de una cría

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/crias/{id}` |
| Quién puede usarla | Criador dueño de la cría |
| Campos | `{id}` entero positivo (`id_cria`) |
| Ejemplo de respuesta | `200` con `data` = objeto `cria` (incluye `id_macho`, `anillo_macho`, `id_hembra` y `anillo_hembra`) |
| Errores esperados | `400`, `401`, `403`, `404`, `500`, `503` |

#### 4. Consultar ascendencia (pedigrí) de una cría

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/crias/{id}/ascendencia` |
| Quién puede usarla | Criador dueño de la cría |
| Parámetros | `{id}` entero positivo (`id_cria`). Query opcional: `generaciones` (entero `1` a `6`, por defecto `4`) |
| Ejemplo de petición | `GET /api/v1/crias/4/ascendencia?generaciones=4` |
| Ejemplo de respuesta | `200` con `data` = `{"cria": {...}, "ascendencia": {"generaciones_solicitadas": 4, "generaciones_encontradas": 2, "total_ejemplares_arbol": 5, "arbol": {...}}}` |
| Errores esperados | `400` ID o `generaciones` fuera de rango, `401`, `403`, `404` cría inexistente o ajena, `500`, `503` |

#### 5. Registrar cría (alta conjunta transaccional `RF019` / `RF020`)

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/crias` |
| Quién puede usarla | Criador autenticado |
| Modalidad 1 — Alta conjunta (recomendada) | Obligatorios: `id_nidada`, `anillo` (1–6 dígitos), `id_club`, `numero_socio` (1–5 dígitos), `temporada` (`<=` año actual). Opcionales: `sexo` (`"M"`, `"H"` o `null`), `id_variedad` (entero positivo o `null`), `factor_genetico` (entero positivo o `null`), `reservada` (booleano, por defecto `false`)[cite: 14] |
| Modalidad 2 — Ejemplar existente | Obligatorios: `id_nidada`, `id_canario`. Opcionales: `factor_genetico`, `reservada`[cite: 14] |
| Ejemplo alta sin sexo ni variedad | `{"id_nidada": 8, "anillo": "0142", "id_club": 4, "numero_socio": "456", "temporada": 2026, "sexo": null, "id_variedad": null, "reservada": true}` |
| Ejemplo con ejemplar existente | `{"id_nidada": 8, "id_canario": 25, "factor_genetico": 1, "reservada": true}` |
| Ejemplo de respuesta | `201` con `data` = objeto `cria` creado |
| Errores esperados | `400`, `401`, `403`, `404` nidada inexistente o ajena, `409` anillo ya ocupado o canario ya registrado como cría, `422` validación o referencia inválida, `503`[cite: 14] |

#### 6. Actualizar cría

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT` o `PATCH /api/v1/crias/{id}` |
| Quién puede usarla | Criador dueño de la cría |
| Campos opcionales | `factor_genetico` (entero positivo o `null`), `reservada` (booleano)[cite: 14] |
| Campos no permitidos | `id_cria`, `id_criador`, `es_portadora`, `id_nidada`, `id_canario`[cite: 14] |
| Ejemplo de petición | `PATCH /api/v1/crias/4` con `{"reservada": true, "factor_genetico": null}` |
| Ejemplo de respuesta | `200` con `data` = objeto `cria` actualizado |
| Errores esperados | `400`, `401`, `403`, `404`, `409`, `422`, `503` |

---

### 4.8 Títulos de competencia

Registra logros de competencia sobre ejemplares del criadero (`SRS-RF023`, `SRS-RF024`). `id_canario` es inmutable tras el registro (`trg_titulo_canario_inmutable`); no existe `DELETE`.

#### Objeto `titulo`

| Campo | Tipo | Origen |
|---|---|---|
| `id_titulo` | entero | `titulo.id_titulo` |
| `id_canario` | entero | `titulo.id_canario` |
| `nombre` | texto (1–100 caracteres) | `titulo.nombre` |
| `fecha` | fecha (`YYYY-MM-DD`) | `titulo.fecha` |
| `anillo` | texto | `canario.anillo` |
| `numero_socio` | texto | `canario.numero_socio` |
| `temporada` | entero | `canario.temporada` |
| `sexo` | `"M"`, `"H"` o `null` | `canario.sexo` |
| `id_club` | entero | `club.id_club` |
| `club_sigla` | texto | `club.sigla` |
| `id_criador` | entero | `canario.id_criador` |

#### 1. Listar títulos

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/titulos` |
| Quién puede usarla | Criador autenticado (solo títulos de su criadero) |
| Filtros opcionales | `id_canario`, `nombre` (coincidencia parcial), `fecha` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `titulo` ordenados por fecha descendente |
| Errores esperados | `401`, `403`, `404`, `500`, `503` |

#### 2. Listar títulos de un ejemplar

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/titulos/canario/{id}` |
| Quién puede usarla | Criador dueño del ejemplar |
| Campos | `{id}` entero positivo (`id_canario`) |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `titulo` del ejemplar |
| Errores esperados | `400`, `401`, `403`, `500`, `503` |

#### 3. Ver detalle de un título

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/titulos/{id}` |
| Quién puede usarla | Criador dueño del título |
| Campos | `{id}` entero positivo (`id_titulo`) |
| Ejemplo de respuesta | `200` con `data` = objeto `titulo` |
| Errores esperados | `400`, `401`, `403`, `404`, `500`, `503` |

#### 4. Registrar título

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/titulos` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `nombre` (1–100 caracteres), `fecha` (`YYYY-MM-DD` no futura) y el ejemplar mediante `id_canario` **o** mediante el anillo completo (`anillo`, `id_club`, `numero_socio`, `temporada`) |
| Ejemplo de petición | `{"id_canario": 12, "nombre": "Campeón Nacional", "fecha": "2026-10-15"}` |
| Ejemplo con anillo | `{"anillo": "2901", "id_club": 4, "numero_socio": "456", "temporada": 2026, "nombre": "Campeón Nacional", "fecha": "2026-10-15"}` |
| Ejemplo de respuesta | `201` con `data` = objeto `titulo` creado |
| Errores esperados | `400`, `401`, `403`, `409` título duplicado `(id_canario, nombre, fecha)`, `422` validación o ejemplar ajeno, `503` |

#### 5. Actualizar título

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT` o `PATCH /api/v1/titulos/{id}` |
| Quién puede usarla | Criador dueño del título |
| Campos opcionales | `nombre`, `fecha` |
| Campos no permitidos | `id_titulo`, `id_criador`, `id_canario`, `anillo`, `id_club`, `numero_socio`, `temporada` |
| Ejemplo de respuesta | `200` con `data` = objeto `titulo` actualizado |
| Errores esperados | `400`, `401`, `403`, `404`, `409` duplicado, `422`, `503` |

#### 6. Consultar descendencia de un ejemplar ganador

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/titulos/canario/{id}/descendencia` |
| Quién puede usarla | Criador dueño del ejemplar |
| Campos | `{id}` entero positivo (`id_canario`) |
| Ejemplo de respuesta | `200` con `data` = `{"id_canario": 12, "tiene_titulos": true, "grupos": [...]}` |
| Errores esperados | `400`, `401`, `403`, `404` ejemplar ajeno o inexistente, `422` ejemplar sin sexo registrado, `503` |
| Reglas de validación | `SRS-RF024`: agrupa las crías por el progenitor opuesto con el que se cruzó. Si no tiene títulos o crías, devuelve arreglos vacíos con `200 OK` |

---

### 4.9 Simulación genética

Calcula y almacena el historial de simulaciones mendelianas por criadero (`SRS-RF025`, `DAT-006`). No se implementan `PUT`, `PATCH` ni `DELETE`.

#### Objeto `simulacion`

| Campo | Tipo | Origen |
|---|---|---|
| `id_simulacion` | entero | `simulacion.id_simulacion` |
| `id_criador` | entero | `simulacion.id_criador` |
| `id_macho` | entero | `simulacion.id_macho` |
| `anillo_macho` | texto | `canario.anillo` (macho) |
| `id_hembra` | entero | `simulacion.id_hembra` |
| `anillo_hembra` | texto | `canario.anillo` (hembra) |
| `id_mutacion` | entero | `simulacion.id_mutacion` |
| `mutacion_nombre` | texto | `mutacion.nombre` |
| `tipo_herencia` | `"autosómica recesiva"` o `"ligada al sexo recesiva"` | `mutacion.tipo_herencia` |
| `genotipo_macho` | `"visual"`, `"portador"` o `"sin factor"` | `simulacion.genotipo_macho` |
| `genotipo_hembra` | `"visual"`, `"portador"` o `"sin factor"` | `simulacion.genotipo_hembra` |
| `fecha` | fecha y hora | `simulacion.fecha` |
| `resultados` | arreglo de objetos | Filas en `simulacion_resultado` (`sexo_cria`, `genotipo_resultado`, `probabilidad`) |

#### 1. Listar simulaciones

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/simulaciones` |
| Quién puede usarla | Criador autenticado (solo historial de su criadero) |
| Filtros opcionales | `id_mutacion`, `id_macho`, `id_hembra` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `simulacion` |
| Errores esperados | `401`, `403`, `404`, `500`, `503` |

#### 2. Ver detalle de una simulación

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/simulaciones/{id}` |
| Quién puede usarla | Criador dueño de la simulación |
| Campos | `{id}` entero positivo (`id_simulacion`) |
| Ejemplo de respuesta | `200` con `data` = objeto `simulacion` con su arreglo `resultados` |
| Errores esperados | `400`, `401`, `403`, `404`, `500`, `503` |

#### 3. Ejecutar y registrar simulación

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/simulaciones` |
| Quién puede usarla | Criador autenticado |
| Campos obligatorios | `id_macho`, `id_hembra`, `id_mutacion`, `genotipo_macho`, `genotipo_hembra` |
| Ejemplo de petición | `{"id_macho": 10, "id_hembra": 14, "id_mutacion": 1, "genotipo_macho": "portador", "genotipo_hembra": "sin factor"}` |
| Ejemplo de respuesta | `201` con `data` = objeto `simulacion` creado con `resultados` |
| Errores esperados | `400`, `401`, `403`, `404`, `409`, `422` validación, sexo incorrecto o hembra `"portador"` en mutación ligada al sexo (`trg_validar_simulacion`), `503` |

---

## 5. Catálogos oficiales (Wiki)

Endpoints de **solo lectura** disponibles para cualquier usuario autenticado (`criador` o `administrador`). No aceptan `POST`, `PUT`, `PATCH` ni `DELETE`.

| Método y ruta | Respuesta | Descripción |
|---|---|---|
| `GET /api/v1/wiki` | `data` con `clubes`, `variedades`, `mutaciones` | Paquete completo para inicializar desplegables |
| `GET /api/v1/wiki/clubes` | lista de clubes | Siglas oficiales disponibles (`SRS-RF002`) |
| `GET /api/v1/wiki/variedades` | lista de variedades | Nomenclador oficial; admite filtros (`SRS-RF007`) |
| `GET /api/v1/wiki/variedades/codigo/{codigo}` | una variedad | Búsqueda exacta por código (`SRS-RF008`) |
| `GET /api/v1/wiki/variedades/{id}` | una variedad | Detalle por `id_variedad` |
| `GET /api/v1/wiki/mutaciones` | lista de mutaciones | Catálogo genético para simulador (`SRS-RF025`) |

**Filtros opcionales en `GET /api/v1/wiki/variedades`:**
- `buscar`: coincidencia parcial (`ILIKE`) en `codigo` o `nombre` (máx. 150 caracteres).
- `codigo`: código exacto del nomenclador (máx. 10 caracteres).
- `tipo`: `"CC"` (color) o `"CP"` (forma y postura).
- `sexo`: `"M"` u `"H"` (derivado del nombre de la variedad).

---

## 6. Módulo de administración (rol `administrador`)

Todas las rutas bajo `/api/v1/admin/...` requieren autenticación y `rol = "administrador"` (el rol `criador` recibe `403 Forbidden`). Estas rutas permanecen operativas incluso cuando el sistema está en modo `mantenimiento` o `emergencia`.

---

### 6.1 Gestión de criadores

#### 1. Listar criadores

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/criadores` |
| Quién puede usarla | Administrador |
| Filtros opcionales | `buscar` (coincidencia parcial `ILIKE` en `nombre`, `numero_socio` o `correo`) |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `criador` |
| Errores esperados | `401`, `403`, `500` |

#### 2. Ver detalle de un criador

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/criadores/{id}` |
| Quién puede usarla | Administrador |
| Campos | `{id}` entero positivo (`id_criador`) |
| Ejemplo de respuesta | `200` con `data` = objeto `criador` |
| Errores esperados | `400`, `401`, `403`, `404`, `500` |

#### 3. Crear criador

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/admin/criadores` *(alias compatible: `POST /api/v1/admin/register`)* |
| Quién puede usarla | Administrador |
| Campos obligatorios | `nombre`, `correo`, `password`, `numero_socio` |
| Ejemplo de petición | `{"nombre": "Carlos Mendoza", "correo": "carlos.mendoza@canariapp.cl", "password": "Password123", "numero_socio": "456"}` |
| Ejemplo de respuesta | `201` con `data` = objeto `criador` creado *(en `/admin/register` devuelve `{"user": {...}}`)* |
| Errores esperados | `400`, `401`, `403`, `409` correo o número de socio duplicado, `422` validación, `500` |
| Reglas de validación | Crea usuario con `rol = "criador"` y fila en `criador` dentro de una transacción |

#### 4. Actualizar criador

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PUT /api/v1/admin/criadores/{id}` |
| Quién puede usarla | Administrador |
| Campos opcionales | `nombre`, `correo`, `numero_socio`, `password` (mínimo 8 caracteres si se envía) |
| Ejemplo de respuesta | `200` con `data` = objeto `criador` actualizado |
| Errores esperados | `400`, `401`, `403`, `404`, `409` correo o número de socio duplicado, `422`, `500` |

#### 5. Eliminar criador

**No existe.** El esquema v7.1 no concede permiso `DELETE` sobre `usuario` ni `criador` y los roles son inmutables (`trg_usuario_rol_inmutable`).

---

### 6.2 Resolución de solicitudes de corrección

Permite al administrador revisar y dictaminar las solicitudes enviadas por los criadores (`SRS-RF033`).

#### 1. Listar todas las solicitudes de corrección

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/solicitudes-correccion` |
| Quién puede usarla | Administrador |
| Filtros opcionales | `estado`, `dato_a_corregir`, `id_canario`, `id_criador` |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `solicitud_correccion` |
| Errores esperados | `401`, `403`, `500` |

#### 2. Ver detalle de una solicitud

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/solicitudes-correccion/{id}` |
| Quién puede usarla | Administrador |
| Campos | `{id}` entero positivo (`id_solicitud`) |
| Ejemplo de respuesta | `200` con `data` = objeto `solicitud_correccion` |
| Errores esperados | `400`, `401`, `403`, `404`, `500` |

#### 3. Aprobar o rechazar una solicitud pendiente

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PATCH /api/v1/admin/solicitudes-correccion/{id}` |
| Quién puede usarla | Administrador |
| Campos obligatorios | `estado` (`"aprobada"` o `"rechazada"`). Opcional: `motivo` (observación administrativa, máx. 1000 caracteres) |
| Ejemplo de petición | `{"estado": "aprobada", "motivo": "Antecedentes verificados, procede corrección"}` |
| Ejemplo de respuesta | `200` con `data` = objeto `solicitud_correccion` con `fecha_cierre` |
| Errores esperados | `400`, `401`, `403`, `404`, `409` la solicitud no está en estado `"pendiente"`, `422` estado inválido, `500` |

---

### 6.3 Modos de operación (`mantenimiento` y `emergencia`)

Controla los estados operativos del sistema (`SRS-RF028`, `DAT-003`). El **modo normal** corresponde a la ausencia de registros con `fecha_desactivacion IS NULL`. Solo puede existir un modo especial activo a la vez (`uq_modo_activo`).

#### Objeto `modo_operacion`

| Campo | Tipo | Origen |
|---|---|---|
| `id_modo` | entero | `modo_operacion.id_modo` |
| `modo` | `"mantenimiento"` o `"emergencia"` | `modo_operacion.modo` |
| `fecha_activacion` | fecha y hora | `modo_operacion.fecha_activacion` |
| `fecha_desactivacion` | fecha y hora o `null` | `modo_operacion.fecha_desactivacion` |
| `activo` | booleano | Calculado (`fecha_desactivacion IS NULL`) |
| `id_usuario` | entero | Administrador que activó el modo |
| `activado_por_nombre` | texto | `usuario.nombre` |
| `id_usuario_cierre` | entero o `null` | Administrador que desactivó el modo |
| `cerrado_por_nombre` | texto o `null` | `usuario.nombre` |
| `diagnostico` | texto o `null` | `modo_operacion.diagnostico` |
| `fecha_diagnostico` | fecha y hora o `null` | `modo_operacion.fecha_diagnostico` |
| `acciones_recuperacion` | texto o `null` | `modo_operacion.acciones_recuperacion` |
| `plazo_diagnostico` | fecha y hora o `null` | Calculado: `fecha_activacion + 4 hours` cuando `modo = 'emergencia'` |

#### 1. Listar historial de modos de operación

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/modo-operacion` |
| Quién puede usarla | Administrador |
| Filtros opcionales | `modo` (`"mantenimiento"` o `"emergencia"`), `activo` (`true` o `false`) |
| Ejemplo de respuesta | `200` con `data` = lista de objetos `modo_operacion` |
| Errores esperados | `401`, `403`, `500` |

#### 2. Consultar modo activo

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/modo-operacion/activo` |
| Quién puede usarla | Administrador |
| Ejemplo de respuesta | `200` con `data` = `{"estado": "normal"|"mantenimiento"|"emergencia", "activo": bool, "detalle": object|null}` |
| Errores esperados | `401`, `403`, `500` |

#### 3. Ver detalle de un modo de operación

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/modo-operacion/{id}` |
| Quién puede usarla | Administrador |
| Campos | `{id}` entero positivo (`id_modo`) |
| Ejemplo de respuesta | `200` con `data` = objeto `modo_operacion` |
| Errores esperados | `400`, `401`, `403`, `404`, `500` |

#### 4. Activar modo `mantenimiento` o `emergencia`

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/admin/modo-operacion` |
| Quién puede usarla | Administrador |
| Campos obligatorios | `modo` (`"mantenimiento"` o `"emergencia"`). Opcionales: `diagnostico`, `motivo` |
| Ejemplo de petición | `{"modo": "mantenimiento", "motivo": "Actualización programada de catálogos oficiales"}` |
| Ejemplo de respuesta | `201` con `data` = objeto `modo_operacion` activo |
| Errores esperados | `400`, `401`, `403`, `409` ya existe un modo especial activo, `422` validación, `500` |

#### 5. Registrar diagnóstico técnico en un modo activo

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PATCH /api/v1/admin/modo-operacion/{id}/diagnostico` |
| Quién puede usarla | Administrador |
| Campos obligatorios | `diagnostico` (texto no vacío). Opcional: `acciones_recuperacion` |
| Ejemplo de petición | `{"diagnostico": "Saturación de pool de conexiones", "acciones_recuperacion": "Reinicio controlado de servicio"}` |
| Ejemplo de respuesta | `200` con `data` = objeto `modo_operacion` con `fecha_diagnostico` actualizada |
| Errores esperados | `400`, `401`, `403`, `404`, `409` modo ya cerrado, `422` diagnóstico vacío, `500` |

#### 6. Desactivar modo especial (volver a modo normal)

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `PATCH /api/v1/admin/modo-operacion/{id}/desactivar` |
| Quién puede usarla | Administrador |
| Campos opcionales | `diagnostico`, `acciones_recuperacion`, `motivo` |
| Ejemplo de petición | `{"motivo": "Operación normal restablecida"}` |
| Ejemplo de respuesta | `200` con `data` = objeto `modo_operacion` cerrado (`activo: false`) |
| Errores esperados | `400`, `401`, `403`, `404`, `409` modo ya cerrado, `422` si es `"emergencia"` y faltan `diagnostico` o `acciones_recuperacion` (`ck_modo_emergencia`), `500` |

---

### 6.4 Auditoría del sistema

Consulta de solo lectura sobre la bitácora inmutable `auditoria` (`SEG-003`, `trg_auditoria_inmutable`).

#### 1. Listar eventos de auditoría (paginado)

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/auditoria` |
| Quién puede usarla | Administrador |
| Filtros opcionales | `id_usuario`, `accion` (`login`, `login_fallido`, `logout`, `insert`, `update`, `correccion`), `entidad`, `id_registro`, `id_criador_solicitante`, `id_solicitud`, `fecha_desde` (`YYYY-MM-DD`), `fecha_hasta` (`YYYY-MM-DD`), `buscar`, `limit` (1–200, por defecto `50`), `offset` (por defecto `0`) |
| Ejemplo de petición | `GET /api/v1/admin/auditoria?entidad=canario&accion=correccion&limit=20&offset=0` |
| Ejemplo de respuesta | `200` con `data` = `{"items": [...], "total": 124, "limit": 20, "offset": 0}` |
| Errores esperados | `401`, `403`, `500` |

#### 2. Ver detalle de un evento de auditoría

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/auditoria/{id}` |
| Quién puede usarla | Administrador |
| Campos | `{id}` entero positivo (`id_auditoria`) |
| Ejemplo de respuesta | `200` con `data` = registro completo con `valor_anterior`, `valor_nuevo`, `motivo` y datos de usuarios |
| Errores esperados | `400`, `401`, `403`, `404`, `500` |

---

### 6.5 Respaldos y rotación

Gestiona la tabla `respaldo` conservando únicamente los **7 respaldos más recientes** (`DAT-003`)[cite: 17]. El sistema ejecuta además un respaldo automático cada **2 días (48 horas)** (`id_usuario = null`) tanto mediante el script CLI `php bin/auto_backup.php` como al consultar la gestión de respaldos si se superó el intervalo. Primero genera el volcado SQL mediante `pg_dump` en `storage/backups/`; si `pg_dump` falla, aborta sin registrar en `respaldo` ni eliminar respaldos previos.

#### 1. Listar respaldos vigentes

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/respaldos` |
| Quién puede usarla | Administrador |
| Ejemplo de respuesta | `200` con `data` = `{"items": [...], "total": 7, "max_retention": 7, "auto_backup_interval_h": 48, "auto_backup_triggered": false}` |
| Errores esperados | `401`, `403`, `500` |

#### 2. Ver detalle de un respaldo

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `GET /api/v1/admin/respaldos/{id}` |
| Quién puede usarla | Administrador |
| Campos | `{id}` entero positivo (`id_respaldo`) |
| Ejemplo de respuesta | `200` con `data` = registro de `respaldo` |
| Errores esperados | `400`, `401`, `403`, `404`, `500` |

#### 3. Generar y registrar respaldo (con rotación automática)

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/admin/respaldos` |
| Quién puede usarla | Administrador |
| Campos opcionales | `archivo` (nombre seguro `[A-Za-z0-9._-]+`, máx. 255 chars; si se omite se genera `canariapp_backup_YYYYMMDD_HHMMSS_xxxxxx.sql`), `motivo` |
| Ejemplo de petición | `{"motivo": "Respaldo preventivo previo a cierre de temporada"}` |
| Ejemplo de respuesta | `201` con `data` = `{"respaldo": {...}, "rotados": ["canariapp_backup_...sql"]}` |
| Errores esperados | `400`, `401`, `403`, `409` nombre de archivo duplicado, `422` nombre inválido, `500` fallo al ejecutar `pg_dump` (no registra ni rota) |

#### 4. Restaurar respaldo (`SRS-RF029`)

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/admin/respaldos/{id}/restaurar` |
| Quién puede usarla | Administrador |
| Campos | `{id}` entero positivo (`id_respaldo`). Cuerpo opcional: `{"motivo": "..."}` |
| Ejemplo de respuesta | `200` con `data` = `{"respaldo": {...}, "restaurado": true}` |
| Errores esperados | `400`, `401`, `403`, `404` respaldo o archivo `.sql` inexistente, `500` fallo al ejecutar `psql` |

---

### 6.6 Carga administrativa de catálogos oficiales

#### 1. Cargar o actualizar nomenclador oficial (`SRS-RF010`)

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/admin/nomenclador` |
| Quién puede usarla | Administrador |
| Formatos admitidos | Objeto individual `{"codigo", "nombre", "tipo", "serie"}`, lote JSON (`{"variedades": [...]}` / `{"items": [...]}` / arreglo raíz) o CSV en `{"contenido": "..."}` |
| Ejemplo de petición | `{"variedades": [{"codigo": "01-001", "nombre": "AMARILLO INTENSO", "tipo": "CC", "serie": "Lipocrómicos"}]}` |
| Ejemplo de respuesta | `201` con `data` = `{"procesadas": 1, "insertadas": 1, "actualizadas": 0, "ejemplares_requieren_revision": 0, "items": [...]}` |
| Errores esperados | `400`, `401`, `403`, `422` validación (`codigo` 1–10 chars, `nombre` 1–150 chars, `tipo` `"CC"` o `"CP"`), `500` |
| Reglas de validación | Si un `codigo` ya existe se actualiza sin eliminar ejemplares; si cambia el sexo derivado de la variedad, PostgreSQL marca automáticamente `canario.requiere_revision = true` |

#### 2. Registrar sigla oficial de club (`SRS-RF011`)

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/admin/clubes` |
| Quién puede usarla | Administrador |
| Campos obligatorios | `sigla` (2–6 letras mayúsculas `^[A-Z]{2,6}$`) o lote `{"clubes": ["FOCH", "AOB"]}` |
| Ejemplo de petición | `{"sigla": "FOCH"}` |
| Ejemplo de respuesta | `201` con `data` = `{"id_club": 5, "sigla": "FOCH"}` |
| Errores esperados | `400`, `401`, `403`, `409` sigla duplicada, `422` formato inválido, `500` |

#### 3. Registrar o cargar mutaciones genéticas (`SRS-RF027`)

| Campo o decisión | Valor acordado |
|---|---|
| Método y ruta | `POST /api/v1/admin/mutaciones` |
| Quién puede usarla | Administrador |
| Campos obligatorios | `nombre` (1–100 chars, único sin distinguir mayúsculas), `tipo_herencia` (`"autosómica recesiva"` o `"ligada al sexo recesiva"`), o lote `{"mutaciones": [...]}` |
| Ejemplo de petición | `{"nombre": "Ágata", "tipo_herencia": "ligada al sexo recesiva"}` |
| Ejemplo de respuesta | `201` con `data` = `{"id_mutacion": 3, "nombre": "Ágata", "tipo_herencia": "ligada al sexo recesiva"}` |
| Errores esperados | `400`, `401`, `403`, `409` nombre de mutación duplicado, `422` validación, `500` |

---

## 7. Referencia de campos, validaciones y códigos de dominio

### Reglas de validación por entidad

| Entidad | Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|---|
| **Usuario / Criador** | `nombre` | texto | Sí (alta) | Máx. 100 caracteres; letras, espacios y signos básicos (`.'-`) |
| | `correo` | texto | Sí (alta/login) | Email válido, máx. 100 caracteres; único sin distinguir mayúsculas (`uq_usuario_correo_lower`) |
| | `password` | texto | Sí (alta/login) | Mínimo 8 caracteres al crear o actualizar |
| | `numero_socio` | texto | Sí (alta criador) | 1–5 dígitos; único entre criadores y no editable desde `/criador/perfil` |
| **Canario** | `anillo` | texto | Sí (alta) | 1–6 dígitos; único globalmente junto con club, socio y temporada (`uq_anillo`); no modificable en Modo de Corrección |
| | `id_club` | entero | Sí (alta) | Entero positivo existente en `club` |
| | `numero_socio` | texto | Sí (alta) | 1–5 dígitos |
| | `temporada` | entero | Sí (alta) | Año de 4 dígitos entre `1000` y el año actual (`date('Y')`) |
| | `sexo` | texto / `null` | Sí en adultos / No en crías | `"M"` o `"H"` (`null` permitido al crear cría mediante `POST /api/v1/crias`) |
| | `id_variedad` | entero / `null` | Sí en adultos / No en crías | Entero positivo existente en `variedad` (`null` permitido al crear cría mediante `POST /api/v1/crias`) |
| **Pareja** | `id_macho` | entero | Sí (alta) | Ejemplar `"M"` del criadero |
| | `id_hembra` | entero | Sí (alta) | Ejemplar `"H"` del criadero distinto de `id_macho`; máx. 1 pareja activa |
| | `id_jaula` | entero | Sí (alta) | Jaula del criadero; máx. 1 pareja activa |
| | `fecha_formacion` | fecha | No | `YYYY-MM-DD`, `<=` fecha actual |
| | `estado` | texto | No | `"activa"`, `"finalizada"` o `"anulada"` |
| | `fecha_fin` | fecha | No | `YYYY-MM-DD`, `>= fecha_formacion` al cerrar |
| **Cruce** | `id_pareja` | entero | Sí (alta) | Pareja `"activa"` del criadero; inmutable |
| | `fecha_cruce` | fecha | Sí (alta) | `YYYY-MM-DD`, `<=` fecha actual |
| **Nidada** | `id_cruce` | entero | Sí (alta) | Cruce del criadero; inmutable |
| | `fecha_nacimiento` | fecha | Sí (alta) | `YYYY-MM-DD`, `>= fecha_cruce` y `<=` fecha actual |
| **Cría** | `id_nidada` | entero | Sí (alta) | Nidada del criadero; inmutable |
| | `id_canario` | entero | Sí en modalidad 2 | Ejemplar del criadero distinto de los padres; en modalidad 1 se crea junto con la cría en la misma transacción |
| | `factor_genetico` | entero / `null` | No | `id_mutacion` válido o `null` |
| | `reservada` | booleano | No | Por defecto `false` |
| **Título** | `nombre` | texto | Sí (alta) | 1–100 caracteres no vacío |
| | `fecha` | fecha | Sí (alta) | `YYYY-MM-DD`, `<=` fecha actual |
| **Simulación** | `genotipo_macho` / `genotipo_hembra` | texto | Sí (alta) | `"visual"`, `"portador"` o `"sin factor"` (hembra no puede ser `"portador"` en herencia ligada al sexo recesiva) |

### Códigos de dominio del backend

| Código interno | HTTP | Significado |
|---|---|---|
| `correction_mode_required` | `403` | Se intentó editar `anillo`/`sexo` (canario) o `id_macho`/`id_hembra` (pareja) sin Modo de Corrección |
| `request_mismatch` / `forbidden` | `403` | Rol no autorizado, solicitud de corrección ajena o acceso a recurso de otro criadero |
| `not_found` / `request_not_found` | `404` | Recurso o solicitud de corrección inexistente |
| `conflict_anillo` | `409` | El anillo completo ya existe en el sistema (mensaje genérico por `SRS-RF003`) |
| `conflict_email` / `conflict_member_number` | `409` | Correo o número de socio ya registrado |
| `cage_occupied` | `409` | La jaula ya está ocupada por una pareja activa |
| `female_active_pair` | `409` | La hembra ya tiene pareja activa |
| `request_not_approved` / `request_already_closed` | `409` | La solicitud de corrección no está aprobada o ya fue aplicada |
| `active_pairs_conflict` | `409` | Ejemplar participa en parejas activas/finalizadas al intentar corregir su sexo |
| `pairs_with_matings_conflict` / `matings_annul_conflict` | `409` | Una pareja con cruces registrados no puede anularse; debe reasignarse en Modo de Corrección |
| `consanguinity_conflict` | `409` | Un ejemplar no puede ser progenitor en la pareja de la que es cría |
| `conflict_pending` | `409` | Ya existe una solicitud de corrección pendiente para ese ejemplar |
| `invalid_state` / `already_active` / `already_closed` | `409` | Transición de estado inválida en solicitud de corrección o modo de operación |
| `duplicate_file` | `409` | Ya existe un respaldo registrado con ese nombre de archivo |
| `conflict` | `409` | Restricción de negocio o integridad referencial (`23503`, `23505` o trigger `P0001`) |
| `correction_field_mismatch` | `422` | Se intentó modificar un campo distinto al aprobado en la solicitud de corrección |
| `invalid_data` / `invalid_reference` / `emergency_incomplete` | `422` | Error de formato, temporada futura, referencia inexistente/ajena o cierre de emergencia sin diagnóstico y acciones |

---

## 8. Pendiente de coordinar

- **Métricas de dashboard (`ProgressController` / `SortController`):** los controladores bajo `Controllers/Api/` (excepto `WikiController`) permanecen vacíos y sin rutas registradas; coordinar con Frontend si se requieren vistas agregadas de avance de temporada o rankings.
- **Sincronización con Frontend:** comunicar los ajustes acordados:
  - Modo de Corrección en `PATCH /api/v1/canarios/{id}` exige `id_solicitud` aprobada, `password` del criador (`RF031`), `motivo` y modifica únicamente `sexo` o `id_variedad` (sin cambios de `anillo`), cerrando la solicitud automáticamente (`RF033`).
  - Alta de crías sin `sexo` ni `id_variedad` (`RF019`, `RF020`) mediante `POST /api/v1/crias` en una única petición transaccional.
  - Mensajes diferenciados en `POST`/`PATCH /api/v1/parejas` (`"La jaula ya está ocupada por una pareja activa."` / `"La hembra ya tiene pareja activa."`).
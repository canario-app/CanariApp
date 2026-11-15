# Acuerdo de API

Borrador a completar por Frontend y Backend. Si cambia la estructura de los datos, coordinarlo con BD.
La API es la forma en que la pantalla pide y guarda información en el servidor.

Antes de programar, acordar nombres de campos, tipos, obligatorios, fechas y mensajes de error.
Fechas de calendario en `YYYY-MM-DD`; horas y eventos de monitoreo en la zona horaria configurada en `APP_TIMEZONE`.

## Convenciones generales

- Base: `/api/v1` (salvo `POST /api/login`).
- Autenticación: `Authorization: Bearer <token>` en todas las rutas privadas.
- Cuerpo y respuesta: JSON.
- Formato de éxito:
  ```json
  { "status": "success", "message": "...", "data": { } }
  ```
- Formato de error:
  ```json
  { "status": "error", "message": "...", "errors": { "campo": "mensaje" } }
  ```
- Errores: `400` JSON/ID inválido, `401` sin token, `403` sin permiso, `404` no encontrado, `409` conflicto, `422` validación, `500` error interno.

## Recursos relacionados

El canario se devuelve con los nombres de sus catálogos para que la pantalla no tenga que pedirlos por separado. En el esquema, `color`, `variedad`, `club` y `criador` son tablas separadas.

Objeto `canario`:

| Campo | Tipo | Origen |
|---|---|---|
| `id_canario` | entero | `canario.id_canario` |
| `anillo` | texto (≤20) | `canario.anillo` |
| `nombre` | texto (≤100) o `null` | `canario.nombre` |
| `sexo` | `"M"`, `"H"` o `null` | `canario.sexo` |
| `fecha_nacimiento` | `YYYY-MM-DD` o `null` | `canario.fecha_nacimiento` |
| `disponibilidad` | texto (≤20) | `canario.disponibilidad` (default `disponible`) |
| `id_color` | entero o `null` | `canario.id_color` |
| `color_nombre` | texto o `null` | `color.nombre` |
| `numero_socio` | texto (≤5) o `null` | copiado de `criador.numero_socio` |
| `temporada` | entero o `null` | `canario.temporada` |
| `id_club` | entero o `null` | `canario.id_club` |
| `club_sigla` | texto o `null` | `club.sigla` |
| `id_variedad` | entero o `null` | `canario.id_variedad` |
| `variedad_nombre` | texto o `null` | `variedad.nombre` |
| `id_criador` | entero | `canario.id_criador` (desde el token) |
| `criador_nombre` | texto | `usuario.nombre` |
| `requiere_revision` | booleano | `canario.requiere_revision` |

`id_canario`, `id_criador` y `numero_socio` **no** se aceptan en el cuerpo: los asigna el servidor.

## Operaciones

### 1. Listar canarios

|         Campo o decisión       | Valor acordado |
|--------------------------------|-----------|
|          Método y ruta         | `GET /api/v1/canarios` |
|       Quién puede usarla       | Criador (solo los suyos) y administrador (todos) |
| Campos, tipos y obligatoriedad | Sin cuerpo. Filtros opcionales por query string |
|       Ejemplo de petición      | `GET /api/v1/canarios?buscar=ABC&disponibilidad=disponible&color=1&temporada=2026` |
|       Ejemplo de respuesta     | `200` con `data` = lista de objetos `canario` |
|       Errores esperados        | `401`, `500` |
|       Reglas de validación     | `buscar` coincide parcialmente con anillo o nombre; `color` es `id_color`; filtros vacíos se ignoran |

### 2. Ver detalle de un canario

|         Campo o decisión       | Valor acordado |
|--------------------------------|-----------|
|          Método y ruta         | `GET /api/v1/canarios/{id}` |
|       Quién puede usarla       | Criador dueño del canario y administrador |
| Campos, tipos y obligatoriedad | `{id}` entero positivo |
|       Ejemplo de petición      | `GET /api/v1/canarios/12` |
|       Ejemplo de respuesta     | `200` con `data` = objeto `canario` |
|       Errores esperados        | `400` ID inválido, `401`, `403` canario ajeno, `404` inexistente |
|       Reglas de validación     | Un criador no puede ver canarios de otro criador |

### 3. Crear canario

|         Campo o decisión       | Valor acordado |
|--------------------------------|-----------|
|          Método y ruta         | `POST /api/v1/canarios` |
|       Quién puede usarla       | Criador y administrador |
| Campos, tipos y obligatoriedad | `anillo` obligatorio; el resto opcional |
|       Ejemplo de petición      | Ver bloque siguiente |
|       Ejemplo de respuesta     | `201` con `data` = objeto `canario` creado |
|       Errores esperados        | `400`, `401`, `409` anillo duplicado, `422` validación o referencia inexistente |
|       Reglas de validación     | Ver tabla de campos |

```json
{
  "anillo": "ABC-123",
  "nombre": "Piolín",
  "sexo": "M",
  "fecha_nacimiento": "2026-03-15",
  "disponibilidad": "disponible",
  "id_color": 1,
  "id_variedad": 2,
  "id_club": 1,
  "temporada": 2026,
  "requiere_revision": false
}
```

### 4. Actualizar canario

|         Campo o decisión       | Valor acordado |
|--------------------------------|-----------|
|          Método y ruta         | `PUT` o `PATCH /api/v1/canarios/{id}` |
|       Quién puede usarla       | Criador dueño del canario y administrador |
| Campos, tipos y obligatoriedad | Mismos campos que crear; los omitidos conservan su valor |
|       Ejemplo de petición      | `PATCH /api/v1/canarios/12` con `{"disponibilidad": "reservado"}` |
|       Ejemplo de respuesta     | `200` con `data` = objeto `canario` actualizado |
|       Errores esperados        | `400`, `401`, `403`, `404`, `409`, `422` |
|       Reglas de validación     | No se puede cambiar `id_criador` ni `numero_socio`; `anillo`, si viene, no puede quedar vacío |

### 5. Eliminar canario

|         Campo o decisión       | Valor acordado |
|--------------------------------|-----------|
|          Método y ruta         | `DELETE /api/v1/canarios/{id}` |
|       Quién puede usarla       | Criador dueño del canario y administrador |
| Campos, tipos y obligatoriedad | `{id}` entero positivo |
|       Ejemplo de petición      | `DELETE /api/v1/canarios/12` |
|       Ejemplo de respuesta     | `204` sin cuerpo |
|       Errores esperados        | `400`, `401`, `403`, `404`, `409` tiene historial asociado |
|       Reglas de validación     | No se elimina si tiene parejas, crías, títulos, árbol genealógico, monitoreo o solicitudes asociadas |

## Campos y validaciones

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `anillo` | texto | Sí (al crear) | ≤20, no vacío, único por criador |
| `nombre` | texto | No | ≤100 |
| `sexo` | texto | No | `M` o `H` si viene |
| `fecha_nacimiento` | fecha | No | `YYYY-MM-DD`, no futura |
| `disponibilidad` | texto | No | ≤20, default `disponible` |
| `id_color` | entero | No | Debe existir en `color` |
| `id_variedad` | entero | No | Debe existir en `variedad` |
| `id_club` | entero | No | Debe existir en `club` |
| `temporada` | entero | No | Entre 1900 y 2100 |
| `requiere_revision` | booleano | No | Default `false` |

Decisiones pendientes (no bloquean): catálogo de `disponibilidad` y alcance real de unicidad del anillo (hoy se valida por criador porque el esquema no tiene `UNIQUE`).

## Pendiente de coordinar

- Catálogo de valores de `disponibilidad` con el cliente.
- Índice único de `anillo` en BD y su alcance (global o por criador).
- Política de borrado de canarios con historial (`ON DELETE` o borrado lógico).

Si una operación cambia, actualizar este documento y avisar a las áreas que la usan antes de integrar el cambio.

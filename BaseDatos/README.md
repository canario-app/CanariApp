# Archivos de la v7.1

Esta carpeta contiene la versión 7.1 del modelo de datos de CanariApp: el esquema de la base, sus permisos, sus pruebas, el diagrama y las notas de cambios. Es una carpeta completa: no necesita ningún archivo de la v7 ni de la v6 para funcionar.

## Resumen

| Archivo | Qué es | Cuándo se usa |
|---|---|---|
| `reset_dev_v7_1.sql` | Borra todas las tablas | Solo en desarrollo, antes de recrear la base |
| `canarios_v7_1.sql` | Crea la base de datos | Siempre; es el archivo principal |
| `permisos_v7_1.sql` | Da permisos al usuario con que se conecta PHP | Después de crear la base |
| `pruebas_v7_1.sql` | Comprueba que las reglas funcionan | Después de cada cambio al esquema |
| `catalogo/seeds/variedad_2026_v7_1.sql` | Carga el nomenclador 2026 (2.661 variedades) | En la base que usa la app, después de los permisos |
| `admin_inicial_v7_1.sql` | Crea el primer usuario administrador | En la base que usa la app, una sola vez |
| `MER_canarios_v7_1.drawio` | Diagrama entidad-relación | Para entender y presentar el modelo |

## Orden de ejecución

Los cuatro archivos SQL se ejecutan en este orden, sobre una base de pruebas:

```sh
createdb canariapp_test
psql -v ON_ERROR_STOP=1 -d canariapp_test -f reset_dev_v7_1.sql
psql -v ON_ERROR_STOP=1 -d canariapp_test -f canarios_v7_1.sql
psql -v ON_ERROR_STOP=1 -d canariapp_test -f permisos_v7_1.sql
psql -v ON_ERROR_STOP=1 -d canariapp_test -f pruebas_v7_1.sql ; echo "salida=$?"
```

`-v ON_ERROR_STOP=1` hace que `psql` se detenga en el primer error en vez de seguir. Si la última línea imprime `salida=0`, todo pasó.

### Base que usa la aplicación

Requiere PostgreSQL 15 o superior. La base es la de `DB_NAME` en el `.env` del backend, y el rol `canariapp` debe existir con la misma contraseña que `DB_PASSWORD`. Desde esta carpeta:

```sh
psql -v ON_ERROR_STOP=1 -d canariapp_db -f canarios_v7_1.sql
psql -v ON_ERROR_STOP=1 -d canariapp_db -f permisos_v7_1.sql
psql -v ON_ERROR_STOP=1 -d canariapp_db -f catalogo/seeds/variedad_2026_v7_1.sql
psql -d canariapp_db -v correo=admin@canariapp.cl -f admin_inicial_v7_1.sql
```

No se ejecutan `pruebas_v7_1.sql` ni `reset_dev_v7_1.sql` en esta base.

---

## `admin_inicial_v7_1.sql`

La base parte sin usuarios y la API no puede crear el primer administrador. Este script lo crea sin necesitar PHP:

- Pide la contraseña al ejecutarse (mínimo 8 caracteres), así no queda escrita en ningún archivo ni en el historial.
- Guarda un hash bcrypt hecho con la extensión `pgcrypto`. El login de PHP (`password_verify`) lo acepta igual que uno hecho con `password_hash`.
- El nombre es opcional (`-v nombre='María Pérez'`); por defecto es «Administrador».
- Si ya hay un usuario con ese correo, no cambia nada. Se puede repetir sin riesgo.

Usa comandos de `psql` (`\prompt`, `\if`), así que no funciona en el **Query Tool** de pgAdmin. Ahí se usa la **PSQL Tool** de pgAdmin, o esta consulta, cambiando el correo y la contraseña (y sin guardarla en ningún archivo):

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
INSERT INTO usuario (nombre, correo, password_hash, rol)
VALUES ('Administrador', 'admin@canariapp.cl',
        crypt('CAMBIAR_CONTRASEÑA', gen_salt('bf', 10)), 'administrador');
```

---

## `reset_dev_v7_1.sql`

Borra todas las tablas, la vista y las funciones del proyecto, incluidas las de versiones anteriores (v5 y v6), para dejar la base vacía.

- **Borra los datos sin preguntar.** Se usa solo en la máquina de cada uno. Nunca contra la base compartida ni la final: el SRS exige conservar el historial hasta 2028 (DAT-002).
- Está separado del esquema a propósito. En la v6 los `DROP` iban al inicio del mismo archivo que creaba las tablas, y ejecutarlo por error borraba todo.
- En una base recién creada no hace falta, pero no hace daño: usa `IF EXISTS`.

## `canarios_v7_1.sql`

Es el archivo principal. Crea las 18 tablas, la vista de genealogía, los índices, las reglas de negocio y las cuatro siglas de club iniciales. Todo va dentro de una transacción: si algo falla, no queda nada a medias.

Está ordenado en secciones:

1. **Zona horaria.** Fija `America/Santiago`, porque las reglas de "fecha no futura" dependen de qué día es para el servidor.
2. **Funciones generales.** `fn_inmutable` (impide cambiar una columna) y `fn_exigir_rol` (exige que un usuario sea criador o administrador). Varias tablas las reutilizan.
3. **Cuentas:** `usuario` y `criador`.
4. **Catálogos:** `club`, `variedad` (el nomenclador) y `mutacion`.
5. **Ejemplares:** `jaula` y `canario`.
6. **Crianza:** `pareja`, `cruce`, `nidada` y `cria`, en ese orden porque cada una depende de la anterior.
7. **Títulos y solicitudes de corrección.**
8. **Simulación genética:** `simulacion` y `simulacion_resultado`.
9. **Administración:** `auditoria`, `respaldo` y `modo_operacion`.
10. **Triggers de reglas de negocio.**
11. **Vista** `v_genealogia`: padres y abuelos de cada ejemplar.
12. **Índices** y **datos semilla**.

Las reglas del SRS se aplican con cuatro herramientas. Conviene reconocerlas al leer el archivo:

| Herramienta | Para qué sirve | Ejemplo en el archivo |
|---|---|---|
| `CHECK` | Regla sobre una sola fila | El anillo solo tiene dígitos (RF001) |
| `UNIQUE` e índices únicos | Que algo no se repita | Anillo único (RF003); una pareja activa por hembra (RF015) |
| Llave foránea (`FOREIGN KEY`) | Que lo referenciado exista | Macho, hembra y jaula del mismo criador que la pareja (SEG-001) |
| Trigger | Regla que mira otras filas o tablas | Máximo 6 parejas activas por macho (RF013) |

Cada regla lleva un comentario con el requisito que cumple (`SRS-RF013`, `SEG-001`, `DAT-003`…), para poder ir del SQL al SRS y de vuelta.

Tres columnas las calcula la base y **no se escriben desde PHP**: `variedad.sexo`, `cria.es_portadora` y `canario.requiere_revision`.

## `permisos_v7_1.sql`

Define qué puede hacer el usuario de base de datos con que se conecta la aplicación PHP (por defecto, el rol `canariapp`).

- PHP no debe conectarse como dueño de las tablas. Con este archivo, la aplicación puede leer, insertar y actualizar, pero **no borrar** el historial de crianza.
- En `auditoria` solo puede insertar y leer.
- El rol debe existir antes; lo crea una vez un administrador de PostgreSQL. La contraseña no va en el repositorio.
- Para usar otro nombre de rol: `psql -v rol_app=otro_rol -d canariapp_test -f permisos_v7_1.sql`.

Estos permisos son del rol técnico de la aplicación, que comparten criadores y administradores. Qué puede hacer cada persona lo decide el backend según la sesión.

## `pruebas_v7_1.sql`

Carga datos de ejemplo ficticios y ejecuta 136 casos. Cada caso intenta una operación y comprueba que la base responda como se espera.

Cada caso tiene esta forma:

```sql
SELECT t('RF013 séptima pareja del macho', 'P0001:máximo de 6 parejas activas',
         $q$INSERT INTO pareja (...) VALUES (...)$q$);
```

- El primer dato es el nombre del caso, con el requisito que prueba.
- El segundo dice qué se espera: `'OK'` si debe aceptarse, o `'CÓDIGO:texto'` si debe rechazarse con ese código de error y ese texto en el mensaje. Así un rechazo por un motivo distinto cuenta como falla.
- El tercero es la operación a intentar.

Cómo leer el resultado:

- Cada caso imprime `OK` o `FALLA`.
- Al final aparece un resumen (`casos | ok | falla`) y la lista de los que fallaron.
- Si hubo alguna falla, el script termina con error y `psql` devuelve un código distinto de 0.

Hay que ejecutarlo sobre una base recién creada: los datos de ejemplo suponen que los identificadores empiezan en 1. Deja en la base la tabla `resultado_pruebas` y la función `t`; el reset las borra.

Al cambiar una regla del esquema, se agrega al menos un caso que deba aceptarse y uno que deba rechazarse.

## `MER_canarios_v7_1.drawio`

El diagrama entidad-relación, editable en draw.io (diagrams.net).

- **Rectángulos azules:** las 18 entidades, una por tabla.
- **Elipses:** los atributos de cada entidad. No incluyen las llaves foráneas, porque en un modelo conceptual esas son las relaciones.
- **Rombos amarillos:** las 28 relaciones. Cada una corresponde a una llave foránea del SQL.
- **Números junto a las líneas:** la cardinalidad. `1` es exactamente uno, `0..1` es opcional y `0..N` es ninguno o varios.
- **Recuadro gris, abajo a la izquierda:** cómo leer el diagrama, las reglas que no se pueden dibujar y lo que debe resolver el backend.

Si se cambia el esquema, hay que actualizar el diagrama para que sigan coincidiendo.

Este archivo se generó por programa y se comprobó que ninguna línea atraviesa una figura ajena, pero no se ha abierto en draw.io. Antes de entregarlo, ábranlo y revisen que el texto se lea bien.


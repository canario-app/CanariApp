# Catálogo del nomenclador 2026

Una sola cadena, donde cada paso se regenera desde el anterior:

```
fuente/*.pdf ─► extraccion_literal_2026.csv ─► (+ correcciones.csv) ─► variedad_2026.csv ─► seeds/variedad_2026.sql ─► base
                agrupaciones_2026.csv                                  └─► Catalogo_CanariApp_2026.xlsx (vista para el cliente)
```

Todo lo que está después de los PDF lo escribe `extraer.py`. **No se edita a mano ningún archivo generado.** Para cambiar un dato se agrega o modifica una fila de `correcciones.csv` y se vuelve a ejecutar:

```sh
python3 catalogo/extraer.py
psql -v ON_ERROR_STOP=1 -d canariapp_dev -f catalogo/seeds/variedad_2026.sql
```

Requiere `pdftotext` (paquete poppler) y Python 3.8 o superior, sin bibliotecas externas. El seed `variedad_2026.sql` necesita el esquema de `canarios_v7_2.sql`, que incluye la tabla `serie`.

### Carga en el esquema v7.1

Mientras se use `canarios_v7_1.sql` (sin tabla `serie`), se carga `seeds/variedad_2026_v7_1.sql`. Trae las mismas 2.661 variedades y guarda la serie como texto en `variedad.serie`:

```sh
psql -v ON_ERROR_STOP=1 -d canariapp_dev -f catalogo/seeds/variedad_2026_v7_1.sql
```

- Se ejecuta después de `canarios_v7_1.sql` y `permisos_v7_1.sql`, en la base de desarrollo (no en la de `pruebas_v7_1.sql`). Solo hace `INSERT` y `UPDATE` sobre `variedad`, así que funciona también con el rol de la aplicación.
- Se puede repetir: actualiza por código, no borra variedades y revierte todo si los totales (881 CC, 1.780 CP, 136 series) o el sexo no coinciden.
- La v7.1 no tiene columnas para el anillo en mm, el orden de la serie ni `en_estudio`: esos datos no se cargan. Las 3 categorías en estudio (D.881, E1.2101, E2.5801) quedan como variedades normales; en una base nueva `ORDER BY id_variedad` sigue el orden del PDF.
- Si se cambia `correcciones.csv` y no hay `pdftotext` a mano, este seed se regenera desde `variedad_2026.csv` con `python3 catalogo/extraer.py --solo-v7_1`.

## Archivos

| Archivo | Se edita a mano | Qué es |
|---|---|---|
| `fuente/17768844458.pdf` | No | Nomenclador de color 2026 (sección D), del cliente |
| `fuente/e - 2026.pdf` | No | Nomenclador de porte 2026 (secciones E1 y E2), del cliente |
| `fuente/SHA256SUMS` | Solo si llega un PDF nuevo | Huella de los PDF. Si un PDF cambia, el script se detiene |
| `extraer.py` | Sí (es el código) | Hace toda la cadena y sus validaciones |
| `correcciones.csv` | **Sí: es el único dato que se edita** | Cada diferencia con el PDF, con motivo y quién la aprobó |
| `extraccion_literal_2026.csv` | No | Lo que dice el PDF, sin corregir nada (2.661 filas) |
| `agrupaciones_2026.csv` | No | Las 440 filas `D.001-D.002`. No son variedades y no se cargan |
| `variedad_2026.csv` | No | Catálogo canónico: el literal con las correcciones aprobadas aplicadas |
| `seeds/variedad_2026.sql` | No | Carga de `serie` y `variedad` (esquema v7.2) |
| `seeds/variedad_2026_v7_1.sql` | No | La misma carga para el esquema v7.1, con la serie como texto |
| `Catalogo_CanariApp_2026.xlsx` | No | Vista para que el cliente revise (incluye la hoja «Pendientes cliente») |
| `mutacion.csv` | Sí | Propuesta del catálogo `mutacion`. **No se carga** hasta que la valide el cliente (DAT-006) |
| `../AVISO_BACKEND.md` | Sí | Aviso del cambio de esquema para el equipo de Backend, incluido el permiso que falta para cargar desde la app |

## Qué hace `extraer.py`

1. **Comprueba los PDF** contra `fuente/SHA256SUMS`.
2. **Extrae** con `pdftotext -layout`, página por página: color páginas 1–27 y porte páginas 1–47 (las páginas 48–188 no tienen texto de catálogo; el script revisa cada una, hasta la última página del PDF, y se detiene si alguna trae algo con forma de código). De cada entrada lee el código, el nombre, la serie o raza, el anillo y la página. Cualquier línea que no reconozca detiene el script: así un cambio de formato del PDF no se pierde en silencio.
3. **Separa las agrupaciones** (`D.001-D.002`): van a `agrupaciones_2026.csv`. Además no cabrían en `variedad.codigo`, que es `VARCHAR(10)`: tienen 11 caracteres.
4. **Aplica `correcciones.csv`** (ver más abajo).
5. **Arma el catálogo canónico**: tipo (D → CC, E1/E2 → CP), serie, anillo en mm, orden de la serie en el PDF, `en_estudio` y el sexo que indica el nombre.
6. **Valida** y se detiene con un error si algo no se cumple:
   - 881 códigos de color y 1.780 de porte (1.387 en E1 y 393 en E2); 440 agrupaciones; 98 series de color y 38 encabezados de porte; 3 categorías en estudio;
   - ningún código repetido, todos con formato `D.nnn` o `En.nnnn`, ninguno de más de 10 caracteres y ningún nombre de más de 150;
   - toda variedad tiene serie, y cada serie tiene un solo tipo, sección y anillo;
   - en porte, cada nombre empieza con el nombre de su raza (sin contar tildes). Esta regla es la que encuentra SALENTNO y REHILÄNDER;
   - no quedan nombres repetidos, salvo los que tienen una consulta pendiente al cliente.
7. **Escribe** los CSV, el seed y el Excel. Si la validación falló, no escribe nada.

## Qué hace el seed

Se puede ejecutar todas las veces que haga falta sobre la misma base:

1. Inserta o actualiza las series por `(seccion, nombre)` y las variedades por código (`ON CONFLICT (codigo) DO UPDATE`, SRS-RF010). Las filas nuevas se insertan en el orden del PDF, así que en una base nueva los `id` salen iguales en todas las máquinas (la serie 1 es «Serie Lipocrómicos sin Factor», la variedad 1 es D.001).
2. **Borra las series que ya no vienen en el archivo y quedaron vacías.** Por ejemplo, si se corrige el nombre de una raza, la carga crea la serie con el nombre nuevo, mueve sus variedades y borra la del nombre viejo, que si no aparecería vacía en el selector.
3. **No borra variedades que ya no vienen en el archivo**, porque puede haber ejemplares que las usen. Las informa con un `WARNING` y una lista (código, nombre, serie y cuántos ejemplares la usan). Una serie que solo tiene variedades sobrantes también se conserva y se informa. Qué hacer con ellas lo decide el equipo con el cliente.
4. Comprueba y, si algo falla, **revierte la carga completa**:
   - quedan 881 CC y 1.780 CP;
   - el sexo que calcula la base (`variedad.sexo`, columna generada) coincide con el del CSV;
   - están en la base las 136 series del archivo;
   - ninguna serie quedó sin variedades.
5. Avisa con un `WARNING`, sin revertir, si dos series del mismo tipo tienen el mismo `orden` (solo puede pasar con series sobrantes).

El mensaje final dice cuántas series hay en la base, cuántas vienen del archivo y cuántas sobran.

## `correcciones.csv`

Columnas: `codigo, campo, valor_pdf, valor_corregido, motivo, aprobado_por`.

- `campo` es `codigo`, `nombre` o `serie`. Con `campo = serie` y `codigo` vacío, la corrección se aplica a la serie completa.
- `valor_pdf` debe ser **exactamente** lo que dice el PDF. Si no coincide (por ejemplo, porque llegó un PDF nuevo), el script se detiene en vez de aplicar la corrección a ciegas.
Cada fila está en uno de tres estados. El estado se deduce de las columnas; no hay una columna aparte:

| `aprobado_por` | `valor_corregido` | Estado | Efecto |
|---|---|---|---|
| vacío | cualquiera (puede ir vacío o con una propuesta) | **pendiente** | Se registra y aparece en la hoja «Pendientes cliente», pero **no se aplica** |
| lleno | distinto de `valor_pdf` | **aplicada** | El catálogo usa `valor_corregido` |
| lleno | igual a `valor_pdf` | **confirmado sin cambio** | El dato del PDF queda como está y la consulta se cierra |

Por ejemplo, si el cliente responde que E1.2012 y E1.2013 están bien así, se pone su nombre en `aprobado_por` y se copia `valor_pdf` en `valor_corregido`. Un nombre repetido solo se acepta si cada código tiene una consulta pendiente o confirmada sin cambio. Una fila aprobada con `valor_corregido` vacío detiene el script, para que no se confunda con «sin cambio».

- Las correcciones de escritura evidente las aprueba el equipo de BD (`Equipo BD`). Lo dudoso queda pendiente del cliente.

Estado actual: 28 correcciones aplicadas, 0 confirmadas sin cambio y 7 consultas pendientes. La hoja «Correcciones» del Excel muestra el estado de cada fila.

| Caso | Corrección | Aprobó |
|---|---|---|
| `D..881` | → `D.881` | Equipo BD |
| Artefacto «D.» en 15 nombres de serie | `EstuD.io` → `Estudio`; `Jaspe SD.` → `Jaspe SD` (8 series); `Jaspe D.D.` → `Jaspe DD` (6 series) | Equipo BD |
| SALENTNO (E1.2003, E1.2015, E1.2028, E1.2040) | → SALENTINO | Equipo BD |
| CONCOPETE (E1.2031, E1.2036) | → CON COPETE | Equipo BD |
| REHILÄNDER (E1.1920–E1.1925) | → REHINLÄNDER, igual que el encabezado | Equipo BD |
| ¿RHEINLÄNDER? (la grafía internacional) | Pendiente | Cliente |
| E1.0507 / E1.0508: mismo nombre, sin sexo | Se cargan literales, con sexo NULL. Parecen MACHO/HEMBRA (D.511/D.512 en color lo son), pero el PDF no lo dice | Cliente |
| E1.2012 / E1.2013 y E1.2037 / E1.2038: mismo nombre | Se cargan literales. Salentino tiene 25 variedades por grupo y las razas con el mismo esquema 24: puede sobrar un código | Cliente |

Observaciones que **no** se corrigieron, porque no son errores evidentes: varios encabezados de porte llevan tilde y sus variedades no (ARLEQUÍN / ARLEQUIN, HOSSO JAPONÉS / JAPONES); el Crest corona se llama «CRESTED (CORONA)»; en color, cinco series dicen «Negros» en vez de «Negro» (Opalo, Ónix, Cobalto, Mogno y Perla con Factor).

## Decisiones tomadas

- **Esquema:** nueva tabla `serie` (tipo, sección, nombre, anillo_mm, orden). `variedad.serie` (texto) se reemplaza por `variedad.id_serie`, obligatoria, y se agrega `variedad.en_estudio`. Una llave foránea compuesta `(id_serie, tipo)` impide poner una variedad de color en una raza de porte.
- **Categorías en estudio** (D.881, E1.2101, E2.5801): se cargan como elegibles, con `en_estudio = TRUE`. La app decide cómo mostrarlas.
- **La carga actualiza por código** (`ON CONFLICT (codigo) DO UPDATE`, SRS-RF010) y no borra variedades que ya no estén en el archivo, porque puede haber ejemplares que las usen. La columna `sexo` no se carga: la calcula la base desde el nombre.

## `mutacion.csv` (propuesta, no se carga)

Los PDF del nomenclador no traen tipos de herencia. La propuesta sale del libro de Cuevas (`Herencia/util/`, la fuente de verdad de genética del proyecto), con la página del PDF en cada fila, y del cuadro de cruces correspondiente cuando existe. Las páginas son páginas del PDF, no del libro impreso; la numeración impresa se desfasa entre 2 y 20 páginas porque el escaneo agrega o pierde hojas. El 2026-11-17 se revisaron a la vista todas las páginas citadas (92, 95, 209, 219, 224, 226, 228, 230, 237, 251, 267 y 284), y cada una respalda el tipo de herencia de su fila. Al revisarlas se corrigió marfil: su clasificación está en la página 92, no en «92-94». La columna `verificado` deja constancia de esa revisión.

- `propuesta`: pastel y satiné (ligadas al sexo, recesivas); opal, ino, topacio, eumo y cobalto (autosómicas recesivas). Las 7 tienen cuadro de cruces.
- `consultar`: marfil, onyx y blanco recesivo. El libro las clasifica, pero no hay cuadro de cruces.
- No se incluyen: alas grises (herencia no determinada), jaspe y blanco dominante (dominantes). El esquema solo admite los dos tipos de DAT-006.

El cliente debe validar la lista antes de generar su seed (DAT-006, DEP-002).

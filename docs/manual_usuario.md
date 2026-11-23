# Manual de usuario — CanariApp

**Versión:** 1.0 · 24-11-2026
**Sitio web:** https://canariapp-demo.vercel.app
**Para quién es:** criadores de canarios y administradores del sistema.

CanariApp reúne en un solo lugar el registro de su criadero: sus canarios, las parejas que forma, los cruces, las nidadas y crías, los títulos de concurso y un simulador de herencia de mutaciones.

---

## Índice

1. [Antes de empezar](#1-antes-de-empezar)
2. [Iniciar y cerrar sesión](#2-iniciar-y-cerrar-sesión)
3. [Pantalla de inicio y menú](#3-pantalla-de-inicio-y-menú)
4. [Canarios](#4-canarios)
5. [Parejas y cruces](#5-parejas-y-cruces)
6. [Nidadas y crías](#6-nidadas-y-crías)
7. [Títulos](#7-títulos)
8. [Simulador de cruce](#8-simulador-de-cruce)
9. [Corregir datos de un ejemplar](#9-corregir-datos-de-un-ejemplar)
10. [Administración (solo administradores)](#10-administración-solo-administradores)
11. [Mensajes frecuentes y soluciones](#11-mensajes-frecuentes-y-soluciones)
12. [Recorrido de ejemplo de principio a fin](#12-recorrido-de-ejemplo-de-principio-a-fin)

---

## 1. Antes de empezar

- **Navegador:** funciona en Chrome, Edge, Firefox o Safari actualizados, en computador, tablet o teléfono.
- **Cuenta:** las cuentas de criador **no se crean desde el sitio**. Las crea el administrador y le entrega su correo y contraseña.
- **Sus datos son solo suyos:** cada criador ve y modifica únicamente sus propios canarios, parejas, crías y títulos.
- **No se borra historial:** CanariApp no elimina registros de crianza. Las parejas se *finalizan* y los errores se arreglan con una *corrección* que queda registrada.

### El anillo: cómo se identifica un canario

Cada canario se identifica por su anillo, formado por cuatro datos:

| Dato | Formato | Ejemplo |
|---|---|---|
| Número de anillo | Solo dígitos, de 1 a 6 | `2901` |
| Sigla del club | Una de las del catálogo: `CON`, `COV`, `COR`, `SOCH` | `SOCH` |
| N.° de socio | Solo dígitos, de 1 a 5 (el número del criador en su club) | `123` |
| Temporada | Año de 4 dígitos | `2026` |

En pantalla se muestra así: **2901** · SOCH · 123 · 2026. No pueden existir dos canarios con el mismo anillo completo.

### La variedad

La variedad se elige del **Nomenclador 2026** (2.661 variedades), escribiendo su código o parte del nombre; el campo sugiere opciones mientras escribe. Algunos códigos son propios de un sexo (por ejemplo `D.007 AMARILLO MOSAICO MACHO` y `D.008 AMARILLO MOSAICO HEMBRA`): el sistema no deja asignar una variedad de macho a una hembra ni al revés.

---

## 2. Iniciar y cerrar sesión

1. Abra el sitio. Verá **Iniciar sesión**.
2. Escriba su **correo electrónico** y su **contraseña** (mínimo 8 caracteres). Con el ícono del ojo puede ver lo que escribió.
3. El botón **Ingresar** se activa cuando ambos campos son válidos. Púlselo.

Al entrar, el **criador** llega a **Inicio** y el **administrador** a **Criadores**.

**Seguridad:**
- Si se equivoca, se indica cuántos intentos le quedan. Tras **5 intentos fallidos** el ingreso se bloquea **15 minutos** y se muestra una cuenta regresiva.
- Tras **30 minutos sin actividad** la sesión se cierra sola y aparece «Su sesión se cerró». Vuelva a ingresar.
- Para salir, use **Cerrar sesión** (arriba a la derecha). Hágalo siempre en computadores compartidos.

¿No puede entrar? Pulse **Contacte al administrador** en la pantalla de ingreso.

---

## 3. Pantalla de inicio y menú

**Inicio** le da la bienvenida, resume su criadero y tiene el botón **¿Cómo funciona?**, que explica el ciclo completo: *de la pareja al campeón, paso a paso*.

El menú lateral tiene las secciones del criador:

| Sección | Para qué sirve |
|---|---|
| **Canarios** | Ver, buscar y registrar sus ejemplares; abrir la ficha de cada uno |
| **Parejas y cruces** | Formar parejas en jaulas y registrar las fechas de cruce |
| **Crías** | Registrar nidadas y las crías que nacen de cada cruce |
| **Títulos** | Registrar premios de concursos y ver las crías de los ganadores |
| **Simulador** | Calcular qué proporción de crías heredaría una mutación |

---

## 4. Canarios

### 4.1 Ver y buscar

**Canarios** muestra una tabla con: anillo, sexo, variedad, si es *portadora* de alguna mutación, si está *reservada* y su estado.

- Use el buscador para encontrar un anillo. Si no existe en su criadero verá «No encontramos ese anillo en su criadero».
- Use los filtros (sexo, estado, etc.) y **Limpiar búsqueda** para volver a la lista completa.
- Pulse una fila para abrir la **ficha del ejemplar**.

### 4.2 Registrar un ejemplar

1. En **Canarios**, pulse **Registrar ejemplar**.
2. **1. Anillo:** número, club, n.° de socio y temporada.
3. **2. Sexo y variedad:** elija Macho o Hembra y escriba la variedad (por ejemplo `D.007`).
4. Revise la **Vista previa** a la derecha.
5. Pulse **Registrar ejemplar**.

Si el anillo ya existe aparece «**Anillo no disponible**»: revise los cuatro datos del anillo.

### 4.3 Ficha del ejemplar

La ficha reúne todo lo de un canario:

- **Genealogía:** padres y abuelos (cuando nació en su criadero y se registró como cría).
- **Parejas en que participa**, con su jaula, estado y crías.
- **Crías por pareja.**
- **Títulos**, con el botón **Registrar título** para agregar uno sin salir de la ficha.
- **Editar marcas:** marcar la cría como *reservada* o como *portadora* de una mutación.
- **Solicitar corrección** y **Modo de Corrección** (ver sección 9).

Si aparece «**Este ejemplar requiere revisión**», la variedad ya no coincide con el sexo registrado (por ejemplo, después de actualizar el nomenclador). Corríjalo con el Modo de Corrección.

---

## 5. Parejas y cruces

### 5.1 Formar una pareja

1. Vaya a **Parejas y cruces** y pulse **Registrar pareja**.
2. Elija el **macho**, la **hembra** y el **número de jaula**.
3. Pulse **Registrar pareja**. Pasará a la pantalla de esa jaula.

**Reglas que aplica el sistema:**
- Un macho puede tener **hasta 6 parejas activas**.
- Una hembra puede tener **solo 1 pareja activa**.
- Una jaula puede tener **solo 1 pareja activa**.

### 5.2 Registrar un cruce

1. En **Mis parejas**, abra la jaula (o entre desde la pareja recién creada).
2. Pulse **Registrar cruce**, elija la fecha y pulse **Guardar cruce**.

La fecha no puede ser futura ni anterior a la formación de la pareja, y no puede repetirse. La pantalla de la jaula muestra los **Cruces** con su nidada y el **Historial**.

### 5.3 Finalizar una pareja

Cuando la pareja termina, pulse **Finalizar pareja** y confirme. La jaula queda libre para otra pareja. La pareja **no se borra**: queda en el historial con sus cruces y crías.

---

## 6. Nidadas y crías

### 6.1 Registrar una nidada

1. Vaya a **Crías** y pulse **Registrar nidada**.
2. **1. Cruce y nacimiento:** elija el cruce (se listan los cruces de sus parejas que aún no tienen nidada) y la fecha de nacimiento. Esta no puede ser anterior al cruce ni futura.
3. **2. Crías de la nidada:** complete una fila por cría (anillo, sexo y variedad). Use **Agregar otra cría** para más filas: se copian el club, el socio y la temporada de la fila anterior.
4. Pulse **Guardar nidada**.

Las crías quedan como canarios de su criadero, **vinculadas a su padre y su madre**, y aparecen en la genealogía de su ficha.

Si aparece «**No hay cruces disponibles**», primero registre un cruce en **Parejas y cruces**.

### 6.2 Ver y completar crías

**Nidadas y crías** agrupa las crías por pareja y nidada. Desde ahí puede **Agregar cría** a una nidada existente y **completar datos** que falten.

---

## 7. Títulos

### 7.1 Registrar un título

1. Vaya a **Títulos** y pulse **Registrar título** (o use el botón de la ficha del ejemplar).
2. **Ejemplar:** escriba el número de anillo y elija de la lista.
3. **Nombre del título:** hasta 100 caracteres, por ejemplo «1.er lugar, Campeonato Nacional SOCH 2026».
4. **Fecha:** no puede ser futura.
5. Pulse **Guardar título**.

### 7.2 Crías de un ganador

En la lista de **Títulos**, abra un ejemplar premiado para ver **Crías de un ganador**: todas sus crías, agrupadas por pareja, con sus marcas y títulos.

---

## 8. Simulador de cruce

Calcula qué porcentaje de las crías heredaría una mutación, según el tipo de herencia.

1. Vaya a **Simulador**.
2. Elija la **mutación** (por ejemplo Pastel, Opal, Ino…).
3. Elija el **macho** y su genotipo: *visual*, *portador* o *sin factor*.
4. Elija la **hembra** y su genotipo.
5. Pulse **Simular cruce**.

El resultado muestra los porcentajes por sexo de la cría y el **Cuadro de Punnett**. Cada simulación queda en su historial, debajo del formulario.

**Regla importante:** en las mutaciones **ligadas al sexo** (Pastel, Satiné) **la hembra no puede ser portadora**; el sistema no lo permite.

> Las mutaciones cargadas hoy son una **propuesta** del equipo, basada en bibliografía, y están **pendientes de validación por el cliente**. Use los resultados como referencia.

---

## 9. Corregir datos de un ejemplar

El sexo y el anillo no se editan libremente, porque afectan a parejas, crías y genealogía. Hay dos caminos, ambos desde la **ficha del ejemplar**:

- **Solicitar corrección:** indique qué dato está mal y el motivo. La solicitud llega al administrador.
- **Modo de Corrección:** se activa confirmando su **contraseña** y escribiendo un **motivo**. Permite cambiar los datos y, si el canario tiene parejas, **decidir qué hacer con cada una**. Termine con **Guardar corrección** o salga con **Salir sin guardar**.

Toda corrección queda registrada con quién la hizo, cuándo, el valor anterior, el nuevo y el motivo.

---

## 10. Administración (solo administradores)

El administrador **no gestiona canarios**: administra cuentas, catálogos y el sistema. Su menú tiene:

| Sección | Qué hace | Estado actual |
|---|---|---|
| **Criadores** | Lista de cuentas. **Registrar criador**: nombre, correo, n.° de socio y contraseña inicial. Editar un criador existente. | Disponible |
| **Nomenclador de variedades** | Consultar las 2.661 variedades (código, nombre, tipo CC/CP, serie, sexo). | Consulta disponible; la carga de archivo está en desarrollo |
| **Catálogo de mutaciones** | Consultar las mutaciones y su tipo de herencia. | Consulta disponible; la carga de archivo está en desarrollo |
| **Siglas de club** | Ver las siglas (CON, COV, COR, SOCH) y registrar nuevas. | Consulta disponible; registrar está en desarrollo |
| **Correcciones solicitadas** | Revisar y resolver las solicitudes de los criadores. | En desarrollo |
| **Modo de operación** | Activar *Mantenimiento* o *Emergencia*: cierra las sesiones de criadores y bloquea su ingreso hasta volver al modo normal. | En desarrollo |
| **Respaldos** | Ver respaldos y restaurar uno (reemplaza los datos actuales). | En desarrollo |

Las secciones *en desarrollo* ya tienen su pantalla, pero muestran el aviso «**Función pendiente en el backend**» hasta que el equipo de backend publique la operación.

### Crear la cuenta de un criador

1. **Criadores** → **Registrar criador**.
2. **1. Datos del criador:** nombre y n.° de socio (el número que le otorgó su club).
3. **2. Acceso:** correo y contraseña inicial (mínimo 8 caracteres).
4. Guarde y entréguele al criador su correo y contraseña por un medio seguro.

---

## 11. Mensajes frecuentes y soluciones

| Mensaje | Qué significa | Qué hacer |
|---|---|---|
| Correo o contraseña incorrectos | Los datos no coinciden | Revise mayúsculas y el correo; quedan pocos intentos |
| Cuenta bloqueada temporalmente | 5 intentos fallidos | Espere los 15 minutos de la cuenta regresiva |
| Su sesión se cerró | 30 minutos sin actividad | Inicie sesión de nuevo |
| Anillo no disponible | Ese anillo ya está registrado | Revise número, club, socio y temporada |
| Elija una variedad del nomenclador | El código no existe | Escriba el código o nombre y elija de la lista |
| Este macho ya tiene 6 parejas activas | Límite por macho | Finalice una pareja del macho |
| Esta hembra ya tiene una pareja activa | Límite por hembra | Finalice la pareja anterior |
| La jaula ya tiene una pareja activa | Jaula ocupada | Use otra jaula o finalice esa pareja |
| No hay cruces disponibles | No hay cruces sin nidada | Registre primero un cruce |
| En herencia ligada al sexo la hembra no puede ser portadora | Regla genética | Elija *visual* o *sin factor* para la hembra |
| Función pendiente en el backend | La pantalla existe, la operación aún no | Avise al equipo; no es un error suyo |
| No hay conexión con el servidor | El sitio no responde | Espere un momento y recargue |

---

## 12. Recorrido de ejemplo de principio a fin

1. El **administrador** crea la cuenta del criador (sección 10).
2. El **criador** inicia sesión y registra un **macho** y una **hembra** (sección 4.2).
3. Forma una **pareja** en la jaula 1 (sección 5.1).
4. Registra la fecha del **cruce** (sección 5.2).
5. Al nacer los pichones, registra la **nidada** con sus **crías** (sección 6.1).
6. Abre la **ficha** de una cría y ve su **genealogía** con padre y madre (sección 4.3).
7. El padre gana un concurso: registra el **título** (sección 7.1) y consulta las **crías del ganador** (sección 7.2).
8. Antes de la próxima temporada, usa el **simulador** para ver qué crías daría una mutación (sección 8).
9. Al terminar la temporada, **finaliza la pareja** y la jaula queda libre (sección 5.3).

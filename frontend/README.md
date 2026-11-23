# CanariApp — frontend PHP (desde Figma, página Main)

## Cómo correrlo
1. Doble clic en `descargar-iconos.bat` (Windows) o `./descargar-iconos.sh` (Mac/Linux).
   Baja los íconos del Figma a `public/img`. **Los links vencen el 28-11-2026.**
2. Levantar la API del backend (ver `README_API.md`) en http://localhost:8000.
3. XAMPP: copiar la carpeta a `htdocs` y abrir http://localhost/canariapp/public
   (si usa `php -S`, que sea en un puerto distinto al de la API, p. ej. 8080).
4. Un criador y un administrador de prueba los crea quien arma la base; ver `README_API.md`.

## Datos
El front ya no usa datos de prueba: lee y escribe en la API (`includes/api.php` y `includes/datos.php`).
La URL de la API es la constante `API_URL` de `includes/api.php`.
Lo que la API todavía no ofrece está en `PENDIENTE_BACKEND.md`; esas pantallas avisan «Función pendiente en el backend».
La sección de administración (`admin_*.php`) cubre el SRS 4.1.8.

## Pantallas
| Sección | Archivo |
|---|---|
| Login (errores, correo no registrado, bloqueo 15 min, sesión expirada) | login.php |
| Contactar al administrador | contacto.php |
| Inicio + modal «¿Cómo funciona?» | inicio.php |
| Canarios: listado, filtros, búsqueda sin resultado | canarios.php |
| Registrar ejemplar (con validaciones y vista previa) | canario_registrar.php |
| Ficha del ejemplar + modales: solicitar corrección, modo de corrección, registrar título, editar marcas | canario_ficha.php |
| Ficha en Modo de Corrección | canario_correccion.php |
| Parejas: listado con pestañas | parejas.php |
| Registrar pareja (reglas: 6 por macho, 1 por hembra, 1 por jaula) | pareja_registrar.php |
| Jaula: detalle + modales registrar cruce y finalizar pareja | jaula.php |
| Nidadas y crías + modales completar datos y agregar cría | crias.php |
| Registrar nidada (filas de crías dinámicas) | nidada_registrar.php |
| Títulos: listado | titulos.php |
| Registrar título | titulo_registrar.php |
| Crías de un ganador | titulo_crias.php |
| Simulador de cruce | simulador.php |

## Estructura
```
includes/  config.php (sesión, helpers, íconos)  datos.php (datos de prueba)
           componentes.php (modales, badges, validaciones)  db.php (PDO, comentado)
           header.php  sidebar.php  footer.php
public/    *.php (pantallas)  css/styles.css  js/  img/
```

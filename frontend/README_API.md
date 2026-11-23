# Conexión con la API

El front ya no usa datos de prueba: lee y escribe en la API del backend (`includes/api.php` + `includes/datos.php`).

1. Base de datos: en la raíz del proyecto backend, `docker compose up -d`
2. API: `cd backend && php -S localhost:8000 -t public`
3. Front: `http://localhost/canariapp/public` (Apache de XAMPP) — no uses el puerto 8000 para el front.
4. Cuentas: el administrador se crea según `backend/PRENDER_SERVER.md`; los criadores los crea el administrador desde la sección «Criadores».

URL de la API: constante `API_URL` en `includes/api.php`.

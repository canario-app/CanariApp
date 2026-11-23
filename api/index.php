<?php
/*
 * Punto de entrada único en Vercel.
 *   /api/...      -> backend/public/index.php (API del equipo de backend)
 *   /<pagina>.php -> frontend/public/<pagina>.php (frontend del equipo, Figma)
 * El código del equipo no se modifica: solo se enruta.
 */
declare(strict_types=1);

$root = dirname(__DIR__);
require $root . '/vercel/bootstrap.php';

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

if ($path === '/__setup') {
    require $root . '/vercel/setup.php';
    return;
}

if ($path === '/api' || str_starts_with($path, '/api/')) {
    $_SERVER['SCRIPT_NAME'] = '/index.php';
    chdir($root . '/backend/public');
    require $root . '/backend/public/index.php';
    return;
}

$page = ltrim($path, '/');
if ($page === '') {
    $page = 'index.php';
}
$file = $root . '/frontend/public/' . $page;
if (!preg_match('/^[a-z0-9_]+\.php$/', $page) || !is_file($file)) {
    http_response_code(404);
    header('Content-Type: text/html; charset=UTF-8');
    echo '<p style="font:16px sans-serif;padding:2rem">Página no encontrada. <a href="/login.php">Ir al inicio de sesión</a></p>';
    return;
}

// config.php decide permisos según el nombre del script (admin_*.php)
$_SERVER['SCRIPT_NAME'] = '/' . $page;
$_SERVER['PHP_SELF'] = '/' . $page;
$_SERVER['SCRIPT_FILENAME'] = $file;
chdir(dirname($file));
require $file;

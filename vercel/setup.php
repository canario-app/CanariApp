<?php
/*
 * Configuración inicial de la base en Neon (solo Vercel, uso único).
 * Activa únicamente si existe la variable SETUP_TOKEN y la petición trae
 * la cabecera X-Setup-Token igual. Sin esa variable responde 404.
 *   GET  /__setup            -> estado (solo lectura)
 *   POST /__setup?apply=1    -> carga esquema + catálogo + permisos si la base está VACÍA
 * Nunca borra datos.
 */
declare(strict_types=1);
header('Content-Type: application/json; charset=UTF-8');
$expected = getenv('SETUP_TOKEN') ?: '';
if (strlen($expected) < 32 || !hash_equals($expected, $_SERVER['HTTP_X_SETUP_TOKEN'] ?? '')) {
    http_response_code(404);
    echo '{"status":"error","message":"Not found"}';
    return;
}
$url = getenv('DATABASE_URL_UNPOOLED') ?: getenv('DATABASE_URL');
$p = parse_url((string)$url);
$owner = new PDO('pgsql:host=' . $p['host'] . ';port=' . ($p['port'] ?? 5432) . ';dbname=' . ltrim($p['path'], '/') . ';sslmode=require',
    rawurldecode($p['user']), rawurldecode($p['pass'] ?? ''), [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

$status = function () use ($owner): array {
    $tables = $owner->query("SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY 1")->fetchAll(PDO::FETCH_COLUMN);
    $counts = [];
    foreach (['usuario', 'criador', 'variedad', 'mutacion', 'canario'] as $t) {
        if (in_array($t, $tables, true)) $counts[$t] = (int)$owner->query("SELECT count(*) FROM $t")->fetchColumn();
    }
    $roles = $owner->query("SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg\\_%' ORDER BY 1")->fetchAll(PDO::FETCH_COLUMN);
    return ['tables' => $tables, 'counts' => $counts, 'roles' => $roles, 'server' => $owner->query('SHOW server_version')->fetchColumn()];
};

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST' || ($_GET['apply'] ?? '') !== '1') {
    echo json_encode(['status' => 'ok', 'data' => $status()]);
    return;
}

$st = $status();
if ($st['tables'] !== []) {
    http_response_code(409);
    echo json_encode(['status' => 'error', 'message' => 'La base ya tiene tablas: no se aplicó nada.', 'data' => $st]);
    return;
}
$appUser = getenv('DB_USER'); $appPass = getenv('DB_PASSWORD');
$adminMail = getenv('SETUP_ADMIN_EMAIL') ?: 'admin@canariapp.cl'; $adminPass = getenv('SETUP_ADMIN_PASSWORD') ?: '';
if ($appUser !== 'canariapp' || strlen((string)$appPass) < 24 || strlen($adminPass) < 12) {
    http_response_code(422);
    echo '{"status":"error","message":"Faltan DB_USER/DB_PASSWORD/SETUP_ADMIN_PASSWORD"}';
    return;
}
$exists = $owner->prepare('SELECT 1 FROM pg_roles WHERE rolname = ?'); $exists->execute([$appUser]);
if (!$exists->fetchColumn()) {
    $owner->exec('CREATE ROLE canariapp LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD ' . $owner->quote($appPass));
} else {
    $owner->exec('ALTER ROLE canariapp PASSWORD ' . $owner->quote($appPass));
}
$owner->beginTransaction();
try {
    // Volcado generado desde una base Docker recién creada con los scripts oficiales de BaseDatos/
    $owner->exec(file_get_contents(__DIR__ . '/setup_bundle.sql'));
    $owner->exec("SELECT pg_catalog.set_config('search_path', 'public', false)");
    $q = $owner->prepare("INSERT INTO usuario (nombre, correo, password_hash, rol) VALUES ('Administrador', lower(?), ?, 'administrador')");
    $q->execute([$adminMail, password_hash($adminPass, PASSWORD_BCRYPT)]);
    $owner->commit();
} catch (Throwable $e) {
    $owner->rollBack();
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
    return;
}
echo json_encode(['status' => 'ok', 'message' => 'Base inicializada', 'data' => $status()]);

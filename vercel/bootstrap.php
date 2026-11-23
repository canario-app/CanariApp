<?php
/*
 * Arranque común en Vercel (no se usa en Docker ni en XAMPP).
 * 1) Completa DB_* a partir de las variables PG* que instala Neon, si faltan.
 * 2) Guarda las sesiones PHP en PostgreSQL: en Vercel cada petición puede
 *    ejecutarse en una instancia distinta y /tmp no se comparte.
 */
declare(strict_types=1);

// Conexión directa (sin pooler) para que funcionen los prepared statements de PDO
if (!getenv('DB_HOST') && getenv('PGHOST_UNPOOLED')) {
    putenv('DB_HOST=' . getenv('PGHOST_UNPOOLED'));
}
foreach (['DB_HOST' => 'PGHOST', 'DB_NAME' => 'PGDATABASE', 'DB_USER' => 'PGUSER', 'DB_PASSWORD' => 'PGPASSWORD'] as $dst => $src) {
    if (!getenv($dst) && getenv($src)) {
        putenv("$dst=" . getenv($src));
    }
}
if (!getenv('DB_SSLMODE')) {
    putenv('DB_SSLMODE=require');
}
foreach (['APP_ENV', 'APP_DEBUG', 'APP_URL', 'APP_TIMEZONE', 'DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD', 'JWT_SECRET', 'JWT_EXPIRATION', 'API_URL'] as $k) {
    if (getenv($k) !== false) {
        $_ENV[$k] = getenv($k);
    }
}
date_default_timezone_set(getenv('APP_TIMEZONE') ?: 'America/Santiago');

final class PgSessionHandler implements SessionHandlerInterface
{
    private ?PDO $pdo = null;

    private function pdo(): PDO
    {
        if ($this->pdo === null) {
            $dsn = sprintf('pgsql:host=%s;port=%s;dbname=%s;sslmode=%s',
                getenv('DB_HOST'), getenv('DB_PORT') ?: '5432', getenv('DB_NAME'), getenv('DB_SSLMODE') ?: 'require');
            $this->pdo = new PDO($dsn, getenv('DB_USER'), getenv('DB_PASSWORD'), [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
        }
        return $this->pdo;
    }
    public function open(string $path, string $name): bool { return true; }
    public function close(): bool { return true; }
    public function read(string $id): string|false
    {
        $st = $this->pdo()->prepare('SELECT data FROM php_sesion WHERE id = ? AND actualizado > now() - interval \'2 hours\'');
        $st->execute([$id]);
        return (string)($st->fetchColumn() ?: '');
    }
    public function write(string $id, string $data): bool
    {
        $st = $this->pdo()->prepare('INSERT INTO php_sesion (id, data, actualizado) VALUES (?, ?, now())
            ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, actualizado = now()');
        return $st->execute([$id, $data]);
    }
    public function destroy(string $id): bool
    {
        return $this->pdo()->prepare('DELETE FROM php_sesion WHERE id = ?')->execute([$id]);
    }
    public function gc(int $max): int|false
    {
        return $this->pdo()->exec("DELETE FROM php_sesion WHERE actualizado < now() - interval '2 hours'");
    }
}

session_set_save_handler(new PgSessionHandler(), true);
ini_set('session.cookie_httponly', '1');
ini_set('session.cookie_samesite', 'Lax');
if (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https') {
    ini_set('session.cookie_secure', '1');
}

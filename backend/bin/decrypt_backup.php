#!/usr/bin/env php
<?php

/*
 * Descifra un respaldo .sql.enc para revisarlo o restaurarlo a mano (DAT-003).
 *   php bin/decrypt_backup.php storage/backups/archivo.sql.enc > respaldo.sql
 * Necesita la misma BACKUP_ENCRYPTION_KEY con que se generó.
 * El .sql resultante queda SIN cifrar: bórrelo apenas termine.
 */

declare(strict_types=1);

use CanariApp\Backend\Helpers\BackupCrypto;

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit('Acceso permitido únicamente desde línea de comandos.' . PHP_EOL);
}

define('BASE_PATH', dirname(__DIR__));

require_once BASE_PATH . '/vendor/autoload.php';

try {
    if (is_file(BASE_PATH . '/.env')) {
        Dotenv\Dotenv::createImmutable(BASE_PATH)->safeLoad();
    }

    $file = $argv[1] ?? '';
    if ($file === '' || !is_file($file)) {
        throw new RuntimeException('Uso: php bin/decrypt_backup.php <archivo.sql.enc> > salida.sql');
    }

    $data = (string) file_get_contents($file);
    fwrite(STDOUT, BackupCrypto::decrypt($data, BackupCrypto::secretFromEnvironment()));
    exit(0);
} catch (Throwable $exception) {
    fwrite(STDERR, '[ERROR] ' . $exception->getMessage() . PHP_EOL);
    exit(1);
}

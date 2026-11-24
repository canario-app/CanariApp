#!/usr/bin/env php
<?php

declare(strict_types=1);

use CanariApp\Backend\Config\App;
use CanariApp\Backend\Controllers\BackupController;

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit('Acceso permitido únicamente desde línea de comandos.' . PHP_EOL);
}

define('BASE_PATH', dirname(__DIR__));

require_once BASE_PATH . '/vendor/autoload.php';

try {
    $envFile = BASE_PATH . '/.env';
    if (is_file($envFile)) {
        Dotenv\Dotenv::createImmutable(BASE_PATH)->safeLoad();
    }

    App::boot();

    $timezone = App::get('timezone') ?? $_ENV['APP_TIMEZONE'] ?? getenv('APP_TIMEZONE') ?: 'America/Santiago';
    if (is_string($timezone) && trim($timezone) !== '') {
        date_default_timezone_set(trim($timezone));
    }

    $force = in_array('--force', $argv ?? [], true);
    $controller = new BackupController();
    $result = $controller->runScheduledAutoBackup($force, true);

    if ($result === null) {
        fwrite(STDOUT, '[OK] Respaldo automático al día (menos de 48 horas desde el último respaldo).' . PHP_EOL);
        exit(0);
    }

    fwrite(
        STDOUT,
        sprintf(
            '[OK] Respaldo automático generado: %s (ID #%d, rotados: %d)' . PHP_EOL,
            $result['respaldo']['archivo'],
            $result['respaldo']['id_respaldo'],
            count($result['rotados'])
        )
    );
    exit(0);
} catch (Throwable $exception) {
    fwrite(STDERR, '[ERROR] Falló el respaldo automático: ' . $exception->getMessage() . PHP_EOL);
    exit(1);
}
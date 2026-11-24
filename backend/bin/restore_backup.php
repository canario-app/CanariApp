#!/usr/bin/env php
<?php

/*
 * Restauración de un respaldo desde línea de comandos (SRS-RF029).
 *
 * Se usa para Neon: los archivos cifrados viven en el Docker de respaldo
 * (servicio respaldo-neon), no en Vercel. Requisitos:
 *   1. El administrador activa el modo mantenimiento (o emergencia) en el sitio.
 *   2. Ejecuta, en el PC donde corre el Docker:
 *        docker compose --profile neon exec respaldo-neon \
 *          php bin/restore_backup.php --id=12 --admin=admin@canariapp.cl --motivo="Texto"
 *
 * Usa DB_RESTORE_USER/DB_RESTORE_PASS (dueño de las tablas) y psql en una sola
 * transacción: si algo falla, la base queda exactamente como estaba.
 * Sin --id muestra los respaldos disponibles.
 */

declare(strict_types=1);

use CanariApp\Backend\Config\App;
use CanariApp\Backend\Config\Db;
use CanariApp\Backend\Controllers\BackupController;
use CanariApp\Backend\Models\Backup;

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

    App::boot();
    date_default_timezone_set((string) (App::get('timezone') ?: 'America/Santiago'));

    $options = getopt('', ['id:', 'admin:', 'motivo:']);
    $backupDir = BASE_PATH . '/storage/backups';

    if (!isset($options['id'])) {
        fwrite(STDOUT, 'Respaldos registrados en ' . (getenv('DB_HOST') ?: '?') . ':' . PHP_EOL);
        foreach ((new Backup())->findAllDetailed() as $row) {
            $file = basename((string) $row['archivo']);
            fwrite(STDOUT, sprintf(
                "  #%-4d %s  %s  %s\n",
                (int) $row['id_respaldo'],
                (string) $row['fecha_hora'],
                $file,
                is_file($backupDir . '/' . $file) ? '[archivo OK]' : '[archivo NO está en este Docker]'
            ));
        }
        fwrite(STDOUT, PHP_EOL . 'Uso: php bin/restore_backup.php --id=N --admin=correo_admin [--motivo="..."]' . PHP_EOL);
        exit(0);
    }

    $id = filter_var($options['id'], FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);
    if ($id === false) {
        throw new RuntimeException('--id debe ser un número entero positivo.');
    }

    $adminId = null;
    if (isset($options['admin']) && is_string($options['admin']) && trim($options['admin']) !== '') {
        $stmt = Db::getConnection()->prepare(
            "SELECT id_usuario FROM usuario WHERE lower(correo) = lower(:correo) AND rol = 'administrador' LIMIT 1"
        );
        $stmt->execute(['correo' => trim($options['admin'])]);
        $found = $stmt->fetchColumn();
        if ($found === false) {
            throw new RuntimeException('No existe un administrador con el correo indicado en --admin.');
        }
        $adminId = (int) $found;
    } else {
        throw new RuntimeException('Indique --admin=correo del administrador que autoriza la restauración (queda en auditoría).');
    }

    $motivo = isset($options['motivo']) && is_string($options['motivo']) && trim($options['motivo']) !== ''
        ? trim($options['motivo'])
        : sprintf('Restauración desde Docker de respaldo #%d (RF029)', $id);

    $result = (new BackupController())->restoreFromCli($id, $adminId, $motivo);

    fwrite(STDOUT, sprintf(
        '[OK] Respaldo #%d (%s) restaurado. Modo actual: %s. Recuerde volver a modo normal desde el panel.' . PHP_EOL,
        $id,
        (string) $result['respaldo']['archivo'],
        $result['modo_operacion']
    ));
    exit(0);
} catch (Throwable $exception) {
    fwrite(STDERR, '[ERROR] ' . $exception->getMessage() . PHP_EOL);
    exit(1);
}

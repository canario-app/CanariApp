<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\AuditHelper;
use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Helpers\Sanitizer;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Backup;
use Throwable;

/**
 * Controlador administrativo para registrar y rotar respaldos del sistema (DAT-003).
 *
 * Mantiene como máximo los 7 respaldos más recientes en la tabla respaldo
 * y elimina tanto los registros como los archivos rotados en storage/backups.
 */
class BackupController {
    private const SERVER_FIELDS = [
        'id_respaldo',
        'fecha_hora',
        'id_usuario',
    ];

    private Backup $backupModel;

    public function __construct(?Backup $backupModel = null) {
        $this->backupModel = $backupModel ?? new Backup();
    }

    /**
     * [Admin] Lista los respaldos vigentes (máximo 7 más recientes).
     */
    public function index(): void {
        $this->ensureAdminRole();

        try {
            $items = $this->backupModel->findAllDetailed();
            ResponseHelper::success([
                'items'         => $items,
                'total'         => count($items),
                'max_retention' => Backup::MAX_RETENTION,
            ], 'Listado de respaldos obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener los respaldos.');
        }
    }

    /**
     * [Admin] Muestra el detalle de un respaldo registrado.
     */
    public function show(int|string $id): void {
        $this->ensureAdminRole();

        $idRespaldo = Sanitizer::int($id, 1);
        if ($idRespaldo === null) {
            ResponseHelper::badRequest('El ID del respaldo no es válido.');
            return;
        }

        try {
            $item = $this->backupModel->findDetailed($idRespaldo);
            if ($item === null) {
                ResponseHelper::notFound('Respaldo no encontrado.');
                return;
            }

            ResponseHelper::success($item, 'Detalle del respaldo obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener el respaldo.');
        }
    }

    /**
     * [Admin] Genera/registra un respaldo y rota los excedentes más allá de los 7 más recientes.
     */
    public function store(): void {
        $adminUserId = $this->ensureAdminRole();

        $input = $this->readOptionalJsonBody();
        $errors = $this->validateCreate($input);
        if ($errors !== []) {
            ResponseHelper::validationError($errors);
            return;
        }

        $requestedFile = is_string($input['archivo'] ?? null) ? trim($input['archivo']) : '';
        $fileName = $requestedFile !== ''
            ? $requestedFile
            : sprintf('canariapp_backup_%s_%s.sql', date('Ymd_His'), bin2hex(random_bytes(3)));

        $motivo = is_string($input['motivo'] ?? null) && trim($input['motivo']) !== ''
            ? trim($input['motivo'])
            : 'Generación y registro de respaldo administrativo';

        $physicalDumpCreated = $this->tryCreatePhysicalDump($fileName);

        try {
            $result = $this->backupModel->registerAndRotate($fileName, $adminUserId);
            if (is_string($result)) {
                $this->respondDomainError($result);
                return;
            }

            $createdId = $result['id_respaldo'];
            $rotatedFiles = $result['rotated_files'];

            foreach ($rotatedFiles as $expiredFile) {
                $this->removePhysicalBackupIfExists($expiredFile);
            }

            $created = $this->backupModel->findDetailed($createdId) ?? [
                'id_respaldo' => $createdId,
                'archivo'     => $fileName,
                'id_usuario'  => $adminUserId,
            ];

            AuditHelper::log(
                action: 'insert',
                entity: 'respaldo',
                recordId: $createdId,
                newValue: [
                    'archivo'        => $fileName,
                    'volcado_fisico' => $physicalDumpCreated,
                    'rotados'        => $rotatedFiles,
                ],
                reason: $motivo,
                userId: $adminUserId
            );

            ResponseHelper::created([
                'respaldo'       => $created,
                'volcado_fisico' => $physicalDumpCreated,
                'rotados'        => $rotatedFiles,
            ], 'Respaldo registrado y rotación aplicada exitosamente.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo registrar el respaldo.');
        }
    }

    /**
     * @param array<string, mixed> $input
     * @return array<string, string>
     */
    private function validateCreate(array $input): array {
        $errors = [];

        foreach (self::SERVER_FIELDS as $field) {
            if (array_key_exists($field, $input)) {
                $errors[$field] = 'Este campo lo asigna el servidor.';
            }
        }

        if (array_key_exists('archivo', $input) && $input['archivo'] !== null) {
            if (!is_string($input['archivo']) || trim($input['archivo']) === '') {
                $errors['archivo'] = 'El nombre de archivo no puede estar vacío.';
            } else {
                $clean = trim($input['archivo']);
                if (mb_strlen($clean) > 255) {
                    $errors['archivo'] = 'El nombre de archivo no puede superar los 255 caracteres.';
                } elseif (preg_match('/^[A-Za-z0-9._-]+$/', $clean) !== 1 || str_contains($clean, '..')) {
                    $errors['archivo'] = 'El nombre de archivo solo puede contener letras, números, puntos, guiones y guiones bajos.';
                }
            }
        }

        if (array_key_exists('motivo', $input) && $input['motivo'] !== null && !is_string($input['motivo'])) {
            $errors['motivo'] = 'El motivo debe ser una cadena de texto.';
        }

        return $errors;
    }

    /**
     * Intenta generar el archivo SQL mediante pg_dump en storage/backups/ si está disponible.
     */
    private function tryCreatePhysicalDump(string $fileName): bool {
        if (!function_exists('exec')) {
            return false;
        }

        $backupDir = $this->backupDirectory();
        if (!is_dir($backupDir) && !@mkdir($backupDir, 0750, true) && !is_dir($backupDir)) {
            return false;
        }

        $dbHost = (string) ($_ENV['DB_HOST'] ?? getenv('DB_HOST') ?: '');
        $dbPort = (string) ($_ENV['DB_PORT'] ?? getenv('DB_PORT') ?: '5432');
        $dbName = (string) ($_ENV['DB_NAME'] ?? $_ENV['DB_DATABASE'] ?? getenv('DB_NAME') ?: '');
        $dbUser = (string) ($_ENV['DB_USER'] ?? $_ENV['DB_USERNAME'] ?? getenv('DB_USER') ?: '');
        $dbPass = (string) ($_ENV['DB_PASS'] ?? $_ENV['DB_PASSWORD'] ?? getenv('DB_PASS') ?: '');

        if ($dbHost === '' || $dbName === '' || $dbUser === '') {
            return false;
        }

        $targetPath = $backupDir . DIRECTORY_SEPARATOR . basename($fileName);
        $command = sprintf(
            'PGPASSWORD=%s pg_dump -h %s -p %s -U %s -F p -f %s %s 2>/dev/null',
            escapeshellarg($dbPass),
            escapeshellarg($dbHost),
            escapeshellarg($dbPort),
            escapeshellarg($dbUser),
            escapeshellarg($targetPath),
            escapeshellarg($dbName)
        );

        $output = [];
        $exitCode = 1;
        @exec($command, $output, $exitCode);

        return $exitCode === 0 && is_file($targetPath);
    }

    /**
     * Elimina del disco un respaldo antiguo retirado por la rotación de 7 archivos.
     */
    private function removePhysicalBackupIfExists(string $fileName): void {
        $safeName = basename(trim($fileName));
        if ($safeName === '' || $safeName === '.' || $safeName === '..') {
            return;
        }

        $targetPath = $this->backupDirectory() . DIRECTORY_SEPARATOR . $safeName;
        if (is_file($targetPath)) {
            @unlink($targetPath);
        }
    }

    private function backupDirectory(): string {
        return dirname(__DIR__, 2) . DIRECTORY_SEPARATOR . 'storage' . DIRECTORY_SEPARATOR . 'backups';
    }

    private function ensureAdminRole(): int {
        if (AuthMiddleware::userRole() !== 'administrador') {
            ResponseHelper::forbidden('Solo un administrador puede gestionar los respaldos del sistema.');
        }

        $userId = AuthMiddleware::userId();
        if ($userId === null || !is_numeric($userId)) {
            ResponseHelper::unauthorized('No hay un usuario autenticado.');
        }

        return (int) $userId;
    }

    /**
     * @return array<string, mixed>
     */
    private function readOptionalJsonBody(): array {
        $raw = file_get_contents('php://input');
        if ($raw === false || trim($raw) === '') {
            return [];
        }

        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            ResponseHelper::badRequest('El cuerpo de la petición debe ser un JSON válido.');
        }

        return $decoded;
    }

    private function respondDomainError(string $code): void {
        match ($code) {
            Backup::ERROR_DUPLICATE_FILE => ResponseHelper::conflict(
                'Ya existe un respaldo registrado con ese nombre de archivo.'
            ),
            Backup::ERROR_FORBIDDEN_ROLE => ResponseHelper::forbidden(
                'Solo un usuario con rol administrador puede registrar respaldos.'
            ),
            default => ResponseHelper::validationError([
                'respaldo' => 'Los datos del respaldo no cumplen las reglas de validación.',
            ]),
        };
    }
}
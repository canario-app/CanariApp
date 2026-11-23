<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\AuditHelper;
use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Helpers\Sanitizer;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\OperationMode;
use Throwable;

/**
 * Controlador para la gestión del modo de operación del sistema (SRS-RF028, DAT-003).
 *
 *  - Consulta de estado actual: disponible para cualquier usuario autenticado.
 *  - Historial, activación, diagnóstico y cierre: exclusivos del rol 'administrador'.
 */
class OperationModeController {
    private const SERVER_FIELDS = [
        'id_modo',
        'fecha_activacion',
        'fecha_desactivacion',
        'id_usuario',
        'id_usuario_cierre',
        'fecha_diagnostico',
    ];

    private OperationMode $modeModel;

    public function __construct(?OperationMode $modeModel = null) {
        $this->modeModel = $modeModel ?? new OperationMode();
    }

    /**
     * [Autenticado] Devuelve el estado operativo actual ('normal', 'mantenimiento' o 'emergencia').
     */
    public function status(): void {
        try {
            $active = $this->modeModel->findActive();

            if ($active === null) {
                ResponseHelper::success([
                    'estado' => 'normal',
                    'activo' => false,
                    'detalle' => null,
                ], 'El sistema opera en modo normal.');
                return;
            }

            ResponseHelper::success([
                'estado'  => $active['modo'],
                'activo'  => true,
                'detalle' => $active,
            ], 'Existe un modo de operación especial activo.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo consultar el estado del modo de operación.');
        }
    }

    /**
     * [Admin] Lista el historial de modos de operación registrados.
     */
    public function index(): void {
        $this->ensureAdminRole();

        try {
            $filters = [
                'modo'   => $_GET['modo'] ?? null,
                'activo' => $_GET['activo'] ?? null,
            ];

            $items = $this->modeModel->findAllDetailed($filters);
            ResponseHelper::success($items, 'Historial de modos de operación obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener el historial de modos de operación.');
        }
    }

    /**
     * [Admin] Muestra el detalle de un registro específico de modo de operación.
     */
    public function show(int|string $id): void {
        $this->ensureAdminRole();

        $idModo = Sanitizer::int($id, 1);
        if ($idModo === null) {
            ResponseHelper::badRequest('El ID del modo de operación no es válido.');
            return;
        }

        try {
            $item = $this->modeModel->findDetailed($idModo);
            if ($item === null) {
                ResponseHelper::notFound('Registro de modo de operación no encontrado.');
                return;
            }

            ResponseHelper::success($item, 'Detalle del modo de operación obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener el modo de operación.');
        }
    }

    /**
     * [Admin] Activa el modo 'mantenimiento' o 'emergencia'.
     */
    public function activate(): void {
        $adminUserId = $this->ensureAdminRole();

        $input = $this->readJsonBody();
        $errors = $this->validateActivate($input);
        if ($errors !== []) {
            ResponseHelper::validationError($errors);
            return;
        }

        $modo = trim((string) $input['modo']);
        $diagnostico = is_string($input['diagnostico'] ?? null) && trim($input['diagnostico']) !== ''
            ? trim($input['diagnostico'])
            : null;
        $motivo = is_string($input['motivo'] ?? null) && trim($input['motivo']) !== ''
            ? trim($input['motivo'])
            : ($diagnostico ?? 'Activación de modo ' . $modo);

        try {
            $result = $this->modeModel->activate($modo, $adminUserId, $diagnostico);
            if (is_string($result)) {
                $this->respondDomainError($result);
                return;
            }

            $createdId = (int) $result;
            $created = $this->modeModel->findDetailed($createdId) ?? ['id_modo' => $createdId, 'modo' => $modo];

            AuditHelper::log(
                action: 'insert',
                entity: 'modo_operacion',
                recordId: $createdId,
                newValue: [
                    'modo'        => $modo,
                    'diagnostico' => $diagnostico,
                ],
                reason: $motivo,
                userId: $adminUserId
            );

            ResponseHelper::created(
                $created,
                'Modo ' . $modo . ' activado exitosamente.'
            );
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo activar el modo de operación.');
        }
    }

    /**
     * [Admin] Registra o actualiza el diagnóstico técnico (plazo de 4h en emergencia)
     * y opcionalmente las acciones de recuperación en un modo activo.
     */
    public function diagnose(int|string $id): void {
        $adminUserId = $this->ensureAdminRole();

        $idModo = Sanitizer::int($id, 1);
        if ($idModo === null) {
            ResponseHelper::badRequest('El ID del modo de operación no es válido.');
            return;
        }

        $input = $this->readJsonBody();
        $errors = $this->validateDiagnosis($input);
        if ($errors !== []) {
            ResponseHelper::validationError($errors);
            return;
        }

        $diagnostico = trim((string) $input['diagnostico']);
        $acciones = is_string($input['acciones_recuperacion'] ?? null) && trim($input['acciones_recuperacion']) !== ''
            ? trim($input['acciones_recuperacion'])
            : null;

        try {
            $result = $this->modeModel->registerDiagnosis($idModo, $diagnostico, $acciones);
            if (is_string($result)) {
                $this->respondDomainError($result);
                return;
            }

            AuditHelper::log(
                action: 'update',
                entity: 'modo_operacion',
                recordId: $idModo,
                previousValue: [
                    'diagnostico'           => $result['previous']['diagnostico'],
                    'acciones_recuperacion' => $result['previous']['acciones_recuperacion'],
                ],
                newValue: [
                    'diagnostico'           => $diagnostico,
                    'acciones_recuperacion' => $result['updated']['acciones_recuperacion'],
                ],
                reason: 'Registro de diagnóstico técnico en modo ' . $result['previous']['modo'],
                userId: $adminUserId
            );

            ResponseHelper::success(
                $result['updated'],
                'Diagnóstico registrado exitosamente.'
            );
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo registrar el diagnóstico.');
        }
    }

    /**
     * [Admin] Desactiva un modo especial activo y retorna el sistema a modo normal.
     */
    public function deactivate(int|string $id): void {
        $adminUserId = $this->ensureAdminRole();

        $idModo = Sanitizer::int($id, 1);
        if ($idModo === null) {
            ResponseHelper::badRequest('El ID del modo de operación no es válido.');
            return;
        }

        $input = $this->readOptionalJsonBody();
        $errors = $this->validateDeactivate($input);
        if ($errors !== []) {
            ResponseHelper::validationError($errors);
            return;
        }

        $diagnostico = is_string($input['diagnostico'] ?? null) && trim($input['diagnostico']) !== ''
            ? trim($input['diagnostico'])
            : null;
        $acciones = is_string($input['acciones_recuperacion'] ?? null) && trim($input['acciones_recuperacion']) !== ''
            ? trim($input['acciones_recuperacion'])
            : null;
        $motivo = is_string($input['motivo'] ?? null) && trim($input['motivo']) !== ''
            ? trim($input['motivo'])
            : 'Retorno a modo de operación normal';

        try {
            $result = $this->modeModel->deactivate($idModo, $adminUserId, $diagnostico, $acciones);
            if (is_string($result)) {
                $this->respondDomainError($result);
                return;
            }

            AuditHelper::log(
                action: 'update',
                entity: 'modo_operacion',
                recordId: $idModo,
                previousValue: [
                    'modo'                => $result['previous']['modo'],
                    'fecha_desactivacion' => null,
                ],
                newValue: [
                    'fecha_desactivacion'   => $result['updated']['fecha_desactivacion'],
                    'diagnostico'           => $result['updated']['diagnostico'],
                    'acciones_recuperacion' => $result['updated']['acciones_recuperacion'],
                ],
                reason: $motivo,
                userId: $adminUserId
            );

            ResponseHelper::success(
                $result['updated'],
                'Modo ' . $result['previous']['modo'] . ' desactivado; el sistema volvió a modo normal.'
            );
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo desactivar el modo de operación.');
        }
    }

    /**
     * @param array<string, mixed> $input
     * @return array<string, string>
     */
    private function validateActivate(array $input): array {
        $errors = $this->rejectServerFields($input);

        $modo = is_string($input['modo'] ?? null) ? trim($input['modo']) : '';
        if (!in_array($modo, OperationMode::ALLOWED_MODES, true)) {
            $errors['modo'] = 'El modo debe ser "mantenimiento" o "emergencia".';
        }

        if (array_key_exists('diagnostico', $input) && $input['diagnostico'] !== null) {
            if (!is_string($input['diagnostico']) || trim($input['diagnostico']) === '') {
                $errors['diagnostico'] = 'Si envía diagnóstico, no puede estar vacío.';
            }
        }

        if (array_key_exists('motivo', $input) && $input['motivo'] !== null && !is_string($input['motivo'])) {
            $errors['motivo'] = 'El motivo debe ser una cadena de texto.';
        }

        return $errors;
    }

    /**
     * @param array<string, mixed> $input
     * @return array<string, string>
     */
    private function validateDiagnosis(array $input): array {
        $errors = $this->rejectServerFields($input);

        $diagnostico = is_string($input['diagnostico'] ?? null) ? trim($input['diagnostico']) : '';
        if ($diagnostico === '') {
            $errors['diagnostico'] = 'El texto del diagnóstico es obligatorio.';
        }

        if (array_key_exists('acciones_recuperacion', $input) && $input['acciones_recuperacion'] !== null) {
            if (!is_string($input['acciones_recuperacion']) || trim($input['acciones_recuperacion']) === '') {
                $errors['acciones_recuperacion'] = 'Si envía acciones de recuperación, no pueden estar vacías.';
            }
        }

        return $errors;
    }

    /**
     * @param array<string, mixed> $input
     * @return array<string, string>
     */
    private function validateDeactivate(array $input): array {
        $errors = $this->rejectServerFields($input);

        if (array_key_exists('diagnostico', $input) && $input['diagnostico'] !== null) {
            if (!is_string($input['diagnostico']) || trim($input['diagnostico']) === '') {
                $errors['diagnostico'] = 'El diagnóstico no puede ser una cadena vacía.';
            }
        }

        if (array_key_exists('acciones_recuperacion', $input) && $input['acciones_recuperacion'] !== null) {
            if (!is_string($input['acciones_recuperacion']) || trim($input['acciones_recuperacion']) === '') {
                $errors['acciones_recuperacion'] = 'Las acciones de recuperación no pueden ser una cadena vacía.';
            }
        }

        if (array_key_exists('motivo', $input) && $input['motivo'] !== null && !is_string($input['motivo'])) {
            $errors['motivo'] = 'El motivo debe ser una cadena de texto.';
        }

        return $errors;
    }

    /**
     * @param array<string, mixed> $input
     * @return array<string, string>
     */
    private function rejectServerFields(array $input): array {
        $errors = [];

        foreach (self::SERVER_FIELDS as $field) {
            if (array_key_exists($field, $input)) {
                $errors[$field] = 'Este campo lo asigna el servidor.';
            }
        }

        return $errors;
    }

    private function ensureAdminRole(): int {
        if (AuthMiddleware::userRole() !== 'administrador') {
            ResponseHelper::forbidden('Solo un administrador puede gestionar los modos de operación.');
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
    private function readJsonBody(): array {
        $raw = file_get_contents('php://input');
        if ($raw === false || trim($raw) === '') {
            ResponseHelper::badRequest('El cuerpo de la petición es obligatorio.');
        }

        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            ResponseHelper::badRequest('El cuerpo de la petición debe ser un JSON válido.');
        }

        return $decoded;
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
            OperationMode::ERROR_ALREADY_ACTIVE => ResponseHelper::conflict(
                'Ya existe un modo de operación especial activo. Debe desactivarlo antes de activar otro.'
            ),
            OperationMode::ERROR_NOT_FOUND => ResponseHelper::notFound(
                'Registro de modo de operación no encontrado.'
            ),
            OperationMode::ERROR_ALREADY_CLOSED => ResponseHelper::conflict(
                'Este modo de operación ya fue desactivado anteriormente.'
            ),
            OperationMode::ERROR_EMERGENCY_INCOMPLETE => ResponseHelper::validationError([
                'emergencia' => 'Para cerrar un modo de emergencia es obligatorio haber registrado el diagnóstico y las acciones de recuperación.',
            ]),
            OperationMode::ERROR_FORBIDDEN_ROLE => ResponseHelper::forbidden(
                'Solo un usuario con rol administrador puede ejecutar esta operación.'
            ),
            default => ResponseHelper::validationError([
                'modo_operacion' => 'Los datos enviados no cumplen las reglas del modo de operación.',
            ]),
        };
    }
}
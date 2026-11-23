<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\AuditHelper;
use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Helpers\Sanitizer;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Breeder;
use CanariApp\Backend\Models\Pair;
use Throwable;

/**
 * Controlador para los endpoints de parejas y asignación de jaulas (/api/v1/parejas).
 */
class PairController {
    private const SERVER_FIELDS = [
        'id_pareja',
        'id_criador',
    ];

    /** Metadatos aceptados cuando se activa el Modo de Corrección o se adjunta motivo. */
    private const CORRECTION_META_FIELDS = [
        'modo_correccion',
        'motivo',
        'id_solicitud',
    ];

    /** Campos de negocio que pueden ser auditados en ediciones. */
    private const TRACKABLE_FIELDS = [
        'id_macho',
        'id_hembra',
        'id_jaula',
        'estado',
        'fecha_fin',
    ];

    private Pair $pairModel;
    private Breeder $breederModel;

    public function __construct(?Pair $pairModel = null, ?Breeder $breederModel = null) {
        $this->pairModel = $pairModel ?? new Pair();
        $this->breederModel = $breederModel ?? new Breeder();
    }

    /**
     * Lista las parejas pertenecientes al criador autenticado.
     */
    public function index(): void {
        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $filters = [
                'estado'    => $_GET['estado'] ?? null,
                'id_macho'  => $_GET['id_macho'] ?? null,
                'id_hembra' => $_GET['id_hembra'] ?? null,
                'id_jaula'  => $_GET['id_jaula'] ?? null,
            ];

            $pairs = $this->pairModel->findAllForBreeder($id_criador, $filters);
            ResponseHelper::success($pairs, 'Listado de parejas obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener las parejas.');
        }
    }

    /**
     * Muestra el detalle de una pareja si pertenece al criador autenticado.
     */
    public function show(string|int $id): void {
        $id_pareja = $this->parsePositiveId($id);
        if ($id_pareja === null) {
            ResponseHelper::badRequest('El ID de la pareja no es válido.');
            return;
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $pair = $this->pairModel->findDetailed($id_pareja);
            if ($pair === null) {
                ResponseHelper::notFound('Pareja no encontrada.');
                return;
            }

            if ((int) $pair['id_criador'] !== $id_criador) {
                ResponseHelper::forbidden('No tienes permiso para acceder a esta pareja.');
                return;
            }

            ResponseHelper::success($pair, 'Detalle de pareja obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener la pareja.');
        }
    }

    /**
     * Crea una nueva pareja para el criador autenticado y registra auditoría.
     */
    public function store(): void {
        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        $input = $this->readJsonBody();
        $serverErrors = $this->validateServerFields($input, true, false);
        if ($serverErrors !== []) {
            ResponseHelper::validationError($serverErrors);
            return;
        }

        try {
            $result = AuditHelper::withoutAutoAudit(
                fn (): int|string => $this->pairModel->createForBreeder($input, $id_criador)
            );

            if (is_string($result)) {
                $this->respondDomainError($result);
                return;
            }

            $createdId = (int) $result;
            $created = $this->pairModel->findDetailed($createdId) ?? ['id_pareja' => $createdId];

            AuditHelper::log(
                action: 'insert',
                entity: 'pareja',
                recordId: $createdId,
                newValue: $created,
                reason: 'Registro de nueva pareja',
                userId: $this->currentUserId()
            );

            ResponseHelper::created($created, 'Pareja creada exitosamente.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo crear la pareja.');
        }
    }

    /**
     * Actualiza una pareja existente.
     *
     * Sin Modo de Corrección permite modificar jaula, estado o fecha_fin,
     * bloqueando id_macho e id_hembra con 403. Con Modo de Corrección activo
     * (`X-Correction-Mode: true` o `modo_correccion: true`) exige `motivo`,
     * permite reasignar progenitores (SRS-RF031) y audita la corrección.
     */
    public function update(string|int $id): void {
        $id_pareja = $this->parsePositiveId($id);
        if ($id_pareja === null) {
            ResponseHelper::badRequest('El ID de la pareja no es válido.');
            return;
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        $input = $this->readJsonBody();
        $isCorrectionMode = $this->isCorrectionModeActive($input);
        $serverErrors = $this->validateServerFields($input, false, $isCorrectionMode);
        if ($serverErrors !== []) {
            ResponseHelper::validationError($serverErrors);
            return;
        }

        try {
            $current = $this->pairModel->findDetailed($id_pareja);
            if ($current === null) {
                ResponseHelper::notFound('Pareja no encontrada.');
                return;
            }

            if ((int) $current['id_criador'] !== $id_criador) {
                ResponseHelper::forbidden('No tienes permiso para acceder a esta pareja.');
                return;
            }

            if (!$isCorrectionMode && (array_key_exists('id_macho', $input) || array_key_exists('id_hembra', $input))) {
                ResponseHelper::forbidden(
                    'Debe activar el Modo de Corrección para reasignar el macho o la hembra de una pareja.'
                );
                return;
            }

            $motivo = is_string($input['motivo'] ?? null) ? trim($input['motivo']) : '';

            if ($isCorrectionMode) {
                $requestId = isset($input['id_solicitud']) ? Sanitizer::int($input['id_solicitud'], 1) : null;

                $correctionResult = AuditHelper::withoutAutoAudit(
                    fn (): array|string => $this->pairModel->updateWithCorrection($id_pareja, $input, $id_criador)
                );

                if (is_string($correctionResult)) {
                    $this->respondDomainError($correctionResult);
                    return;
                }

                $trackedNew = $this->extractTrackedFields($input);

                AuditHelper::log(
                    action: 'correccion',
                    entity: 'pareja',
                    recordId: $id_pareja,
                    previousValue: $this->extractTrackedSnapshot($correctionResult['previous'], $trackedNew),
                    newValue: $trackedNew,
                    reason: $motivo,
                    userId: $this->currentUserId(),
                    requestingBreederId: $id_criador,
                    requestId: $requestId
                );

                ResponseHelper::success(
                    $correctionResult['updated'],
                    'Pareja corregida exitosamente en Modo de Corrección.'
                );
                return;
            }

            $result = AuditHelper::withoutAutoAudit(
                fn (): int|string => $this->pairModel->updateForBreeder($id_pareja, $input, $id_criador)
            );

            if (is_string($result)) {
                $this->respondDomainError($result);
                return;
            }

            $updated = $this->pairModel->findDetailed($id_pareja);
            $trackedNew = $this->extractTrackedFields($input);

            if ($trackedNew !== [] && $result > 0) {
                AuditHelper::log(
                    action: 'update',
                    entity: 'pareja',
                    recordId: $id_pareja,
                    previousValue: $this->extractTrackedSnapshot($current, $trackedNew),
                    newValue: $trackedNew,
                    reason: $motivo !== '' ? $motivo : 'Actualización de pareja',
                    userId: $this->currentUserId()
                );
            }

            ResponseHelper::success($updated, 'Pareja actualizada exitosamente.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo actualizar la pareja.');
        }
    }

    /**
     * Detecta si el cliente activó el Modo de Corrección por cabecera o cuerpo JSON.
     *
     * @param array<string, mixed> $input
     */
    private function isCorrectionModeActive(array $input): bool {
        $headerValue = $_SERVER['HTTP_X_CORRECTION_MODE'] ?? null;

        if ($headerValue === null && function_exists('getallheaders')) {
            $headers = array_change_key_case(getallheaders(), CASE_LOWER);
            $headerValue = $headers['x-correction-mode'] ?? null;
        }

        if ($headerValue !== null && filter_var($headerValue, FILTER_VALIDATE_BOOLEAN)) {
            return true;
        }

        return array_key_exists('modo_correccion', $input)
            && filter_var($input['modo_correccion'], FILTER_VALIDATE_BOOLEAN);
    }

    /**
     * Rechaza campos asignados por el servidor y valida metadatos de corrección.
     *
     * @param array<string, mixed> $input
     * @return array<string, string>
     */
    private function validateServerFields(array $input, bool $isCreate, bool $isCorrectionMode): array {
        $errors = [];

        foreach (self::SERVER_FIELDS as $field) {
            if (array_key_exists($field, $input)) {
                $errors[$field] = 'Este campo lo asigna el servidor.';
            }
        }

        if ($isCreate) {
            foreach (['estado', 'fecha_fin'] as $field) {
                if (array_key_exists($field, $input)) {
                    $errors[$field] = 'Este campo se asigna automáticamente al crear la pareja.';
                }
            }

            foreach (self::CORRECTION_META_FIELDS as $metaField) {
                if (array_key_exists($metaField, $input)) {
                    $errors[$metaField] = 'El Modo de Corrección solo aplica en edición de parejas.';
                }
            }

            return $errors;
        }

        if (array_key_exists('motivo', $input) && $input['motivo'] !== null && !is_string($input['motivo'])) {
            $errors['motivo'] = 'El motivo debe ser una cadena de texto.';
        } elseif (is_string($input['motivo'] ?? null) && mb_strlen(trim($input['motivo'])) > 500) {
            $errors['motivo'] = 'El motivo no puede superar los 500 caracteres.';
        }

        if ($isCorrectionMode) {
            $motivo = is_string($input['motivo'] ?? null) ? trim($input['motivo']) : '';
            if ($motivo === '') {
                $errors['motivo'] = 'Debe indicar el motivo al utilizar el Modo de Corrección.';
            }

            if (
                array_key_exists('id_solicitud', $input)
                && $input['id_solicitud'] !== null
                && Sanitizer::int($input['id_solicitud'], 1) === null
            ) {
                $errors['id_solicitud'] = 'El identificador de solicitud debe ser un entero positivo.';
            }
        }

        return $errors;
    }

    /**
     * @param array<string, mixed> $input
     * @return array<string, mixed>
     */
    private function extractTrackedFields(array $input): array {
        return array_intersect_key($input, array_flip(self::TRACKABLE_FIELDS));
    }

    /**
     * @param array<string, mixed> $current
     * @param array<string, mixed> $updatedFields
     * @return array<string, mixed>
     */
    private function extractTrackedSnapshot(array $current, array $updatedFields): array {
        return array_intersect_key($current, $updatedFields);
    }

    /**
     * Obtiene id_criador del usuario autenticado y responde 403/404 si no aplica.
     */
    private function resolveCurrentBreederId(): ?int {
        $authUser = AuthMiddleware::user();
        $rol = $authUser->rol ?? null;
        $userId = $authUser->sub ?? null;

        if ($rol !== 'criador' || $userId === null) {
            ResponseHelper::forbidden('Solo un criador puede gestionar parejas.');
            return null;
        }

        $breeder = $this->breederModel->findByUserId((int) $userId);
        if ($breeder === null) {
            ResponseHelper::notFound('Perfil de criador no encontrado.');
            return null;
        }

        return (int) $breeder['id_criador'];
    }

    private function currentUserId(): ?int {
        $userId = AuthMiddleware::userId();

        return $userId !== null && is_numeric($userId) ? (int) $userId : null;
    }

    /**
     * Valida y convierte un ID a entero positivo.
     */
    private function parsePositiveId(string|int $id): ?int {
        return Sanitizer::int($id, 1);
    }

    /**
     * Lee el cuerpo JSON; si está vacío devuelve [], y si es inválido responde 400.
     *
     * @return array<string, mixed>
     */
    private function readJsonBody(): array {
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

    /**
     * Traduce códigos de error de dominio a respuestas HTTP con mensajes específicos por regla.
     */
    private function respondDomainError(string $code): void {
        match ($code) {
            'correction_mode_required' => ResponseHelper::forbidden('Debe activar el Modo de Corrección para reasignar el macho o la hembra de una pareja.'),
            'not_found'                => ResponseHelper::notFound('Pareja no encontrada.'),
            'invalid_reference'        => ResponseHelper::validationError(['referencia' => 'El ejemplar o la jaula no existen o no pertenecen a tu criadero.'], 'Referencia inválida.'),
            'cage_occupied'            => ResponseHelper::conflict('La jaula ya está ocupada por una pareja activa.'),
            'female_active_pair'       => ResponseHelper::conflict('La hembra ya tiene pareja activa.'),
            'matings_annul_conflict'   => ResponseHelper::conflict('Una pareja con cruces registrados no puede anularse; debe reasignarse en Modo de Corrección.'),
            'consanguinity_conflict'   => ResponseHelper::conflict('Un ejemplar no puede ser progenitor en la pareja de la que es cría.'),
            'conflict'                 => ResponseHelper::conflict('No se pudo registrar o actualizar la pareja por una restricción de estado o ciclo de vida.'),
            default                    => ResponseHelper::validationError(['datos' => 'Los datos o fechas de la pareja no son válidos.'], 'Error de validación.'),
        };
    }
}
<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\AuditHelper;
use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Breeder;
use CanariApp\Backend\Models\Canary;

class CanaryController {
    /** Campos del anillo y del ejemplar que puede escribir el cliente. */
    private const WRITABLE_FIELDS = [
        'anillo',
        'id_club',
        'numero_socio',
        'temporada',
        'sexo',
        'id_variedad',
    ];

    /** Campos que siempre asigna el servidor o la base de datos. */
    private const SERVER_FIELDS = [
        'id_canario',
        'fecha_registro',
        'requiere_revision',
    ];

    /** Metadatos aceptados cuando se activa el Modo de Corrección en PATCH/PUT. */
    private const CORRECTION_META_FIELDS = [
        'modo_correccion',
        'motivo',
        'id_solicitud',
        'anular_parejas',
    ];

    /**
     * [Criador] Lista sus canarios. [Admin] Recibe 403 Forbidden.
     */
    public function index(): void {
        $this->ensureBreederRole();

        $model = new Canary();
        $idCriador = $this->currentBreederId();

        $filters = [
            'buscar'      => $this->queryString('buscar'),
            'id_club'     => $this->queryString('id_club'),
            'id_variedad' => $this->queryString('id_variedad'),
            'temporada'   => $this->queryString('temporada'),
        ];

        ResponseHelper::success(
            $model->findAllDetailed($filters, $idCriador),
            'Listado de canarios obtenido.'
        );
    }

    /**
     * [Criador] Muestra un canario propio. [Admin] Recibe 403 Forbidden.
     */
    public function show(int|string $id): void {
        $this->ensureBreederRole();

        $idCanario = $this->parseId($id);
        $model = new Canary();
        $canario = $model->findDetailed($idCanario);

        if ($canario === null) {
            ResponseHelper::notFound('Canario no encontrado.');
        }

        $this->assertVisible($canario);

        ResponseHelper::success($canario, 'Detalle del canario obtenido.');
    }

    /**
     * [Criador] Crea un canario en su criadero. [Admin] Recibe 403 Forbidden.
     */
    public function store(): void {
        $this->ensureBreederRole();

        $input = $this->getJsonInput();
        $errors = $this->validate($input, true, false);
        if ($errors !== []) {
            ResponseHelper::validationError($errors);
        }

        $idCriador = $this->currentBreederId();
        $filtered = $this->filterFields($input);

        $model = new Canary();
        $result = $model->createForBreeder($filtered, $idCriador);

        if (is_string($result)) {
            $this->handleError($result);
            return;
        }

        $createdId = (int) $result;
        $creado = $model->findDetailed($createdId) ?? ['id_canario' => $createdId];

        AuditHelper::log(
            action: 'insert',
            entity: 'canario',
            recordId: $createdId,
            newValue: $filtered,
            reason: 'Registro de nuevo ejemplar',
            userId: (int) AuthMiddleware::userId()
        );

        ResponseHelper::created($creado, 'Canario creado exitosamente.');
    }

    /**
     * [Criador] Actualiza un canario propio.
     *
     * Sin Modo de Corrección bloquea la modificación de `anillo` y de `sexo`
     * ya asignado. Con Modo de Corrección (`X-Correction-Mode: true` o
     * `modo_correccion: true`) exige `motivo` y audita la corrección.
     */
    public function update(int|string $id): void {
        $this->ensureBreederRole();

        $idCanario = $this->parseId($id);
        $input = $this->getJsonInput();
        $isCorrectionMode = $this->isCorrectionModeActive($input);
        $isPatch = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'PATCH') === 'PATCH';

        $errors = $this->validate($input, false, $isCorrectionMode);
        if ($errors !== []) {
            ResponseHelper::validationError($errors);
        }

        $model = new Canary();
        $actual = $model->findDetailed($idCanario);
        if ($actual === null) {
            ResponseHelper::notFound('Canario no encontrado.');
        }

        $this->assertVisible($actual);

        // Bloquea intento de modificar anillo o sobrescribir sexo sin Modo de Corrección
        if (!$isCorrectionMode) {
            if (
                array_key_exists('anillo', $input)
                && ($isPatch || trim((string) $input['anillo']) !== (string) $actual['anillo'])
            ) {
                ResponseHelper::forbidden(
                    'Debe activar el Modo de Corrección para modificar el anillo de un ejemplar.'
                );
            }

            if (
                array_key_exists('sexo', $input)
                && $actual['sexo'] !== null
                && ($isPatch || $input['sexo'] !== $actual['sexo'])
            ) {
                ResponseHelper::forbidden(
                    'Debe activar el Modo de Corrección para modificar el sexo de un ejemplar ya sexado.'
                );
            }
        }

        $targetBreederId = $this->currentBreederId();
        $filtered = $this->filterFields($input);

        if ($isCorrectionMode) {
            $reason = trim((string) ($input['motivo'] ?? ''));
            $requestId = isset($input['id_solicitud']) ? $this->positiveInt($input['id_solicitud']) : null;
            $annulPairs = filter_var($input['anular_parejas'] ?? false, FILTER_VALIDATE_BOOLEAN);

            $correctionResult = $model->updateWithCorrection(
                $idCanario,
                $filtered,
                $targetBreederId,
                $annulPairs
            );

            if (is_string($correctionResult)) {
                $this->handleError($correctionResult);
                return;
            }

            AuditHelper::log(
                action: 'correccion',
                entity: 'canario',
                recordId: $idCanario,
                previousValue: $this->extractTrackedSnapshot($correctionResult['previous'], $filtered),
                newValue: $filtered,
                reason: $reason,
                userId: (int) AuthMiddleware::userId(),
                requestingBreederId: $targetBreederId,
                requestId: $requestId
            );

            ResponseHelper::success(
                $correctionResult['updated'],
                'Canario corregido exitosamente en Modo de Corrección.'
            );
        }

        $result = $model->updateForBreeder($idCanario, $filtered, $targetBreederId);

        if (is_string($result)) {
            $this->handleError($result);
            return;
        }

        $actualizado = $model->findDetailed($idCanario);

        if ($filtered !== []) {
            AuditHelper::log(
                action: 'update',
                entity: 'canario',
                recordId: $idCanario,
                previousValue: $this->extractTrackedSnapshot($actual, $filtered),
                newValue: $filtered,
                reason: 'Actualización de datos del ejemplar',
                userId: (int) AuthMiddleware::userId()
            );
        }

        ResponseHelper::success($actualizado, 'Canario actualizado exitosamente.');
    }

    /**
     * Exige que el usuario autenticado tenga rol 'criador'; devuelve 403 en caso contrario.
     */
    private function ensureBreederRole(): void {
        if (AuthMiddleware::userRole() !== 'criador') {
            ResponseHelper::forbidden('Solo los usuarios con rol criador pueden acceder a este recurso.');
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
     * Extrae únicamente los valores previos de los campos que se intentan actualizar.
     *
     * @param array<string, mixed> $current
     * @param array<string, mixed> $updatedFields
     * @return array<string, mixed>
     */
    private function extractTrackedSnapshot(array $current, array $updatedFields): array {
        return array_intersect_key($current, $updatedFields);
    }

    /**
     * Un criador solo puede acceder a los ejemplares de su criadero.
     *
     * @param array<string, mixed> $canario
     */
    private function assertVisible(array $canario): void {
        if ((int) $canario['id_criador'] !== $this->currentBreederId()) {
            ResponseHelper::forbidden('El canario pertenece a otro criador.');
        }
    }

    /**
     * Valida el cuerpo de la petición con mensajes por campo.
     *
     * @param array<string, mixed> $input
     * @return array<string, string>
     */
    private function validate(array $input, bool $isCreate, bool $isCorrectionMode): array {
        $errors = [];

        foreach (self::SERVER_FIELDS as $field) {
            if (array_key_exists($field, $input)) {
                $errors[$field] = 'Este campo lo asigna el servidor.';
            }
        }

        if (array_key_exists('id_criador', $input)) {
            $errors['id_criador'] = $isCreate
                ? 'El criador se toma del usuario autenticado.'
                : 'El criador dueño del ejemplar no se puede modificar.';
        }

        if ($isCreate) {
            foreach (self::CORRECTION_META_FIELDS as $metaField) {
                if (array_key_exists($metaField, $input)) {
                    $errors[$metaField] = 'El Modo de Corrección solo aplica en edición de ejemplares.';
                }
            }
        } elseif ($isCorrectionMode) {
            $motivo = is_string($input['motivo'] ?? null) ? trim($input['motivo']) : '';
            if ($motivo === '') {
                $errors['motivo'] = 'Debe indicar el motivo al utilizar el Modo de Corrección.';
            } elseif (mb_strlen($motivo) > 500) {
                $errors['motivo'] = 'El motivo no puede superar los 500 caracteres.';
            }

            if (
                array_key_exists('id_solicitud', $input)
                && $input['id_solicitud'] !== null
                && $this->positiveInt($input['id_solicitud']) === null
            ) {
                $errors['id_solicitud'] = 'El identificador de solicitud debe ser un entero positivo.';
            }
        }

        foreach (self::WRITABLE_FIELDS as $field) {
            $present = array_key_exists($field, $input);
            if (!$present && !$isCreate) {
                continue;
            }
            if (!$present) {
                $errors[$field] = 'Este campo es obligatorio.';
                continue;
            }

            $value = $input[$field];
            $temporada = $this->positiveInt($value);
            $valid = match ($field) {
                'anillo' => is_scalar($value)
                    && preg_match('/^[0-9]{1,6}$/', trim((string) $value)) === 1,
                'numero_socio' => is_scalar($value)
                    && preg_match('/^[0-9]{1,5}$/', trim((string) $value)) === 1,
                'sexo' => is_string($value) && in_array($value, ['M', 'H'], true),
                'id_club', 'id_variedad' => $this->positiveInt($value) !== null,
                'temporada' => $temporada !== null && $temporada >= 1000 && $temporada <= 9999,
            };

            if (!$valid) {
                $errors[$field] = $this->validationMessage($field);
            }
        }

        return $errors;
    }

    /**
     * @param array<string, mixed> $input
     * @return array<string, mixed>
     */
    private function filterFields(array $input): array {
        return array_intersect_key($input, array_flip(self::WRITABLE_FIELDS));
    }

    private function validationMessage(string $field): string {
        return match ($field) {
            'anillo' => 'El número de anillo debe tener entre 1 y 6 dígitos.',
            'numero_socio' => 'El número de socio debe tener entre 1 y 5 dígitos.',
            'sexo' => 'El sexo debe ser "M" o "H".',
            'id_club', 'id_variedad' => 'Debe indicar un identificador válido.',
            'temporada' => 'La temporada debe ser un año de 4 dígitos.',
            default => 'El valor no es válido.',
        };
    }

    private function handleError(string $code): void {
        match ($code) {
            'correction_mode_required' => ResponseHelper::forbidden(
                'Debe activar el Modo de Corrección para modificar el sexo o el anillo del ejemplar.'
            ),
            'active_pairs_conflict' => ResponseHelper::conflict(
                'El ejemplar participa en parejas activas o finalizadas; envíe anular_parejas=true o reasígnelas antes de corregir el sexo.'
            ),
            'pairs_with_matings_conflict' => ResponseHelper::conflict(
                'El ejemplar tiene parejas con cruces registrados que no pueden anularse; debe reasignarlas antes de corregir el sexo.'
            ),
            'conflict_anillo' => ResponseHelper::conflict('El anillo no está disponible.'),
            'invalid_reference' => ResponseHelper::validationError([
                'canario' => 'El club, la variedad o el criador no existen.',
            ]),
            'not_found' => ResponseHelper::notFound('Canario no encontrado.'),
            default => ResponseHelper::validationError([
                'canario' => 'Los datos no cumplen las reglas de registro del ejemplar.',
            ]),
        };
    }

    /**
     * ID del criadero asociado al usuario autenticado.
     */
    private function currentBreederId(): int {
        $userId = AuthMiddleware::userId();
        if ($userId === null) {
            ResponseHelper::unauthorized('No hay un usuario autenticado.');
        }

        $perfil = (new Breeder())->findByUserId((int) $userId);
        if ($perfil === null) {
            ResponseHelper::forbidden('El usuario actual no tiene un criadero asociado.');
        }

        return (int) $perfil['id_criador'];
    }

    private function parseId(int|string $id): int {
        $value = is_int($id) ? $id : filter_var(trim($id), FILTER_VALIDATE_INT);
        if ($value === false || $value <= 0) {
            ResponseHelper::badRequest('El ID del canario no es válido.');
        }

        return (int) $value;
    }

    private function positiveInt(mixed $value): ?int {
        if (!is_int($value) && !(is_string($value) && preg_match('/^[0-9]+$/', trim($value)) === 1)) {
            return null;
        }

        $integer = (int) $value;

        return $integer > 0 ? $integer : null;
    }

    private function queryString(string $key): ?string {
        $value = $_GET[$key] ?? null;

        return is_scalar($value) ? trim((string) $value) : null;
    }

    /**
     * Lee y decodifica el cuerpo JSON de la petición.
     *
     * @return array<string, mixed>
     */
    private function getJsonInput(): array {
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
}
<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\AuditHelper;
use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Helpers\Sanitizer;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Breeder;
use CanariApp\Backend\Models\Canary;
use CanariApp\Backend\Models\CorrectionRequest;
use Throwable;

/**
 * Controlador para las solicitudes de corrección de sexo o variedad (SRS-RF033).
 *
 *  - Criador: lista sus solicitudes, crea nuevas y cancela solicitudes pendientes.
 *  - Administrador: lista todas las solicitudes, rechaza o aprueba aplicando
 *    directamente la corrección sobre el ejemplar solicitado.
 */
class CorrectionRequestController {
    private const SERVER_FIELDS = [
        'id_solicitud',
        'id_criador',
        'fecha_solicitud',
        'fecha_cierre',
    ];

    private CorrectionRequest $requestModel;
    private Breeder $breederModel;

    public function __construct(
        ?CorrectionRequest $requestModel = null,
        ?Breeder $breederModel = null
    ) {
        $this->requestModel = $requestModel ?? new CorrectionRequest();
        $this->breederModel = $breederModel ?? new Breeder();
    }

    /**
     * [Criador] Lista las solicitudes de corrección del criadero autenticado.
     */
    public function index(): void {
        $idCriador = $this->resolveCurrentBreederId();
        if ($idCriador === null) {
            return;
        }

        try {
            $filters = [
                'estado'          => $_GET['estado'] ?? null,
                'dato_a_corregir' => $_GET['dato_a_corregir'] ?? null,
                'id_canario'      => $_GET['id_canario'] ?? null,
            ];

            $items = $this->requestModel->findAllDetailed($filters, $idCriador);
            ResponseHelper::success($items, 'Listado de solicitudes de corrección obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener las solicitudes de corrección.');
        }
    }

    /**
     * [Criador] Muestra el detalle de una solicitud propia.
     */
    public function show(int|string $id): void {
        $idSolicitud = $this->parsePositiveId($id);
        if ($idSolicitud === null) {
            ResponseHelper::badRequest('El ID de la solicitud no es válido.');
            return;
        }

        $idCriador = $this->resolveCurrentBreederId();
        if ($idCriador === null) {
            return;
        }

        try {
            $item = $this->requestModel->findDetailed($idSolicitud);
            if ($item === null) {
                ResponseHelper::notFound('Solicitud de corrección no encontrada.');
                return;
            }

            if ((int) $item['id_criador'] !== $idCriador) {
                ResponseHelper::forbidden('No tienes permiso para acceder a esta solicitud.');
                return;
            }

            ResponseHelper::success($item, 'Detalle de solicitud de corrección obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener la solicitud de corrección.');
        }
    }

    /**
     * [Criador] Crea una nueva solicitud de corrección ('sexo' o 'variedad').
     */
    public function store(): void {
        $idCriador = $this->resolveCurrentBreederId();
        if ($idCriador === null) {
            return;
        }

        $input = $this->readJsonBody();
        $errors = $this->validateCreate($input);
        if ($errors !== []) {
            ResponseHelper::validationError($errors);
            return;
        }

        $idCanario = (int) Sanitizer::int($input['id_canario'], 1);
        $datoACorregir = trim((string) $input['dato_a_corregir']);
        $motivo = trim((string) $input['motivo']);

        try {
            $result = $this->requestModel->createForBreeder(
                $idCanario,
                $datoACorregir,
                $motivo,
                $idCriador
            );

            if (is_string($result)) {
                $this->respondDomainError($result);
                return;
            }

            $createdId = (int) $result;
            $created = $this->requestModel->findDetailed($createdId) ?? ['id_solicitud' => $createdId];

            AuditHelper::log(
                action: 'insert',
                entity: 'solicitud_correccion',
                recordId: $createdId,
                newValue: [
                    'id_canario'      => $idCanario,
                    'dato_a_corregir' => $datoACorregir,
                    'estado'          => 'pendiente',
                ],
                reason: $motivo,
                userId: $this->currentUserId(),
                requestingBreederId: $idCriador,
                requestId: $createdId
            );

            ResponseHelper::created($created, 'Solicitud de corrección creada exitosamente.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo crear la solicitud de corrección.');
        }
    }

    /**
     * [Criador] Cancela una solicitud pendiente propia.
     */
    public function cancel(int|string $id): void {
        $idSolicitud = $this->parsePositiveId($id);
        if ($idSolicitud === null) {
            ResponseHelper::badRequest('El ID de la solicitud no es válido.');
            return;
        }

        $idCriador = $this->resolveCurrentBreederId();
        if ($idCriador === null) {
            return;
        }

        $input = $this->readOptionalJsonBody();
        $cancelReason = is_string($input['motivo'] ?? null) && trim($input['motivo']) !== ''
            ? trim($input['motivo'])
            : 'Cancelación de solicitud por el criador';

        try {
            $result = $this->requestModel->cancelByBreeder($idSolicitud, $idCriador);
            if (is_string($result)) {
                $this->respondDomainError($result);
                return;
            }

            AuditHelper::log(
                action: 'update',
                entity: 'solicitud_correccion',
                recordId: $idSolicitud,
                previousValue: ['estado' => $result['previous']['estado']],
                newValue: ['estado' => 'cancelada'],
                reason: $cancelReason,
                userId: $this->currentUserId(),
                requestingBreederId: $idCriador,
                requestId: $idSolicitud
            );

            ResponseHelper::success($result['updated'], 'Solicitud de corrección cancelada.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo cancelar la solicitud de corrección.');
        }
    }

    /**
     * [Admin] Lista todas las solicitudes de corrección del sistema.
     */
    public function adminIndex(): void {
        $this->ensureAdminRole();

        try {
            $filters = [
                'estado'          => $_GET['estado'] ?? null,
                'dato_a_corregir' => $_GET['dato_a_corregir'] ?? null,
                'id_canario'      => $_GET['id_canario'] ?? null,
                'id_criador'      => $_GET['id_criador'] ?? null,
            ];

            $items = $this->requestModel->findAllDetailed($filters, null);
            ResponseHelper::success($items, 'Listado administrativo de solicitudes obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener las solicitudes de corrección.');
        }
    }

    /**
     * [Admin] Muestra el detalle de cualquier solicitud de corrección.
     */
    public function adminShow(int|string $id): void {
        $this->ensureAdminRole();

        $idSolicitud = $this->parsePositiveId($id);
        if ($idSolicitud === null) {
            ResponseHelper::badRequest('El ID de la solicitud no es válido.');
            return;
        }

        try {
            $item = $this->requestModel->findDetailed($idSolicitud);
            if ($item === null) {
                ResponseHelper::notFound('Solicitud de corrección no encontrada.');
                return;
            }

            ResponseHelper::success($item, 'Detalle de solicitud de corrección obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener la solicitud de corrección.');
        }
    }

    /**
     * [Admin] Resuelve una solicitud pendiente ('aprobada' o 'rechazada').
     * Cuando se aprueba ('aprobada'), aplica directamente la corrección sobre el ejemplar
     * en la misma transacción (SRS-RF033).
     */
    public function resolve(int|string $id): void {
        $this->ensureAdminRole();

        $idSolicitud = $this->parsePositiveId($id);
        if ($idSolicitud === null) {
            ResponseHelper::badRequest('El ID de la solicitud no es válido.');
            return;
        }

        $input = $this->readJsonBody();
        $errors = $this->validateResolution($input);
        if ($errors !== []) {
            ResponseHelper::validationError($errors);
            return;
        }

        $nuevoEstado = trim((string) $input['estado']);
        $observacion = is_string($input['motivo'] ?? null) && trim($input['motivo']) !== ''
            ? trim($input['motivo'])
            : ($nuevoEstado === 'aprobada'
                ? 'Solicitud aprobada y corrección aplicada por administrador (RF033)'
                : 'Solicitud rechazada por administrador');

        try {
            if ($nuevoEstado === 'rechazada') {
                $result = $this->requestModel->resolveByAdmin($idSolicitud, 'rechazada');
                if (is_string($result)) {
                    $this->respondDomainError($result);
                    return;
                }

                $breederId = (int) $result['previous']['id_criador'];

                AuditHelper::log(
                    action: 'update',
                    entity: 'solicitud_correccion',
                    recordId: $idSolicitud,
                    previousValue: ['estado' => $result['previous']['estado']],
                    newValue: ['estado' => 'rechazada'],
                    reason: $observacion,
                    userId: $this->currentUserId(),
                    requestingBreederId: $breederId,
                    requestId: $idSolicitud
                );

                ResponseHelper::success(
                    $result['updated'],
                    'Solicitud de corrección rechazada.'
                );
                return;
            }

            $existing = $this->requestModel->findDetailed($idSolicitud);
            if ($existing === null) {
                ResponseHelper::notFound('Solicitud de corrección no encontrada.');
                return;
            }

            if ($existing['estado'] !== 'pendiente') {
                ResponseHelper::conflict('Solo se pueden aprobar solicitudes en estado pendiente.');
                return;
            }

            $datoACorregir = (string) $existing['dato_a_corregir'];
            $correctionPayload = [];

            if ($datoACorregir === 'sexo') {
                $sexo = $input['sexo'] ?? null;
                if (!is_string($sexo) || !in_array($sexo, ['M', 'H'], true)) {
                    ResponseHelper::validationError([
                        'sexo' => 'Debe indicar el nuevo sexo ("M" o "H") para aprobar y aplicar esta solicitud.',
                    ]);
                    return;
                }
                $correctionPayload['sexo'] = $sexo;
            } elseif ($datoACorregir === 'variedad') {
                $idVariedad = Sanitizer::int($input['id_variedad'] ?? null, 1);
                if ($idVariedad === null) {
                    ResponseHelper::validationError([
                        'id_variedad' => 'Debe indicar el nuevo id_variedad válido para aprobar y aplicar esta solicitud.',
                    ]);
                    return;
                }
                $correctionPayload['id_variedad'] = $idVariedad;
            }

            $adminUserId = $this->currentUserId();
            if ($adminUserId === null) {
                ResponseHelper::unauthorized('No hay un usuario autenticado.');
                return;
            }

            $annulPairs = filter_var($input['anular_parejas'] ?? false, FILTER_VALIDATE_BOOLEAN);

            $canaryModel = new Canary();
            $applied = $canaryModel->applyAdminCorrection(
                (int) $existing['id_canario'],
                $correctionPayload,
                $adminUserId,
                $observacion,
                $idSolicitud,
                $annulPairs
            );

            if (is_string($applied)) {
                $this->respondCanaryCorrectionError($applied);
                return;
            }

            $responseData = $applied['request'];
            $responseData['canario'] = $applied['updated'];

            ResponseHelper::success(
                $responseData,
                'Solicitud aprobada y corrección aplicada al ejemplar exitosamente.'
            );
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo resolver la solicitud de corrección.');
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

        if (array_key_exists('estado', $input)) {
            $errors['estado'] = 'Toda solicitud se crea automáticamente en estado pendiente.';
        }

        if (Sanitizer::int($input['id_canario'] ?? null, 1) === null) {
            $errors['id_canario'] = 'Debe indicar un identificador de canario válido.';
        }

        $dato = is_string($input['dato_a_corregir'] ?? null) ? trim($input['dato_a_corregir']) : '';
        if (!in_array($dato, CorrectionRequest::ALLOWED_FIELDS, true)) {
            $errors['dato_a_corregir'] = 'El dato a corregir debe ser "sexo" o "variedad".';
        }

        $motivo = is_string($input['motivo'] ?? null) ? trim($input['motivo']) : '';
        if ($motivo === '') {
            $errors['motivo'] = 'El motivo de la solicitud es obligatorio.';
        } elseif (mb_strlen($motivo) > 1000) {
            $errors['motivo'] = 'El motivo no puede superar los 1000 caracteres.';
        }

        return $errors;
    }

    /**
     * @param array<string, mixed> $input
     * @return array<string, string>
     */
    private function validateResolution(array $input): array {
        $errors = [];

        foreach (self::SERVER_FIELDS as $field) {
            if (array_key_exists($field, $input)) {
                $errors[$field] = 'Este campo lo asigna el servidor.';
            }
        }

        $estado = is_string($input['estado'] ?? null) ? trim($input['estado']) : '';
        if (!in_array($estado, CorrectionRequest::RESOLUTION_STATES, true)) {
            $errors['estado'] = 'El estado de resolución debe ser "aprobada" o "rechazada".';
        }

        if (array_key_exists('motivo', $input) && $input['motivo'] !== null && !is_string($input['motivo'])) {
            $errors['motivo'] = 'El motivo debe ser una cadena de texto.';
        } elseif (is_string($input['motivo'] ?? null) && mb_strlen(trim($input['motivo'])) > 1000) {
            $errors['motivo'] = 'El motivo no puede superar los 1000 caracteres.';
        }

        return $errors;
    }

    private function ensureAdminRole(): void {
        if (AuthMiddleware::userRole() !== 'administrador') {
            ResponseHelper::forbidden('Solo un administrador puede realizar esta acción.');
        }
    }

    private function resolveCurrentBreederId(): ?int {
        $authUser = AuthMiddleware::user();
        $rol = $authUser->rol ?? null;
        $userId = $authUser->sub ?? null;

        if ($rol !== 'criador' || $userId === null) {
            ResponseHelper::forbidden('Solo un criador puede gestionar sus solicitudes de corrección.');
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

    private function parsePositiveId(string|int $id): ?int {
        return Sanitizer::int($id, 1);
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
            CorrectionRequest::ERROR_NOT_FOUND => ResponseHelper::notFound(
                'El ejemplar o la solicitud de corrección no existen.'
            ),
            CorrectionRequest::ERROR_FORBIDDEN_CANARY => ResponseHelper::forbidden(
                'Solo el criador propietario del ejemplar puede gestionar esta solicitud.'
            ),
            CorrectionRequest::ERROR_CONFLICT_PENDING => ResponseHelper::conflict(
                'El ejemplar ya tiene una solicitud de corrección pendiente.'
            ),
            CorrectionRequest::ERROR_INVALID_STATE => ResponseHelper::conflict(
                'Solo se pueden modificar solicitudes que se encuentren en estado pendiente.'
            ),
            default => ResponseHelper::validationError([
                'solicitud' => 'Los datos de la solicitud de corrección no son válidos.',
            ]),
        };
    }

    private function respondCanaryCorrectionError(string $code): void {
        match ($code) {
            'pending_request_required' => ResponseHelper::conflict(
                'El ejemplar no tiene una solicitud de corrección pendiente.'
            ),
            'request_not_pending' => ResponseHelper::conflict(
                'La solicitud de corrección ya fue resuelta o cancelada.'
            ),
            'correction_field_mismatch' => ResponseHelper::validationError([
                'correccion' => 'El campo enviado no coincide con el dato solicitado en la petición.',
            ]),
            'active_pairs_conflict' => ResponseHelper::conflict(
                'El ejemplar participa en parejas activas o finalizadas; envíe anular_parejas=true o reasígnelas antes de corregir el sexo.'
            ),
            'pairs_with_matings_conflict' => ResponseHelper::conflict(
                'El ejemplar tiene parejas con cruces registrados que no pueden anularse; debe reasignarlas antes de corregir el sexo.'
            ),
            'invalid_reference' => ResponseHelper::validationError([
                'id_variedad' => 'La variedad indicada no existe.',
            ]),
            'not_found' => ResponseHelper::notFound('Canario no encontrado.'),
            default => ResponseHelper::validationError([
                'correccion' => 'Los datos de corrección no son válidos.',
            ]),
        };
    }
}
<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

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
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $pair = $this->pairModel->findDetailed($id_pareja);
            if ($pair === null) {
                ResponseHelper::notFound('Pareja no encontrada.');
            }

            if ((int) $pair['id_criador'] !== $id_criador) {
                ResponseHelper::forbidden('No tienes permiso para acceder a esta pareja.');
            }

            ResponseHelper::success($pair, 'Detalle de pareja obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener la pareja.');
        }
    }

    /**
     * Crea una nueva pareja para el criador autenticado.
     */
    public function store(): void {
        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        $input = $this->readJsonBody();
        $serverErrors = $this->validateServerFields($input, true);
        if ($serverErrors !== []) {
            ResponseHelper::validationError($serverErrors);
        }

        try {
            $result = $this->pairModel->createForBreeder($input, $id_criador);
            if (is_string($result)) {
                $this->respondDomainError($result);
            }

            $created = $this->pairModel->findDetailed((int) $result);
            ResponseHelper::created($created, 'Pareja creada exitosamente.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo crear la pareja.');
        }
    }

    /**
     * Actualiza una pareja existente (jaula, estado o fecha de cierre).
     */
    public function update(string|int $id): void {
        $id_pareja = $this->parsePositiveId($id);
        if ($id_pareja === null) {
            ResponseHelper::badRequest('El ID de la pareja no es válido.');
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        $input = $this->readJsonBody();
        $serverErrors = $this->validateServerFields($input, false);
        if ($serverErrors !== []) {
            ResponseHelper::validationError($serverErrors);
        }

        try {
            $result = $this->pairModel->updateForBreeder($id_pareja, $input, $id_criador);
            if (is_string($result)) {
                $this->respondDomainError($result);
            }

            $updated = $this->pairModel->findDetailed($id_pareja);
            ResponseHelper::success($updated, 'Pareja actualizada exitosamente.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo actualizar la pareja.');
        }
    }

    /**
     * Rechaza campos asignados por el servidor o inmutables en la creación.
     *
     * @param array<string, mixed> $input
     * @return array<string, string>
     */
    private function validateServerFields(array $input, bool $isCreate): array {
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
        }

        return $errors;
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
     * Traduce códigos de error de dominio a respuestas HTTP.
     */
    private function respondDomainError(string $code): void {
        match ($code) {
            'not_found'         => ResponseHelper::notFound('Pareja no encontrada.'),
            'invalid_reference' => ResponseHelper::validationError(['referencia' => 'El ejemplar o la jaula no existen o no pertenecen a tu criadero.'], 'Referencia inválida.'),
            'conflict'          => ResponseHelper::conflict('Conflicto con las reglas de pareja o jaula activa (máximo 6 parejas activas por macho, 1 activa por hembra, 1 activa por jaula, o restricción de estado/cruces).'),
            default             => ResponseHelper::validationError(['datos' => 'Los datos o fechas de la pareja no son válidos.'], 'Error de validación.'),
        };
    }
}

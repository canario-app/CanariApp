<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Helpers\Sanitizer;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Breeder;
use CanariApp\Backend\Models\Mating;
use Throwable;

/**
 * Controlador para el registro y consulta de cruces (/api/v1/cruces).
 */
class MatingController {
    /** Campos asignados por el servidor o inmutables en la BD (SQL-01). */
    private const SERVER_FIELDS = [
        'id_cruce',
        'id_criador',
    ];

    private Mating $matingModel;
    private Breeder $breederModel;

    public function __construct(?Mating $matingModel = null, ?Breeder $breederModel = null) {
        $this->matingModel = $matingModel ?? new Mating();
        $this->breederModel = $breederModel ?? new Breeder();
    }

    /**
     * Lista los cruces del criadero autenticado.
     */
    public function index(): void {
        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $filters = [
                'id_pareja'   => $_GET['id_pareja'] ?? null,
                'fecha_cruce' => $_GET['fecha_cruce'] ?? null,
            ];

            $cruces = $this->matingModel->findAllForBreeder($id_criador, $filters);
            ResponseHelper::success($cruces, 'Listado de cruces obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener los cruces.');
        }
    }

    /**
     * Lista los cruces de una pareja del criadero autenticado.
     */
    public function byPair(string|int $id): void {
        $id_pareja = $this->parsePositiveId($id);
        if ($id_pareja === null) {
            ResponseHelper::badRequest('El ID de la pareja no es válido.');
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $cruces = $this->matingModel->findAllForPair($id_pareja, $id_criador);
            ResponseHelper::success($cruces, 'Cruces de la pareja obtenidos.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener los cruces de la pareja.');
        }
    }

    /**
     * Muestra el detalle de un cruce del criadero autenticado.
     */
    public function show(string|int $id): void {
        $id_cruce = $this->parsePositiveId($id);
        if ($id_cruce === null) {
            ResponseHelper::badRequest('El ID del cruce no es válido.');
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $cruce = $this->matingModel->findDetailed($id_cruce);
            if ($cruce === null) {
                ResponseHelper::notFound('Cruce no encontrado.');
            }

            if ((int) $cruce['id_criador'] !== $id_criador) {
                ResponseHelper::forbidden('No tienes permiso para acceder a este cruce.');
            }

            ResponseHelper::success($cruce, 'Detalle del cruce obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener el cruce.');
        }
    }

    /**
     * Registra un cruce asociado a una pareja activa del criador autenticado.
     */
    public function store(): void {
        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        $input = $this->readJsonBody();

        $errors = [];
        foreach (self::SERVER_FIELDS as $field) {
            if (array_key_exists($field, $input)) {
                $errors[$field] = 'Este campo lo asigna el servidor.';
            }
        }

        $id_pareja = Sanitizer::int($input['id_pareja'] ?? null, 1);
        if ($id_pareja === null) {
            $errors['id_pareja'] = 'Debe indicar una pareja válida.';
        }

        $fecha = Sanitizer::date($input['fecha_cruce'] ?? null);
        if ($fecha === null) {
            $errors['fecha_cruce'] = 'La fecha de cruce es obligatoria y debe tener formato YYYY-MM-DD.';
        } elseif ($fecha > date('Y-m-d')) {
            $errors['fecha_cruce'] = 'La fecha de cruce no puede ser posterior a la fecha actual.';
        }

        if ($errors !== []) {
            ResponseHelper::validationError($errors);
        }

        try {
            $result = $this->matingModel->createForBreeder([
                'id_pareja'   => $id_pareja,
                'fecha_cruce' => $fecha,
            ], $id_criador);

            if (is_string($result)) {
                $this->respondDomainError($result);
            }

            $creado = $this->matingModel->findDetailed((int) $result);
            ResponseHelper::created($creado, 'Cruce registrado exitosamente.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo registrar el cruce.');
        }
    }

    /**
     * Obtiene id_criador del usuario autenticado y responde 403/404 si no aplica.
     */
    private function resolveCurrentBreederId(): ?int {
        $authUser = AuthMiddleware::user();
        $rol = $authUser?->rol ?? null;
        $userId = $authUser?->sub ?? null;

        if ($rol !== 'criador' || $userId === null) {
            ResponseHelper::forbidden('Solo un criador puede gestionar cruces.');
            return null;
        }

        $breeder = $this->breederModel->findByUserId((int) $userId);
        if ($breeder === null) {
            ResponseHelper::notFound('Perfil de criador no encontrado.');
            return null;
        }

        return (int) $breeder['id_criador'];
    }

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
            ResponseHelper::badRequest('El cuerpo de la petición es obligatorio.');
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
            Mating::ERROR_NOT_FOUND => ResponseHelper::notFound('Pareja no encontrada en tu criadero.'),
            Mating::ERROR_CONFLICT => ResponseHelper::conflict(
                'La pareja no está activa o el cruce contradice las reglas de la base de datos.'
            ),
            Mating::ERROR_INVALID_REFERENCE => ResponseHelper::validationError(
                ['id_pareja' => 'La pareja indicada no existe.'],
                'Referencia inválida.'
            ),
            default => ResponseHelper::validationError(
                ['fecha_cruce' => 'La fecha o los datos del cruce no son válidos.'],
                'Error de validación.'
            ),
        };
    }
}

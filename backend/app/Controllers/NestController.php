<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Helpers\Sanitizer;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Breeder;
use CanariApp\Backend\Models\Nest;
use Throwable;

/** Controlador de registro y consulta de nidadas. */
class NestController {
    private const SERVER_FIELDS = ['id_nidada', 'id_criador'];
    private Nest $nestModel;
    private Breeder $breederModel;

    public function __construct(?Nest $nestModel = null, ?Breeder $breederModel = null) {
        $this->nestModel = $nestModel ?? new Nest();
        $this->breederModel = $breederModel ?? new Breeder();
    }

    public function index(): void {
        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) return;
        try {
            $nidadas = $this->nestModel->findAllForBreeder($id_criador, [
                'id_cruce' => $_GET['id_cruce'] ?? null,
                'fecha_nacimiento' => $_GET['fecha_nacimiento'] ?? null,
            ]);
            ResponseHelper::success($nidadas, 'Listado de nidadas obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener las nidadas.');
        }
    }

    public function byMating(string|int $id): void {
        $id_cruce = Sanitizer::int($id, 1);
        if ($id_cruce === null) ResponseHelper::badRequest('El ID del cruce no es válido.');
        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) return;
        try {
            $nidadas = $this->nestModel->findAllForMating($id_cruce, $id_criador);
            ResponseHelper::success($nidadas, 'Nidadas del cruce obtenidas.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener las nidadas del cruce.');
        }
    }

    public function show(string|int $id): void {
        $id_nidada = Sanitizer::int($id, 1);
        if ($id_nidada === null) ResponseHelper::badRequest('El ID de la nidada no es válido.');
        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) return;
        try {
            $nidada = $this->nestModel->findDetailed($id_nidada);
            if ($nidada === null || (int) $nidada['id_criador'] !== $id_criador) {
                ResponseHelper::notFound('Nidada no encontrada en tu criadero.');
            }
            ResponseHelper::success($nidada, 'Detalle de la nidada obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener la nidada.');
        }
    }

    public function store(): void {
        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) return;
        $input = $this->readJsonBody();
        $errors = [];
        foreach (self::SERVER_FIELDS as $field) {
            if (array_key_exists($field, $input)) $errors[$field] = 'Este campo lo asigna el servidor.';
        }
        $id_cruce = Sanitizer::int($input['id_cruce'] ?? null, 1);
        if ($id_cruce === null) $errors['id_cruce'] = 'Debe indicar un cruce válido.';
        $fecha = Sanitizer::date($input['fecha_nacimiento'] ?? null);
        if ($fecha === null) {
            $errors['fecha_nacimiento'] = 'La fecha de nacimiento es obligatoria y debe tener formato YYYY-MM-DD.';
        } elseif ($fecha > date('Y-m-d')) {
            $errors['fecha_nacimiento'] = 'La fecha de nacimiento no puede ser posterior a la fecha actual.';
        }
        if ($errors !== []) ResponseHelper::validationError($errors);

        try {
            $result = $this->nestModel->createForBreeder([
                'id_cruce' => $id_cruce,
                'fecha_nacimiento' => $fecha,
            ], $id_criador);
            if (is_string($result)) $this->respondDomainError($result);
            ResponseHelper::created(
                $this->nestModel->findDetailed((int) $result),
                'Nidada registrada exitosamente.'
            );
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo registrar la nidada.');
        }
    }

    private function resolveCurrentBreederId(): ?int {
        $authUser = AuthMiddleware::user();
        $rol = $authUser?->rol ?? null;
        $userId = $authUser?->sub ?? null;
        if ($rol !== 'criador' || $userId === null) {
            ResponseHelper::forbidden('Solo un criador puede gestionar nidadas.');
            return null;
        }
        $breeder = $this->breederModel->findByUserId((int) $userId);
        if ($breeder === null) {
            ResponseHelper::notFound('Perfil de criador no encontrado.');
            return null;
        }
        return (int) $breeder['id_criador'];
    }

    /** @return array<string,mixed> */
    private function readJsonBody(): array {
        $raw = file_get_contents('php://input');
        if ($raw === false || trim($raw) === '') ResponseHelper::badRequest('El cuerpo de la petición es obligatorio.');
        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) ResponseHelper::badRequest('El cuerpo de la petición debe ser un JSON válido.');
        return $decoded;
    }

    private function respondDomainError(string $code): void {
        match ($code) {
            Nest::ERROR_NOT_FOUND => ResponseHelper::notFound('El cruce indicado no existe en tu criadero.'),
            Nest::ERROR_INVALID_REFERENCE => ResponseHelper::validationError(
                ['id_cruce' => 'El cruce indicado no existe.'], 'Referencia inválida.'
            ),
            default => ResponseHelper::validationError(
                ['fecha_nacimiento' => 'La fecha debe ser igual o posterior a la fecha del cruce y no puede ser futura.'],
                'Error de validación.'
            ),
        };
    }
}

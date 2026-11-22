<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Breeder;
use CanariApp\Backend\Models\Cage;

class CageController {
    /**
     * Lista las jaulas del criador autenticado y su disponibilidad.
     */
    public function index(): void {
        $idCriador = $this->currentBreederId();
        $jaulas = (new Cage())->findAllDetailed($idCriador);

        ResponseHelper::success($jaulas, 'Listado de jaulas obtenido.');
    }

    /**
     * Devuelve el detalle de una jaula del criador autenticado.
     */
    public function show(int|string $id): void {
        $idJaula = $this->parseId($id);
        $jaula = (new Cage())->findDetailed($idJaula, $this->currentBreederId());

        if ($jaula === null) {
            ResponseHelper::notFound('Jaula no encontrada en tu criadero.');
        }

        ResponseHelper::success($jaula, 'Detalle de la jaula obtenido.');
    }

    /**
     * Registra una jaula en el criadero del usuario autenticado.
     * El cliente no puede indicar id_jaula ni id_criador.
     */
    public function store(): void {
        $input = $this->getJsonInput();
        $errors = [];

        foreach (['id_jaula', 'id_criador'] as $serverField) {
            if (array_key_exists($serverField, $input)) {
                $errors[$serverField] = 'Este campo lo asigna el servidor.';
            }
        }

        $numero = $this->positiveInt($input['numero_jaula'] ?? null);
        if ($numero === null || $numero > 2147483647) {
            $errors['numero_jaula'] = 'El número de jaula debe ser un entero entre 1 y 2.147.483.647.';
        }

        if ($errors !== []) {
            ResponseHelper::validationError($errors);
        }

        $idCriador = $this->currentBreederId();
        $model = new Cage();
        $result = $model->createForBreeder($numero, $idCriador);

        if (is_string($result)) {
            $this->handleModelError($result);
            return;
        }

        $creada = $model->findDetailed((int) $result, $idCriador)
            ?? ['id_jaula' => $result, 'numero_jaula' => $numero, 'id_criador' => $idCriador, 'ocupada' => false];

        ResponseHelper::created($creada, 'Jaula registrada exitosamente.');
    }

    /**
     * El módulo de jaulas solo está disponible para el perfil criador.
     * El SRS de esta versión excluye la edición y eliminación de registros.
     */
    private function currentBreederId(): int {
        if (AuthMiddleware::userRole() !== 'criador') {
            ResponseHelper::forbidden('La gestión de jaulas está disponible para criadores.');
        }

        $userId = AuthMiddleware::userId();
        if ($userId === null) {
            ResponseHelper::unauthorized('No hay un usuario autenticado.');
        }

        $perfil = (new Breeder())->findByUserId($userId);
        if ($perfil === null) {
            ResponseHelper::forbidden('El usuario actual no tiene un criadero asociado.');
        }

        return (int) $perfil['id_criador'];
    }

    private function handleModelError(string $code): void {
        match ($code) {
            Cage::ERROR_CONFLICT => ResponseHelper::conflict(
                'Ya existe una jaula con ese número en tu criadero.'
            ),
            Cage::ERROR_INVALID_REFERENCE => ResponseHelper::validationError([
                'id_criador' => 'El criadero indicado no existe.',
            ]),
            Cage::ERROR_INVALID_DATA => ResponseHelper::validationError([
                'numero_jaula' => 'El número de jaula no cumple las restricciones de la base de datos.',
            ]),
            default => ResponseHelper::internalError(),
        };
    }

    private function parseId(int|string $id): int {
        $value = is_int($id) ? $id : filter_var(trim($id), FILTER_VALIDATE_INT);
        if ($value === false || $value <= 0) {
            ResponseHelper::badRequest('El ID de la jaula no es válido.');
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

    /**
     * Lee el cuerpo JSON de la petición.
     *
     * @return array<string, mixed>
     */
    private function getJsonInput(): array {
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
}

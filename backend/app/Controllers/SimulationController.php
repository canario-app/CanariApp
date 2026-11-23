<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Helpers\Sanitizer;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Breeder;
use CanariApp\Backend\Models\Simulation;
use Throwable;

/**
 * Controlador para los endpoints de simulación genética (/api/v1/simulaciones).
 */
class SimulationController {
    private const SERVER_FIELDS = [
        'id_simulacion',
        'id_criador',
        'fecha',
        'resultados',
    ];

    private Simulation $simulationModel;
    private Breeder $breederModel;

    public function __construct(?Simulation $simulationModel = null, ?Breeder $breederModel = null) {
        $this->simulationModel = $simulationModel ?? new Simulation();
        $this->breederModel = $breederModel ?? new Breeder();
    }

    /**
     * Lista el historial de simulaciones del criador autenticado.
     */
    public function index(): void {
        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $simulations = $this->simulationModel->findAllForBreeder($id_criador, [
                'id_mutacion' => $_GET['id_mutacion'] ?? null,
                'id_macho'    => $_GET['id_macho'] ?? null,
                'id_hembra'   => $_GET['id_hembra'] ?? null,
            ]);
            ResponseHelper::success($simulations, 'Listado de simulaciones obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener las simulaciones.');
        }
    }

    /**
     * Muestra el detalle de una simulación perteneciente al criador autenticado.
     */
    public function show(string|int $id): void {
        $id_simulacion = Sanitizer::int($id, 1);
        if ($id_simulacion === null) {
            ResponseHelper::badRequest('El ID de la simulación no es válido.');
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $simulation = $this->simulationModel->findDetailed($id_simulacion);
            if ($simulation === null || (int) $simulation['id_criador'] !== $id_criador) {
                ResponseHelper::notFound('Simulación no encontrada en tu criadero.');
            }

            ResponseHelper::success($simulation, 'Detalle de la simulación obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener la simulación.');
        }
    }

    /**
     * Ejecuta y registra una nueva simulación genética para el criador autenticado.
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
                $errors[$field] = 'Este campo lo asigna o calcula el servidor o la base de datos.';
            }
        }

        $id_macho = Sanitizer::int($input['id_macho'] ?? null, 1);
        if ($id_macho === null) {
            $errors['id_macho'] = 'Debe indicar un ejemplar macho válido.';
        }

        $id_hembra = Sanitizer::int($input['id_hembra'] ?? null, 1);
        if ($id_hembra === null) {
            $errors['id_hembra'] = 'Debe indicar un ejemplar hembra válido.';
        }

        $id_mutacion = Sanitizer::int($input['id_mutacion'] ?? null, 1);
        if ($id_mutacion === null) {
            $errors['id_mutacion'] = 'Debe indicar una mutación válida del catálogo.';
        }

        if (!isset($input['genotipo_macho']) || !is_string($input['genotipo_macho'])) {
            $errors['genotipo_macho'] = 'Debe indicar genotipo_macho (visual, portador o sin factor).';
        }

        if (!isset($input['genotipo_hembra']) || !is_string($input['genotipo_hembra'])) {
            $errors['genotipo_hembra'] = 'Debe indicar genotipo_hembra (visual, portador o sin factor).';
        }

        if ($errors !== []) {
            ResponseHelper::validationError($errors);
        }

        try {
            $result = $this->simulationModel->simulateAndCreate([
                'id_macho'        => $id_macho,
                'id_hembra'       => $id_hembra,
                'id_mutacion'     => $id_mutacion,
                'genotipo_macho'  => $input['genotipo_macho'],
                'genotipo_hembra' => $input['genotipo_hembra'],
            ], $id_criador);

            if (is_string($result)) {
                $this->respondDomainError($result);
            }

            ResponseHelper::created(
                $this->simulationModel->findDetailed((int) $result),
                'Simulación genética registrada exitosamente.'
            );
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo ejecutar la simulación genética.');
        }
    }

    private function resolveCurrentBreederId(): ?int {
        $authUser = AuthMiddleware::user();
        $rol = $authUser?->rol ?? null;
        $userId = $authUser?->sub ?? null;

        if ($rol !== 'criador' || $userId === null) {
            ResponseHelper::forbidden('Solo un criador puede ejecutar o consultar simulaciones.');
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

    private function respondDomainError(string $code): void {
        match ($code) {
            Simulation::ERROR_NOT_FOUND => ResponseHelper::notFound('La simulación indicada no existe en tu criadero.'),
            Simulation::ERROR_INVALID_REFERENCE => ResponseHelper::validationError(
                ['referencia' => 'La mutación o alguno de los ejemplares indicados no existe o pertenece a otro criadero.'],
                'Referencia inválida.'
            ),
            Simulation::ERROR_CONFLICT => ResponseHelper::conflict(
                'La simulación contradice las reglas de integridad de la base de datos.'
            ),
            default => ResponseHelper::validationError(
                ['simulacion' => 'Los parámetros de la simulación genética no son válidos.'],
                'Error de validación.'
            ),
        };
    }
}

<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Helpers\Sanitizer;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Breeder;
use CanariApp\Backend\Models\Canary;
use CanariApp\Backend\Models\Chick;
use Throwable;

/**
 * Controlador para los endpoints de crías (/api/v1/crias).
 */
class ChickController {
    private const SERVER_FIELDS = [
        'id_cria',
        'id_criador',
        'es_portadora',
        'fecha_registro',
        'requiere_revision',
    ];

    private const CANARY_RING_FIELDS = [
        'anillo',
        'id_club',
        'numero_socio',
        'temporada',
        'sexo',
        'id_variedad',
    ];

    private Chick $chickModel;
    private Breeder $breederModel;

    public function __construct(?Chick $chickModel = null, ?Breeder $breederModel = null) {
        $this->chickModel = $chickModel ?? new Chick();
        $this->breederModel = $breederModel ?? new Breeder();
    }

    /**
     * Lista las crías pertenecientes al criador autenticado.
     */
    public function index(): void {
        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $chicks = $this->chickModel->findAllForBreeder($id_criador, [
                'id_nidada'       => $_GET['id_nidada'] ?? null,
                'id_canario'      => $_GET['id_canario'] ?? null,
                'factor_genetico' => $_GET['factor_genetico'] ?? null,
                'reservada'       => $_GET['reservada'] ?? null,
            ]);
            ResponseHelper::success($chicks, 'Listado de crías obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener las crías.');
        }
    }

    /**
     * Lista las crías de una nidada del criadero autenticado.
     */
    public function byNest(string|int $id): void {
        $id_nidada = Sanitizer::int($id, 1);
        if ($id_nidada === null) {
            ResponseHelper::badRequest('El ID de la nidada no es válido.');
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $chicks = $this->chickModel->findAllForNest($id_nidada, $id_criador);
            ResponseHelper::success($chicks, 'Crías de la nidada obtenidas.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener las crías de la nidada.');
        }
    }

    /**
     * Muestra el detalle de una cría si pertenece al criador autenticado.
     */
    public function show(string|int $id): void {
        $id_cria = Sanitizer::int($id, 1);
        if ($id_cria === null) {
            ResponseHelper::badRequest('El ID de la cría no es válido.');
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $chick = $this->chickModel->findDetailed($id_cria);
            if ($chick === null || (int) $chick['id_criador'] !== $id_criador) {
                ResponseHelper::notFound('Cría no encontrada en tu criadero.');
            }

            ResponseHelper::success($chick, 'Detalle de la cría obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener la cría.');
        }
    }

    /**
     * Registra una nueva cría asociada a una nidada.
     *
     * Admite dos modalidades (RF019, RF020):
     *  1. Alta conjunta transaccional (recomendada para crías sin sexo o variedad):
     *     envía los datos de anillo (`anillo`, `id_club`, `numero_socio`, `temporada`,
     *     y opcionalmente `sexo` e `id_variedad` en null) junto con `id_nidada`.
     *  2. Vinculación de un ejemplar ya registrado mediante `id_canario`.
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

        $id_nidada = Sanitizer::int($input['id_nidada'] ?? null, 1);
        if ($id_nidada === null) {
            $errors['id_nidada'] = 'Debe indicar una nidada válida.';
        }

        $hasCanaryId = array_key_exists('id_canario', $input) && $input['id_canario'] !== null && $input['id_canario'] !== '';
        $nestedCanary = is_array($input['canario'] ?? null) ? $input['canario'] : null;
        $hasFlatCanaryData = false;

        foreach (self::CANARY_RING_FIELDS as $ringField) {
            if (array_key_exists($ringField, $input)) {
                $hasFlatCanaryData = true;
                break;
            }
        }

        $isCombinedCreate = $nestedCanary !== null || $hasFlatCanaryData;

        if ($hasCanaryId && $isCombinedCreate) {
            $errors['id_canario'] = 'Indique id_canario de un ejemplar existente o los datos del nuevo anillo, pero no ambos.';
        } elseif (!$hasCanaryId && !$isCombinedCreate) {
            $errors['canario'] = 'Debe indicar los datos del anillo de la cría (anillo, id_club, numero_socio, temporada) o un id_canario existente.';
        }

        if ($isCombinedCreate) {
            $canarySource = $nestedCanary ?? $input;
            $errors = array_merge($errors, $this->validateNewChickCanary($canarySource));
        } elseif ($hasCanaryId && Sanitizer::int($input['id_canario'], 1) === null) {
            $errors['id_canario'] = 'Debe indicar un ejemplar de canario válido.';
        }

        if ($errors !== []) {
            ResponseHelper::validationError($errors);
        }

        try {
            if ($isCombinedCreate) {
                $canarySource = $nestedCanary ?? $input;
                $userId = (int) (AuthMiddleware::userId() ?? 0);

                $result = $this->chickModel->createWithCanaryForBreeder(
                    [
                        'anillo'       => $canarySource['anillo'] ?? null,
                        'id_club'      => $canarySource['id_club'] ?? null,
                        'numero_socio' => $canarySource['numero_socio'] ?? null,
                        'temporada'    => $canarySource['temporada'] ?? null,
                        'sexo'         => $canarySource['sexo'] ?? null,
                        'id_variedad'  => $canarySource['id_variedad'] ?? null,
                    ],
                    [
                        'id_nidada'       => $id_nidada,
                        'factor_genetico' => $input['factor_genetico'] ?? null,
                        'reservada'       => $input['reservada'] ?? false,
                    ],
                    $id_criador,
                    $userId
                );
            } else {
                $result = $this->chickModel->createForBreeder([
                    'id_nidada'       => $id_nidada,
                    'id_canario'      => Sanitizer::int($input['id_canario'], 1),
                    'factor_genetico' => $input['factor_genetico'] ?? null,
                    'reservada'       => $input['reservada'] ?? false,
                ], $id_criador);
            }

            if (is_string($result)) {
                $this->respondDomainError($result);
            }

            ResponseHelper::created(
                $this->chickModel->findDetailed((int) $result),
                'Cría registrada exitosamente.'
            );
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo registrar la cría.');
        }
    }

    /**
     * Actualiza marcas de portadora (factor_genetico) o reserva de una cría.
     */
    public function update(string|int $id): void {
        $id_cria = Sanitizer::int($id, 1);
        if ($id_cria === null) {
            ResponseHelper::badRequest('El ID de la cría no es válido.');
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        $input = $this->readJsonBody();
        $errors = [];

        foreach (array_merge(self::SERVER_FIELDS, ['id_nidada', 'id_canario']) as $field) {
            if (array_key_exists($field, $input)) {
                $errors[$field] = 'Este campo no se puede modificar.';
            }
        }

        if ($errors !== []) {
            ResponseHelper::validationError($errors);
        }

        try {
            $result = $this->chickModel->updateForBreeder($id_cria, $input, $id_criador);
            if (is_string($result)) {
                $this->respondDomainError($result);
            }

            ResponseHelper::success(
                $this->chickModel->findDetailed($id_cria),
                'Cría actualizada exitosamente.'
            );
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo actualizar la cría.');
        }
    }

    /**
     * Valida los campos del ejemplar a crear junto con la cría (sexo e id_variedad son opcionales/null).
     *
     * @param array<string, mixed> $canaryData
     * @return array<string, string>
     */
    private function validateNewChickCanary(array $canaryData): array {
        $errors = [];
        $maxSeason = (int) date('Y');

        foreach (self::SERVER_FIELDS as $serverField) {
            if (array_key_exists($serverField, $canaryData)) {
                $errors[$serverField] = 'Este campo lo asigna el servidor.';
            }
        }

        if (array_key_exists('id_criador', $canaryData)) {
            $errors['id_criador'] = 'El criador se toma del usuario autenticado.';
        }

        $anillo = $canaryData['anillo'] ?? null;
        if (!is_scalar($anillo) || preg_match('/^[0-9]{1,6}$/', trim((string) $anillo)) !== 1) {
            $errors['anillo'] = 'El número de anillo es obligatorio y debe tener entre 1 y 6 dígitos.';
        }

        $numeroSocio = $canaryData['numero_socio'] ?? null;
        if (!is_scalar($numeroSocio) || preg_match('/^[0-9]{1,5}$/', trim((string) $numeroSocio)) !== 1) {
            $errors['numero_socio'] = 'El número de socio es obligatorio y debe tener entre 1 y 5 dígitos.';
        }

        if (Sanitizer::int($canaryData['id_club'] ?? null, 1) === null) {
            $errors['id_club'] = 'Debe indicar un club válido.';
        }

        $temporada = Sanitizer::int($canaryData['temporada'] ?? null, 1);
        if ($temporada === null || $temporada < 1000 || $temporada > $maxSeason) {
            $errors['temporada'] = 'La temporada debe ser un año de 4 dígitos y no puede ser mayor al año actual (' . date('Y') . ').';
        }

        if (array_key_exists('sexo', $canaryData) && $canaryData['sexo'] !== null && $canaryData['sexo'] !== '') {
            if (!is_string($canaryData['sexo']) || !in_array($canaryData['sexo'], ['M', 'H'], true)) {
                $errors['sexo'] = 'El sexo debe ser "M", "H" o null si aún está pendiente.';
            }
        }

        if (
            array_key_exists('id_variedad', $canaryData)
            && $canaryData['id_variedad'] !== null
            && $canaryData['id_variedad'] !== ''
            && Sanitizer::int($canaryData['id_variedad'], 1) === null
        ) {
            $errors['id_variedad'] = 'La variedad debe ser un identificador válido o null si aún está pendiente.';
        }

        return $errors;
    }

    private function resolveCurrentBreederId(): ?int {
        $authUser = AuthMiddleware::user();
        $rol = $authUser?->rol ?? null;
        $userId = $authUser?->sub ?? null;

        if ($rol !== 'criador' || $userId === null) {
            ResponseHelper::forbidden('Solo un criador puede gestionar crías.');
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
            Chick::ERROR_NOT_FOUND => ResponseHelper::notFound('La nidada o la cría indicada no existe en tu criadero.'),
            Chick::ERROR_CONFLICT_ANILLO => ResponseHelper::conflict('El anillo no está disponible.'),
            Chick::ERROR_INVALID_REFERENCE => ResponseHelper::validationError(
                ['referencia' => 'El club, la variedad, el canario o la mutación indicada no existe o pertenece a otro criadero.'],
                'Referencia inválida.'
            ),
            Chick::ERROR_CONFLICT => ResponseHelper::conflict(
                'El canario ya está registrado como cría o contradice las reglas de la base de datos.'
            ),
            default => ResponseHelper::validationError(
                ['cria' => 'Los datos de la cría o del ejemplar no son válidos (verifique coherencia entre sexo y variedad).'],
                'Error de validación.'
            ),
        };
    }

    /**
     * Devuelve el árbol de ascendencia de una cría perteneciente al criadero autenticado.
     * Admite ?generaciones=1..6 (por defecto 4).
     */
    public function ancestry(string|int $id): void {
        $id_cria = Sanitizer::int($id, 1);
        if ($id_cria === null) {
            ResponseHelper::badRequest('El ID de la cría no es válido.');
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        $rawGen = $_GET['generaciones'] ?? null;
        $generaciones = Canary::DEFAULT_PEDIGREE_GENERATIONS;
        if ($rawGen !== null && !(is_string($rawGen) && trim($rawGen) === '')) {
            $parsedGen = Sanitizer::int($rawGen, 1, Canary::MAX_PEDIGREE_GENERATIONS);
            if ($parsedGen === null) {
                ResponseHelper::badRequest(
                    'El parámetro generaciones debe ser un entero entre 1 y ' . Canary::MAX_PEDIGREE_GENERATIONS . '.'
                );
            }
            $generaciones = $parsedGen;
        }

        try {
            $chick = $this->chickModel->findDetailed($id_cria);
            if ($chick === null || (int) $chick['id_criador'] !== $id_criador) {
                ResponseHelper::notFound('Cría no encontrada en tu criadero.');
            }

            $pedigree = (new Canary())->findAncestry((int) $chick['id_canario'], $generaciones);

            ResponseHelper::success([
                'cria'        => $chick,
                'ascendencia' => $pedigree,
            ], 'Ascendencia de la cría obtenida.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener la ascendencia de la cría.');
        }
    }
}
<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Helpers\Sanitizer;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Breeder;
use CanariApp\Backend\Models\Canary;
use CanariApp\Backend\Models\Title;
use Throwable;

/**
 * Controlador para los endpoints de títulos de competencia (/api/v1/titulos).
 *
 * Solo un criador puede gestionar títulos, siempre sobre ejemplares de su
 * propio criadero (SRS-RF023, SEG-001, tabla de permisos de la BD v7.1).
 */
class TitleController {
    private const SERVER_FIELDS = ['id_titulo', 'id_criador'];
    private const IMMUTABLE_FIELDS = ['id_canario'];
    private const RING_FIELDS = ['anillo', 'id_club', 'numero_socio', 'temporada'];

    private Title $titleModel;
    private Breeder $breederModel;
    private Canary $canaryModel;

    public function __construct(
        ?Title $titleModel = null,
        ?Breeder $breederModel = null,
        ?Canary $canaryModel = null
    ) {
        $this->titleModel = $titleModel ?? new Title();
        $this->breederModel = $breederModel ?? new Breeder();
        $this->canaryModel = $canaryModel ?? new Canary();
    }

    /**
     * Lista los títulos del criadero autenticado.
     */
    public function index(): void {
        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $titles = $this->titleModel->findAllForBreeder($id_criador, [
                'id_canario' => $_GET['id_canario'] ?? null,
                'nombre'     => $_GET['nombre'] ?? null,
                'fecha'      => $_GET['fecha'] ?? null,
            ]);
            ResponseHelper::success($titles, 'Listado de títulos obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener los títulos.');
        }
    }

    /**
     * Lista los títulos de un ejemplar del criadero autenticado.
     */
    public function byCanary(string|int $id): void {
        $id_canario = Sanitizer::int($id, 1);
        if ($id_canario === null) {
            ResponseHelper::badRequest('El ID del ejemplar no es válido.');
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $titles = $this->titleModel->findAllForCanary($id_canario, $id_criador);
            ResponseHelper::success($titles, 'Títulos del ejemplar obtenidos.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener los títulos del ejemplar.');
        }
    }

    /**
     * Muestra el detalle de un título si pertenece al criadero autenticado.
     */
    public function show(string|int $id): void {
        $id_titulo = Sanitizer::int($id, 1);
        if ($id_titulo === null) {
            ResponseHelper::badRequest('El ID del título no es válido.');
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $title = $this->titleModel->findDetailed($id_titulo);
            if ($title === null || (int) $title['id_criador'] !== $id_criador) {
                ResponseHelper::notFound('Título no encontrado en tu criadero.');
            }

            ResponseHelper::success($title, 'Detalle del título obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener el título.');
        }
    }

    /**
     * Registra un título asociado a un ejemplar del criadero autenticado.
     *
     * El ejemplar se puede indicar con `id_canario` o con el anillo completo
     * (`anillo`, `id_club`, `numero_socio` y `temporada`), según SRS-RF023.
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
                $errors[$field] = 'Este campo lo asigna el servidor o la base de datos.';
            }
        }

        $id_canario = $this->resolveCanaryId($input, $id_criador, $errors);

        $nombre = Sanitizer::string($input['nombre'] ?? null, 100);
        if ($nombre === null || $nombre === '') {
            $errors['nombre'] = 'El nombre del título es obligatorio y no puede superar 100 caracteres.';
        }

        $fecha = Sanitizer::date($input['fecha'] ?? null);
        if ($fecha === null) {
            $errors['fecha'] = 'La fecha es obligatoria y debe tener formato YYYY-MM-DD.';
        } elseif ($fecha > date('Y-m-d')) {
            $errors['fecha'] = 'La fecha del título no puede ser posterior a la fecha actual.';
        }

        if ($errors !== []) {
            ResponseHelper::validationError($errors);
        }

        try {
            $result = $this->titleModel->createForBreeder([
                'id_canario' => $id_canario,
                'nombre'     => $nombre,
                'fecha'      => $fecha,
            ], $id_criador);

            if (is_string($result)) {
                $this->respondDomainError($result);
            }

            ResponseHelper::created(
                $this->titleModel->findDetailed((int) $result),
                'Título registrado exitosamente.'
            );
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo registrar el título.');
        }
    }

    /**
     * Actualiza el nombre o la fecha de un título del criadero autenticado.
     * El ejemplar asociado no se puede cambiar (trg_titulo_canario_inmutable).
     */
    public function update(string|int $id): void {
        $id_titulo = Sanitizer::int($id, 1);
        if ($id_titulo === null) {
            ResponseHelper::badRequest('El ID del título no es válido.');
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        $input = $this->readJsonBody();
        $errors = [];

        foreach (array_merge(self::SERVER_FIELDS, self::IMMUTABLE_FIELDS) as $field) {
            if (array_key_exists($field, $input)) {
                $errors[$field] = 'Este campo no se puede modificar.';
            }
        }
        foreach (self::RING_FIELDS as $field) {
            if (array_key_exists($field, $input)) {
                $errors[$field] = 'El ejemplar de un título no se puede cambiar.';
            }
        }

        $updates = [];
        if (array_key_exists('nombre', $input)) {
            $nombre = Sanitizer::string($input['nombre'], 100);
            if ($nombre === null || $nombre === '') {
                $errors['nombre'] = 'El nombre del título no puede estar vacío ni superar 100 caracteres.';
            } else {
                $updates['nombre'] = $nombre;
            }
        }

        if (array_key_exists('fecha', $input)) {
            $fecha = Sanitizer::date($input['fecha']);
            if ($fecha === null) {
                $errors['fecha'] = 'La fecha debe tener formato YYYY-MM-DD.';
            } elseif ($fecha > date('Y-m-d')) {
                $errors['fecha'] = 'La fecha del título no puede ser posterior a la fecha actual.';
            } else {
                $updates['fecha'] = $fecha;
            }
        }

        if ($errors !== []) {
            ResponseHelper::validationError($errors);
        }
        if ($updates === []) {
            ResponseHelper::badRequest('Debe indicar al menos un campo editable (nombre o fecha).');
        }

        try {
            $result = $this->titleModel->updateForBreeder($id_titulo, $updates, $id_criador);
            if (is_string($result)) {
                $this->respondDomainError($result);
            }

            ResponseHelper::success(
                $this->titleModel->findDetailed($id_titulo),
                'Título actualizado exitosamente.'
            );
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo actualizar el título.');
        }
    }

    /**
     * Crías de un ejemplar ganador, agrupadas por el ejemplar con que se cruzó
     * (SRS-RF024). Si el ejemplar no tiene títulos o no tiene crías, se devuelve
     * un mensaje explícito en lugar de un error.
     */
    public function offspring(string|int $id): void {
        $id_canario = Sanitizer::int($id, 1);
        if ($id_canario === null) {
            ResponseHelper::badRequest('El ID del ejemplar no es válido.');
        }

        $id_criador = $this->resolveCurrentBreederId();
        if ($id_criador === null) {
            return;
        }

        try {
            $result = $this->titleModel->offspringForWinner($id_canario, $id_criador);

            if (!is_array($result)) {
                $this->respondOffspringResult($result, $id_canario);
            }

            ResponseHelper::success([
                'id_canario'    => $id_canario,
                'tiene_titulos' => true,
                'grupos'        => $result,
            ], 'Descendencia del ejemplar ganador obtenida.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener la descendencia del ejemplar.');
        }
    }

    private function resolveCurrentBreederId(): ?int {
        $authUser = AuthMiddleware::user();
        $rol = $authUser?->rol ?? null;
        $userId = $authUser?->sub ?? null;

        if ($rol !== 'criador' || $userId === null) {
            ResponseHelper::forbidden('Solo un criador puede gestionar títulos.');
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
     * Resuelve el ejemplar a partir de `id_canario` o del anillo completo.
     * El anillo debe existir en el criadero autenticado (SRS-RF023).
     *
     * @param array<string, mixed> $input
     * @param array<string, string> $errors
     */
    private function resolveCanaryId(array $input, int $id_criador, array &$errors): ?int {
        $id_canario = Sanitizer::int($input['id_canario'] ?? null, 1);
        if ($id_canario !== null) {
            return $id_canario;
        }
        if (array_key_exists('id_canario', $input)) {
            $errors['id_canario'] = 'Debe indicar un ejemplar válido.';
            return null;
        }

        $hasRing = false;
        foreach (self::RING_FIELDS as $field) {
            if (array_key_exists($field, $input) && $input[$field] !== null && $input[$field] !== '') {
                $hasRing = true;
                break;
            }
        }
        if (!$hasRing) {
            $errors['id_canario'] = 'Debe indicar un ejemplar con `id_canario` o con su anillo completo.';
            return null;
        }

        $anillo = Sanitizer::string($input['anillo'] ?? null, 6);
        $id_club = Sanitizer::int($input['id_club'] ?? null, 1);
        $numero_socio = Sanitizer::string($input['numero_socio'] ?? null, 5);
        $temporada = Sanitizer::int($input['temporada'] ?? null, 1000, 9999);

        if ($anillo === null || preg_match('/^[0-9]{1,6}$/', $anillo) !== 1
            || $id_club === null
            || $numero_socio === null || preg_match('/^[0-9]{1,5}$/', $numero_socio) !== 1
            || $temporada === null
        ) {
            $errors['anillo'] = 'El anillo completo debe incluir anillo, club, número de socio y temporada válidos.';
            return null;
        }

        try {
            $canary = $this->canaryModel->findByAnillo($anillo, $id_club, $numero_socio, $temporada);
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo verificar el anillo del ejemplar.');
        }

        if ($canary === null || (int) $canary['id_criador'] !== $id_criador) {
            $errors['anillo'] = 'El anillo indicado no corresponde a un ejemplar registrado en tu criadero.';
            return null;
        }

        return (int) $canary['id_canario'];
    }

    /** @return array<string, mixed> */
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
            Title::ERROR_NOT_FOUND => ResponseHelper::notFound('El título indicado no existe en tu criadero.'),
            Title::ERROR_INVALID_REFERENCE => ResponseHelper::validationError(
                ['id_canario' => 'El ejemplar indicado no existe en tu criadero.'],
                'Referencia inválida.'
            ),
            Title::ERROR_CONFLICT => ResponseHelper::conflict(
                'Ya existe un título con ese nombre y fecha para el ejemplar.'
            ),
            default => ResponseHelper::validationError(
                ['titulo' => 'Los datos del título no son válidos.'],
                'Error de validación.'
            ),
        };
    }

    private function respondOffspringResult(string $code, int $id_canario): void {
        match ($code) {
            Title::ERROR_NOT_FOUND => ResponseHelper::notFound('Ejemplar no encontrado en tu criadero.'),
            Title::ERROR_INVALID_DATA => ResponseHelper::validationError(
                ['id_canario' => 'El ejemplar no tiene sexo registrado; no se puede agrupar su descendencia.'],
                'Error de validación.'
            ),
            Title::ERROR_NO_TITLES => ResponseHelper::success([
                'id_canario'    => $id_canario,
                'tiene_titulos' => false,
                'grupos'        => [],
            ], 'El ejemplar no tiene títulos registrados.'),
            Title::ERROR_NO_OFFSPRING => ResponseHelper::success([
                'id_canario'    => $id_canario,
                'tiene_titulos' => true,
                'grupos'        => [],
            ], 'El ejemplar ganador no tiene crías registradas.'),
            default => ResponseHelper::internalError('No se pudo obtener la descendencia del ejemplar.'),
        };
    }
}

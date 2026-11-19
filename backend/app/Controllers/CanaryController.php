<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

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

    /**
     * [Criador] Lista sus canarios. [Admin] Lista todos.
     */
    public function index(): void {
        $model = new Canary();
        $idCriador = $this->isAdmin() ? null : $this->currentBreederId();

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
     * Muestra un canario. Un criador no puede ver los de otro criadero.
     */
    public function show(int|string $id): void {
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
     * Crea un canario. El criador se toma del token; el administrador debe
     * indicar `id_criador` en el cuerpo.
     */
    public function store(): void {
        $input = $this->getJsonInput();
        $errors = $this->validate($input, true);
        if ($errors !== []) {
            ResponseHelper::validationError($errors);
        }

        $idCriador = $this->isAdmin()
            ? $this->positiveInt($input['id_criador']) ?? 0
            : $this->currentBreederId();

        $model = new Canary();
        $result = $model->createForBreeder($this->filterFields($input), $idCriador);

        if (is_string($result)) {
            $this->handleError($result);
            return;
        }

        $creado = $model->findDetailed($result) ?? ['id_canario' => $result];
        ResponseHelper::created($creado, 'Canario creado exitosamente.');
    }

    /**
     * Actualiza un canario propio (criador) o cualquiera (administrador).
     * Los campos omitidos conservan su valor.
     */
    public function update(int|string $id): void {
        $idCanario = $this->parseId($id);
        $input = $this->getJsonInput();
        $errors = $this->validate($input, false);
        if ($errors !== []) {
            ResponseHelper::validationError($errors);
        }

        $model = new Canary();
        $actual = $model->findDetailed($idCanario);
        if ($actual === null) {
            ResponseHelper::notFound('Canario no encontrado.');
        }

        $this->assertVisible($actual);

        $result = $this->isAdmin()
            ? $model->updateForAdmin($idCanario, $this->filterFields($input, true))
            : $model->updateForBreeder(
                $idCanario,
                $this->filterFields($input),
                (int) $actual['id_criador']
            );

        if (is_string($result)) {
            $this->handleError($result);
            return;
        }

        $actualizado = $model->findDetailed($idCanario);
        ResponseHelper::success($actualizado, 'Canario actualizado exitosamente.');
    }

    /**
     * Un criador solo puede acceder a los ejemplares de su criadero.
     *
     * @param array<string, mixed> $canario
     */
    private function assertVisible(array $canario): void {
        if ($this->isAdmin()) {
            return;
        }

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
    private function validate(array $input, bool $isCreate): array {
        $errors = [];

        foreach (self::SERVER_FIELDS as $field) {
            if (array_key_exists($field, $input)) {
                $errors[$field] = 'Este campo lo asigna el servidor.';
            }
        }

        if (!$this->isAdmin() && array_key_exists('id_criador', $input)) {
            $errors['id_criador'] = 'El criador se toma del usuario autenticado.';
        }

        if ($this->isAdmin()) {
            $hasBreeder = array_key_exists('id_criador', $input);
            if (($isCreate || $hasBreeder) && $this->positiveInt($input['id_criador'] ?? null) === null) {
                $errors['id_criador'] = 'Debe indicar un identificador de criador válido.';
            }
        }

        if ($isCreate && $this->isAdmin() && $this->positiveInt($input['id_criador'] ?? null) === null) {
            $errors['id_criador'] = 'El administrador debe indicar el criador dueño del ejemplar.';
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
    private function filterFields(array $input, bool $includeBreeder = false): array {
        $allowed = self::WRITABLE_FIELDS;
        if ($includeBreeder) {
            $allowed[] = 'id_criador';
        }

        return array_intersect_key($input, array_flip($allowed));
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

    private function isAdmin(): bool {
        return AuthMiddleware::userRole() === 'administrador';
    }

    /**
     * ID del criadero asociado al usuario autenticado.
     */
    private function currentBreederId(): int {
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

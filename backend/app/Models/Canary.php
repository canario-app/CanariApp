<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use PDOException;
use RuntimeException;

/**
 * Modelo de la tabla canario según el esquema v7.1.
 *
 * El anillo se identifica con cuatro datos (número de anillo, sigla del club,
 * número de socio y temporada) y es único en todo el sistema. La base compara
 * el número de anillo y el de socio como enteros: '0005' y '5' son el mismo
 * anillo (uq_anillo).
 *
 * id_canario, id_criador y fecha_registro los asigna la base;
 * requiere_revision lo calcula el trigger trg_validar_sexo_variedad, así que
 * el cliente no puede escribirlo.
 */
class Canary extends BaseModel {
    protected string $table = 'canario';
    protected string $primaryKey = 'id_canario';

    /**
     * Campos que el cliente puede escribir. id_criador, fecha_registro y
     * requiere_revision se asignan en el servidor o en la base de datos.
     *
     * @var array<int, string>
     */
    private const ASSIGNABLE_FIELDS = [
        'anillo',
        'id_club',
        'numero_socio',
        'temporada',
        'sexo',
        'id_variedad',
    ];

    private const ERROR_INVALID_DATA = 'invalid_data';
    private const ERROR_CONFLICT_ANILLO = 'conflict_anillo';
    private const ERROR_INVALID_REFERENCE = 'invalid_reference';
    private const ERROR_NOT_FOUND = 'not_found';

    /**
     * Busca un canario por su PK junto con club, variedad y criador.
     *
     * @return array<string, mixed>|null
     */
    public function findDetailed(int $id): ?array {
        $sql = $this->detailedSelect()
            . ' WHERE c.id_canario = :id_canario'
            . ' LIMIT 1';

        return $this->fetch($sql, ['id_canario' => $id]);
    }

    /**
     * Lista canarios con detalle y filtros opcionales.
     *
     * Filtros admitidos: buscar (anillo o número de socio), id_club,
     * id_variedad y temporada. Si $idCriador no es null, solo devuelve
     * los canarios de ese criador.
     *
     * @param array<string, mixed> $filters
     * @return array<int, array<string, mixed>>
     */
    public function findAllDetailed(array $filters = [], ?int $idCriador = null): array {
        $conditions = [];
        $params = [];

        if ($idCriador !== null) {
            $conditions[] = 'c.id_criador = :id_criador';
            $params['id_criador'] = $idCriador;
        }

        $search = is_scalar($filters['buscar'] ?? null)
            ? trim((string) $filters['buscar'])
            : '';

        if ($search !== '') {
            // PDO con prepares nativos no admite repetir el mismo parámetro.
            $conditions[] = '(c.anillo ILIKE :buscar_anillo OR c.numero_socio ILIKE :buscar_socio)';
            $params['buscar_anillo'] = '%' . $search . '%';
            $params['buscar_socio'] = '%' . $search . '%';
        }

        foreach (['id_club', 'id_variedad', 'temporada'] as $field) {
            $value = $filters[$field] ?? null;
            if (is_scalar($value) && trim((string) $value) !== '') {
                $conditions[] = 'c.' . $field . ' = :' . $field;
                $params[$field] = (int) $value;
            }
        }

        $sql = $this->detailedSelect();

        if ($conditions !== []) {
            $sql .= ' WHERE ' . implode(' AND ', $conditions);
        }

        $sql .= ' ORDER BY c.id_canario DESC';

        return $this->fetchAll($sql, $params);
    }

    /**
     * Busca canarios por coincidencia parcial en anillo o número de socio.
     *
     * @return array<int, array<string, mixed>>
     */
    public function search(string $term, ?int $idCriador = null): array {
        return $this->findAllDetailed(['buscar' => $term], $idCriador);
    }

    /**
     * Busca un canario por el anillo completo (las cuatro partes).
     *
     * @return array<string, mixed>|null
     */
    public function findByAnillo(
        string $anillo,
        int $idClub,
        string $numeroSocio,
        int $temporada
    ): ?array {
        $ring = $this->normalizeRing($anillo, $numeroSocio, $temporada);
        if ($ring === null) {
            return null;
        }

        $sql = $this->detailedSelect()
            . ' WHERE c.anillo::INT = :anillo'
            . ' AND c.id_club = :id_club'
            . ' AND c.numero_socio::INT = :numero_socio'
            . ' AND c.temporada = :temporada'
            . ' LIMIT 1';

        return $this->fetch($sql, [
            'anillo'       => $ring['anillo'],
            'id_club'      => $idClub,
            'numero_socio' => $ring['numero_socio'],
            'temporada'    => $ring['temporada'],
        ]);
    }

    /**
     * Indica si el anillo completo ya existe en cualquier criadero.
     * En edición se excluye el propio canario con $excludeId.
     */
    public function anilloExists(
        string $anillo,
        int $idClub,
        string $numeroSocio,
        int $temporada,
        ?int $excludeId = null
    ): bool {
        $ring = $this->normalizeRing($anillo, $numeroSocio, $temporada);
        if ($ring === null) {
            return false;
        }

        $sql = 'SELECT 1 FROM ' . $this->quoteIdentifier($this->table)
            . ' WHERE anillo::INT = :anillo'
            . ' AND id_club = :id_club'
            . ' AND numero_socio::INT = :numero_socio'
            . ' AND temporada = :temporada';
        $params = [
            'anillo'       => $ring['anillo'],
            'id_club'      => $idClub,
            'numero_socio' => $ring['numero_socio'],
            'temporada'    => $ring['temporada'],
        ];

        if ($excludeId !== null) {
            $sql .= ' AND id_canario <> :id_canario';
            $params['id_canario'] = $excludeId;
        }

        $sql .= ' LIMIT 1';

        return $this->fetch($sql, $params) !== null;
    }

    /**
     * Comprueba que el canario pertenezca al criador indicado.
     */
    public function belongsToBreeder(int $idCanario, int $idCriador): bool {
        return $this->existsBy([
            'id_canario' => $idCanario,
            'id_criador' => $idCriador,
        ]);
    }

    /**
     * Crea un canario para el criador indicado.
     *
     * El número de socio se toma del cuerpo de la petición: es parte del
     * anillo del ejemplar, no se copia del perfil del criador.
     *
     * Devuelve el ID creado o un código de error de dominio.
     */
    public function createForBreeder(array $data, int $idCriador): int|string {
        $payload = $this->filterAssignable($data);
        $validation = $this->validate($payload, true);
        if ($validation !== null) {
            return $validation;
        }
        $payload = $this->normalizePayload($payload);

        if (
            $this->anilloExists(
                $payload['anillo'],
                $payload['id_club'],
                $payload['numero_socio'],
                $payload['temporada']
            )
        ) {
            return self::ERROR_CONFLICT_ANILLO;
        }

        $payload['id_criador'] = $idCriador;

        try {
            $id = $this->insert($payload);
        } catch (PDOException $exception) {
            return $this->mapWriteException($exception);
        }

        if ($id === null) {
            throw new RuntimeException('No se pudo obtener el ID del canario creado.');
        }

        return $id;
    }

    /**
     * Actualiza un canario solo si pertenece al criador indicado.
     *
     * Devuelve las filas afectadas (0 si no hubo cambios) o un código de
     * error de dominio.
     */
    public function updateForBreeder(int $id, array $data, int $idCriador): int|string {
        $payload = $this->filterAssignable($data);
        if ($payload === []) {
            return $this->belongsToBreeder($id, $idCriador) ? 0 : self::ERROR_NOT_FOUND;
        }

        $validation = $this->validate($payload, false);
        if ($validation !== null) {
            return $validation;
        }
        $payload = $this->normalizePayload($payload);

        $current = $this->find($id);
        if ($current === null || (int) $current['id_criador'] !== $idCriador) {
            return self::ERROR_NOT_FOUND;
        }

        $anillo = (string) ($payload['anillo'] ?? $current['anillo']);
        $idClub = (int) ($payload['id_club'] ?? $current['id_club']);
        $numeroSocio = (string) ($payload['numero_socio'] ?? $current['numero_socio']);
        $temporada = (int) ($payload['temporada'] ?? $current['temporada']);

        if ($this->anilloExists($anillo, $idClub, $numeroSocio, $temporada, $id)) {
            return self::ERROR_CONFLICT_ANILLO;
        }

        try {
            $affected = $this->updateBy(
                ['id_canario' => $id, 'id_criador' => $idCriador],
                $payload
            );
        } catch (PDOException $exception) {
            return $this->mapWriteException($exception);
        }

        if ($affected === 0 && !$this->belongsToBreeder($id, $idCriador)) {
            return self::ERROR_NOT_FOUND;
        }

        return $affected;
    }

    /**
     * SELECT base con los datos del canario y los nombres relacionados.
     */
    private function detailedSelect(): string {
        return 'SELECT c.id_canario, c.anillo, c.id_club, cl.sigla AS club_sigla,
                        c.numero_socio, c.temporada, c.sexo, c.id_variedad,
                        v.nombre AS variedad_nombre, c.id_criador,
                        u.nombre AS criador_nombre, c.fecha_registro,
                        c.requiere_revision
                 FROM ' . $this->quoteIdentifier($this->table) . ' c
                 INNER JOIN club cl ON c.id_club = cl.id_club
                 LEFT JOIN variedad v ON c.id_variedad = v.id_variedad
                 INNER JOIN criador cr ON c.id_criador = cr.id_criador
                 INNER JOIN usuario u ON cr.id_usuario = u.id_usuario';
    }

    /**
     * Deja solo los campos que el cliente puede escribir.
     *
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    private function filterAssignable(array $data): array {
        return array_intersect_key($data, array_flip(self::ASSIGNABLE_FIELDS));
    }

    /**
     * Valida los campos recibidos. En alta se exigen los cuatro datos del
     * anillo más sexo y variedad (una cría se registra por otro flujo).
     *
     * @param array<string, mixed> $data
     */
    private function validate(array $data, bool $isCreate): ?string {
        if ($isCreate) {
            foreach (self::ASSIGNABLE_FIELDS as $field) {
                if (!array_key_exists($field, $data)) {
                    return self::ERROR_INVALID_DATA;
                }
            }
        }

        if (array_key_exists('anillo', $data)) {
            $value = $data['anillo'];
            if (!is_scalar($value) || preg_match('/^[0-9]{1,6}$/', trim((string) $value)) !== 1) {
                return self::ERROR_INVALID_DATA;
            }
        }

        if (array_key_exists('numero_socio', $data)) {
            $value = $data['numero_socio'];
            if (!is_scalar($value) || preg_match('/^[0-9]{1,5}$/', trim((string) $value)) !== 1) {
                return self::ERROR_INVALID_DATA;
            }
        }

        if (array_key_exists('id_club', $data)) {
            if ($this->positiveInt($data['id_club']) === null) {
                return self::ERROR_INVALID_DATA;
            }
        }

        if (array_key_exists('id_variedad', $data)) {
            if ($this->positiveInt($data['id_variedad']) === null) {
                return self::ERROR_INVALID_DATA;
            }
        }

        if (array_key_exists('temporada', $data)) {
            $temporada = $this->positiveInt($data['temporada']);
            if ($temporada === null || $temporada < 1000 || $temporada > 9999) {
                return self::ERROR_INVALID_DATA;
            }
        }

        if (array_key_exists('sexo', $data)) {
            $sexo = $data['sexo'];
            if (!is_string($sexo) || !in_array($sexo, ['M', 'H'], true)) {
                return self::ERROR_INVALID_DATA;
            }
        }

        return null;
    }

    /**
     * Convierte enteros recibidos como JSON o query string a int positivo.
     */
    private function positiveInt(mixed $value): ?int {
        if (is_string($value)) {
            $value = trim($value);
        }
        if (!is_int($value) && !(is_string($value) && preg_match('/^[0-9]+$/', $value) === 1)) {
            return null;
        }

        $integer = (int) $value;

        return $integer > 0 ? $integer : null;
    }

    /**
     * Normaliza los tipos de los campos ya validados.
     *
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    private function normalizePayload(array $payload): array {
        if (array_key_exists('anillo', $payload)) {
            $payload['anillo'] = trim((string) $payload['anillo']);
        }
        if (array_key_exists('numero_socio', $payload)) {
            $payload['numero_socio'] = trim((string) $payload['numero_socio']);
        }
        foreach (['id_club', 'id_variedad', 'temporada'] as $field) {
            if (array_key_exists($field, $payload)) {
                $payload[$field] = (int) $payload[$field];
            }
        }

        return $payload;
    }

    /**
     * Parte numérica del anillo, tal como la compara el índice uq_anillo.
     *
     * @return array{anillo: int, numero_socio: int, temporada: int}|null
     */
    private function normalizeRing(string $anillo, string $numeroSocio, int $temporada): ?array {
        if (
            preg_match('/^[0-9]{1,6}$/', $anillo) !== 1
            || preg_match('/^[0-9]{1,5}$/', $numeroSocio) !== 1
            || $temporada < 1000
            || $temporada > 9999
        ) {
            return null;
        }

        return [
            'anillo'       => (int) $anillo,
            'numero_socio' => (int) $numeroSocio,
            'temporada'    => $temporada,
        ];
    }

    /**
     * Traduce errores de PostgreSQL a códigos de dominio.
     */
    private function mapWriteException(PDOException $exception): string {
        return match ((string) $exception->getCode()) {
            '23505' => self::ERROR_CONFLICT_ANILLO,
            '23503' => self::ERROR_INVALID_REFERENCE,
            '23502', '23514', '22P02', '22007', 'P0001' => self::ERROR_INVALID_DATA,
            default => throw $exception,
        };
    }
}

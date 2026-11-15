<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use PDOException;
use RuntimeException;

/**
 * Modelo de la tabla canario.
 *
 * Nota: el esquema no define UNIQUE sobre anillo, por lo que anilloExists()
 * valida en código (mejor esfuerzo). Si la BD agrega el índice, 23505 se
 * traduce igualmente a 'conflict_anillo'.
 */
class Canary extends BaseModel {
    protected string $table = 'canario';
    protected string $primaryKey = 'id_canario';

    /**
     * Campos que el cliente puede escribir. id_canario, id_criador y
     * numero_socio se asignan en el servidor.
     *
     * @var array<int, string>
     */
    private const ASSIGNABLE_FIELDS = [
        'anillo',
        'nombre',
        'sexo',
        'fecha_nacimiento',
        'disponibilidad',
        'id_color',
        'id_variedad',
        'id_club',
        'temporada',
        'requiere_revision',
    ];

    /**
     * Busca un canario por su PK junto con los nombres de color, variedad,
     * club y criador.
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
     * Filtros admitidos: buscar (anillo o nombre), disponibilidad,
     * id_color/color y temporada. Si $idCriador no es null, solo devuelve
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
            $conditions[] = '(c.anillo ILIKE :buscar_anillo OR c.nombre ILIKE :buscar_nombre)';
            $params['buscar_anillo'] = '%' . $search . '%';
            $params['buscar_nombre'] = '%' . $search . '%';
        }

        $availability = is_scalar($filters['disponibilidad'] ?? null)
            ? trim((string) $filters['disponibilidad'])
            : '';

        if ($availability !== '') {
            $conditions[] = 'c.disponibilidad = :disponibilidad';
            $params['disponibilidad'] = $availability;
        }

        $color = $filters['id_color'] ?? $filters['color'] ?? null;
        if (is_scalar($color) && $color !== '') {
            $conditions[] = 'c.id_color = :id_color';
            $params['id_color'] = (int) $color;
        }

        $season = $filters['temporada'] ?? null;
        if (is_scalar($season) && $season !== '') {
            $conditions[] = 'c.temporada = :temporada';
            $params['temporada'] = (int) $season;
        }

        $sql = $this->detailedSelect();

        if ($conditions !== []) {
            $sql .= ' WHERE ' . implode(' AND ', $conditions);
        }

        $sql .= ' ORDER BY c.id_canario DESC';

        return $this->fetchAll($sql, $params);
    }

    /**
     * Busca canarios por coincidencia parcial en anillo o nombre.
     *
     * @return array<int, array<string, mixed>>
     */
    public function search(string $term, ?int $idCriador = null): array {
        return $this->findAllDetailed(['buscar' => $term], $idCriador);
    }

    /**
     * Busca un canario por su anillo, opcionalmente acotado a un criador.
     *
     * @return array<string, mixed>|null
     */
    public function findByAnillo(string $anillo, ?int $idCriador = null): ?array {
        $sql = $this->detailedSelect() . ' WHERE c.anillo = :anillo';
        $params = ['anillo' => $anillo];

        if ($idCriador !== null) {
            $sql .= ' AND c.id_criador = :id_criador';
            $params['id_criador'] = $idCriador;
        }

        $sql .= ' LIMIT 1';

        return $this->fetch($sql, $params);
    }

    /**
     * Indica si el anillo ya está registrado. En edición se excluye el
     * propio canario con $excludeId; si se indica $idCriador, solo se
     * compara dentro de ese criador.
     */
    public function anilloExists(
        string $anillo,
        ?int $excludeId = null,
        ?int $idCriador = null
    ): bool {
        $sql = 'SELECT 1 FROM ' . $this->quoteIdentifier($this->table)
            . ' WHERE anillo = :anillo';
        $params = ['anillo' => $anillo];

        if ($idCriador !== null) {
            $sql .= ' AND id_criador = :id_criador';
            $params['id_criador'] = $idCriador;
        }

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
     * Crea un canario asignando el criador y el numero_socio del criador.
     *
     * Devuelve el ID creado o un código de error de dominio.
     */
    public function createForBreeder(array $data, int $idCriador): int|string {
        $anillo = trim((string) ($data['anillo'] ?? ''));

        if ($anillo !== '' && $this->anilloExists($anillo, null, $idCriador)) {
            return 'conflict_anillo';
        }

        $payload = $this->filterAssignable($data);
        $payload['id_criador'] = $idCriador;
        $payload['numero_socio'] = $this->findBreederMemberNumber($idCriador);
        $payload['disponibilidad'] ??= 'disponible';
        $payload['requiere_revision'] ??= false;

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
        $anillo = $data['anillo'] ?? null;

        if (
            is_string($anillo)
            && trim($anillo) !== ''
            && $this->anilloExists(trim($anillo), $id, $idCriador)
        ) {
            return 'conflict_anillo';
        }

        $payload = $this->filterAssignable($data);

        if ($payload === []) {
            return $this->belongsToBreeder($id, $idCriador) ? 0 : 'not_found';
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
            return 'not_found';
        }

        return $affected;
    }

    /**
     * Elimina un canario solo si pertenece al criador indicado.
     *
     * Devuelve las filas eliminadas o un código de error de dominio.
     */
    public function deleteForBreeder(int $id, int $idCriador): int|string {
        try {
            $affected = $this->deleteBy([
                'id_canario' => $id,
                'id_criador' => $idCriador,
            ]);
        } catch (PDOException $exception) {
            return $this->mapWriteException($exception, true);
        }

        return $affected > 0 ? $affected : 'not_found';
    }

    /**
     * SELECT base con los nombres relacionados. Se reutiliza en las lecturas.
     */
    private function detailedSelect(): string {
        return 'SELECT c.id_canario, c.anillo, c.nombre, c.sexo, c.fecha_nacimiento,
                       c.disponibilidad, c.id_color, co.nombre AS color_nombre,
                       c.numero_socio, c.temporada, c.id_club, cl.sigla AS club_sigla,
                       c.id_variedad, v.nombre AS variedad_nombre, c.id_criador,
                       u.nombre AS criador_nombre, c.requiere_revision
                FROM ' . $this->quoteIdentifier($this->table) . ' c
                LEFT JOIN color co ON c.id_color = co.id_color
                LEFT JOIN variedad v ON c.id_variedad = v.id_variedad
                LEFT JOIN club cl ON c.id_club = cl.id_club
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
     * Obtiene el numero_socio del criador (puede ser null según el esquema).
     */
    private function findBreederMemberNumber(int $idCriador): ?string {
        $value = $this->fetchColumn(
            'SELECT numero_socio FROM criador WHERE id_criador = :id_criador',
            ['id_criador' => $idCriador]
        );

        return $value === null ? null : (string) $value;
    }

    /**
     * Traduce errores de PostgreSQL a códigos de dominio.
     */
    private function mapWriteException(PDOException $exception, bool $isDelete = false): string {
        return match ((string) $exception->getCode()) {
            '23505' => 'conflict_anillo',
            '23503' => $isDelete ? 'has_history' : 'invalid_reference',
            '23502', '23514', '22P02', '22007' => 'invalid_reference',
            default => throw $exception,
        };
    }
}

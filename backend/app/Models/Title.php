<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use DateTimeImmutable;
use PDOException;

/**
 * Modelo para la tabla "titulo" (BD v7.1, SRS-RF023 y SRS-RF024).
 *
 * Un título pertenece a un ejemplar registrado en el criadero autenticado.
 * El ejemplar es inmutable (trg_titulo_canario_inmutable), por lo que solo se
 * pueden editar el nombre y la fecha. La unicidad (id_canario, nombre, fecha)
 * la refuerza la restricción uq_titulo de la base de datos.
 */
class Title extends BaseModel {
    public const ERROR_INVALID_DATA = 'invalid_data';
    public const ERROR_INVALID_REFERENCE = 'invalid_reference';
    public const ERROR_NOT_FOUND = 'not_found';
    public const ERROR_CONFLICT = 'conflict';
    public const ERROR_NO_TITLES = 'no_titles';
    public const ERROR_NO_OFFSPRING = 'no_offspring';

    private const NAME_MAX_LENGTH = 100;

    protected string $table = 'titulo';
    protected string $primaryKey = 'id_titulo';

    /** Campos que el cliente puede escribir al registrar un título. */
    private const CREATABLE_FIELDS = ['id_canario', 'nombre', 'fecha'];

    /** Campos editables: id_canario no se puede cambiar (SQL-04). */
    private const UPDATABLE_FIELDS = ['nombre', 'fecha'];

    /**
     * Busca un título por su clave primaria con los datos del ejemplar.
     *
     * @return array<string, mixed>|null
     */
    public function findDetailed(int $id_titulo): ?array {
        return $this->fetch(
            $this->detailedSelect() . ' WHERE t.id_titulo = :id_titulo LIMIT 1',
            ['id_titulo' => $id_titulo]
        );
    }

    /**
     * Lista los títulos de un criadero con filtros opcionales.
     *
     * Filtros admitidos: id_canario, nombre (coincidencia parcial) y fecha.
     *
     * @param array<string, mixed> $filters
     * @return array<int, array<string, mixed>>
     */
    public function findAllForBreeder(int $id_criador, array $filters = []): array {
        $where = ['c.id_criador = :id_criador'];
        $params = ['id_criador' => $id_criador];

        $id_canario = $this->positiveInt($filters['id_canario'] ?? null);
        if ($id_canario !== null) {
            $where[] = 't.id_canario = :id_canario';
            $params['id_canario'] = $id_canario;
        }

        $nombre = $filters['nombre'] ?? null;
        if (is_string($nombre) && trim($nombre) !== '') {
            $where[] = 't.nombre ILIKE :nombre';
            $params['nombre'] = '%' . trim($nombre) . '%';
        }

        $fecha = $filters['fecha'] ?? null;
        if (is_string($fecha) && $this->validDate($fecha)) {
            $where[] = 't.fecha = :fecha';
            $params['fecha'] = $fecha;
        }

        return $this->fetchAll(
            $this->detailedSelect()
            . ' WHERE ' . implode(' AND ', $where)
            . ' ORDER BY t.fecha DESC, t.id_titulo DESC',
            $params
        );
    }

    /** @return array<int, array<string, mixed>> */
    public function findAllForCanary(int $id_canario, int $id_criador): array {
        return $this->findAllForBreeder($id_criador, ['id_canario' => $id_canario]);
    }

    /**
     * Comprueba que un título pertenezca al criadero indicado.
     */
    public function belongsToBreeder(int $id_titulo, int $id_criador): bool {
        $sql = 'SELECT 1
                  FROM ' . $this->quoteIdentifier($this->table) . ' t
                  INNER JOIN canario c ON c.id_canario = t.id_canario
                 WHERE t.id_titulo = :id_titulo
                   AND c.id_criador = :id_criador
                 LIMIT 1';

        return $this->fetch($sql, [
            'id_titulo'  => $id_titulo,
            'id_criador' => $id_criador,
        ]) !== null;
    }

    /**
     * Registra un título para un ejemplar del criadero autenticado.
     *
     * @param array<string, mixed> $data
     * @return int|string ID generado o código de error de dominio.
     */
    public function createForBreeder(array $data, int $id_criador): int|string {
        $payload = array_intersect_key($data, array_flip(self::CREATABLE_FIELDS));

        $id_canario = $this->positiveInt($payload['id_canario'] ?? null);
        $nombre = $payload['nombre'] ?? null;
        $fecha = $payload['fecha'] ?? null;

        if ($id_canario === null || !$this->validName($nombre) || !$this->validDateValue($fecha)) {
            return self::ERROR_INVALID_DATA;
        }

        $canary = $this->fetch(
            'SELECT id_canario FROM canario
              WHERE id_canario = :id_canario AND id_criador = :id_criador
              LIMIT 1',
            ['id_canario' => $id_canario, 'id_criador' => $id_criador]
        );
        if ($canary === null) {
            return self::ERROR_INVALID_REFERENCE;
        }

        try {
            $id = $this->insert([
                'id_canario' => $id_canario,
                'nombre'     => trim((string) $nombre),
                'fecha'      => $fecha,
            ]);
        } catch (PDOException $exception) {
            return $this->mapWriteException($exception);
        }

        return $id ?? self::ERROR_INVALID_DATA;
    }

    /**
     * Actualiza el nombre o la fecha de un título del criadero autenticado.
     *
     * @param array<string, mixed> $data
     * @return int|string Filas afectadas o código de error de dominio.
     */
    public function updateForBreeder(int $id_titulo, array $data, int $id_criador): int|string {
        $payload = array_intersect_key($data, array_flip(self::UPDATABLE_FIELDS));

        if (!$this->belongsToBreeder($id_titulo, $id_criador)) {
            return self::ERROR_NOT_FOUND;
        }

        $updates = [];

        if (array_key_exists('nombre', $payload)) {
            if (!$this->validName($payload['nombre'])) {
                return self::ERROR_INVALID_DATA;
            }
            $updates['nombre'] = trim((string) $payload['nombre']);
        }

        if (array_key_exists('fecha', $payload)) {
            if (!$this->validDateValue($payload['fecha'])) {
                return self::ERROR_INVALID_DATA;
            }
            $updates['fecha'] = $payload['fecha'];
        }

        if ($updates === []) {
            return 0;
        }

        try {
            return $this->update($id_titulo, $updates);
        } catch (PDOException $exception) {
            return $this->mapWriteException($exception);
        }
    }

    /**
     * Crías de un ejemplar ganador agrupadas por el ejemplar con que se cruzó.
     *
     * SRS-RF024: se agrupa por la hembra si el ganador es macho y por el macho
     * si es hembra. El ejemplar debe pertenecer al criadero y tener al menos
     * un título registrado.
     *
     * @return array<int, array<string, mixed>>|string Grupos o código de error de dominio.
     */
    public function offspringForWinner(int $id_canario, int $id_criador): array|string {
        $canary = $this->fetch(
            'SELECT id_canario, sexo
               FROM canario
              WHERE id_canario = :id_canario AND id_criador = :id_criador
              LIMIT 1',
            ['id_canario' => $id_canario, 'id_criador' => $id_criador]
        );
        if ($canary === null) {
            return self::ERROR_NOT_FOUND;
        }

        $hasTitle = $this->fetch(
            'SELECT 1 FROM ' . $this->quoteIdentifier($this->table) . '
              WHERE id_canario = :id_canario
              LIMIT 1',
            ['id_canario' => $id_canario]
        );
        if ($hasTitle === null) {
            return self::ERROR_NO_TITLES;
        }

        $sexo = $canary['sexo'] ?? null;
        if ($sexo !== 'M' && $sexo !== 'H') {
            return self::ERROR_INVALID_DATA;
        }

        $partnerColumn = $sexo === 'M' ? 'p.id_hembra' : 'p.id_macho';
        $sql = 'SELECT ' . $partnerColumn . ' AS id_pareja_canario,
                       pc.anillo AS pareja_anillo, pc.temporada AS pareja_temporada,
                       pc.sexo AS pareja_sexo, cl.sigla AS pareja_club,
                       cr.id_cria, cr.id_canario AS id_cria_canario,
                       ca.anillo AS cria_anillo, ca.temporada AS cria_temporada,
                       ca.sexo AS cria_sexo, cr.es_portadora, cr.reservada,
                       n.fecha_nacimiento
                  FROM canario c
                  INNER JOIN pareja p ON p.id_criador = c.id_criador
                      AND (p.id_macho = c.id_canario OR p.id_hembra = c.id_canario)
                  INNER JOIN cruce crz ON crz.id_pareja = p.id_pareja
                  INNER JOIN nidada n ON n.id_cruce = crz.id_cruce
                  INNER JOIN cria cr ON cr.id_nidada = n.id_nidada
                  INNER JOIN canario ca ON ca.id_canario = cr.id_canario
                  INNER JOIN canario pc ON pc.id_canario = ' . $partnerColumn . '
                  INNER JOIN club cl ON cl.id_club = pc.id_club
                 WHERE c.id_canario = :id_canario
                   AND c.id_criador = :id_criador
                 ORDER BY pc.temporada, pc.anillo, ca.temporada, ca.anillo, cr.id_cria';

        $rows = $this->fetchAll($sql, [
            'id_canario' => $id_canario,
            'id_criador' => $id_criador,
        ]);

        if ($rows === []) {
            return self::ERROR_NO_OFFSPRING;
        }

        $groups = [];
        foreach ($rows as $row) {
            $partnerId = (int) $row['id_pareja_canario'];
            if (!isset($groups[$partnerId])) {
                $groups[$partnerId] = [
                    'id_canario' => $partnerId,
                    'anillo'     => $row['pareja_anillo'],
                    'club'       => $row['pareja_club'],
                    'temporada'  => (int) $row['pareja_temporada'],
                    'sexo'       => $row['pareja_sexo'],
                    'crias'      => [],
                ];
            }

            $groups[$partnerId]['crias'][] = [
                'id_cria'          => (int) $row['id_cria'],
                'id_canario'       => (int) $row['id_cria_canario'],
                'anillo'           => $row['cria_anillo'],
                'temporada'        => (int) $row['cria_temporada'],
                'sexo'             => $row['cria_sexo'],
                'fecha_nacimiento' => $row['fecha_nacimiento'],
                'es_portadora'     => $row['es_portadora'],
                'reservada'        => $row['reservada'],
            ];
        }

        return array_values($groups);
    }

    /** Consulta base con los datos del título y del ejemplar ganador. */
    private function detailedSelect(): string {
        return 'SELECT t.id_titulo, t.id_canario, t.nombre, t.fecha,
                       c.id_criador, c.anillo, c.numero_socio, c.temporada, c.sexo,
                       cl.id_club, cl.sigla AS club_sigla
                  FROM ' . $this->quoteIdentifier($this->table) . ' t
                  INNER JOIN canario c ON c.id_canario = t.id_canario
                  INNER JOIN club cl ON cl.id_club = c.id_club';
    }

    private function validName(mixed $value): bool {
        return is_string($value)
            && trim($value) !== ''
            && mb_strlen(trim($value), 'UTF-8') <= self::NAME_MAX_LENGTH;
    }

    private function validDateValue(mixed $value): bool {
        if (!is_string($value) || !$this->validDate($value)) {
            return false;
        }

        // SRS-RF023: la fecha no puede ser posterior a la fecha actual.
        return $value <= date('Y-m-d');
    }

    private function validDate(string $value): bool {
        $parsed = DateTimeImmutable::createFromFormat('!Y-m-d', $value);

        return $parsed !== false && $parsed->format('Y-m-d') === $value;
    }

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

    /** Traduce códigos SQLSTATE de PostgreSQL a códigos de error de dominio. */
    private function mapWriteException(PDOException $exception): string {
        return match ((string) $exception->getCode()) {
            '23505' => self::ERROR_CONFLICT,
            '23503' => self::ERROR_INVALID_REFERENCE,
            '23502', '23514', '22P02', '22007' => self::ERROR_INVALID_DATA,
            'P0001' => self::ERROR_CONFLICT,
            default => throw $exception,
        };
    }
}

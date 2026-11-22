<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use DateTimeImmutable;
use PDOException;

/**
 * Modelo para la tabla "cruce" según el esquema v7.1.
 *
 * Un cruce registra la fecha en que se apareó una pareja activa. Según
 * SRS-RF016 una pareja puede tener varios cruces; según SQL-01 la pareja de
 * un cruce es inmutable. El criadero se obtiene de la pareja, por lo que el
 * cliente nunca envía id_criador.
 */
class Mating extends BaseModel {
    public const ERROR_INVALID_DATA = 'invalid_data';
    public const ERROR_INVALID_REFERENCE = 'invalid_reference';
    public const ERROR_NOT_FOUND = 'not_found';
    public const ERROR_CONFLICT = 'conflict';

    protected string $table = 'cruce';
    protected string $primaryKey = 'id_cruce';

    /**
     * Busca un cruce por su clave primaria junto con los datos de la pareja.
     *
     * @return array<string, mixed>|null
     */
    public function findDetailed(int $id): ?array {
        $sql = $this->detailedSelect()
            . ' WHERE c.id_cruce = :id_cruce'
            . ' LIMIT 1';

        return $this->fetch($sql, ['id_cruce' => $id]);
    }

    /**
     * Lista los cruces de un criadero con filtros opcionales.
     *
     * @param array<string, mixed> $filters
     * @return array<int, array<string, mixed>>
     */
    public function findAllForBreeder(int $id_criador, array $filters = []): array {
        $conditions = ['p.id_criador = :id_criador'];
        $params = ['id_criador' => $id_criador];

        $id_pareja = $this->positiveInt($filters['id_pareja'] ?? null);
        if ($id_pareja !== null) {
            $conditions[] = 'c.id_pareja = :id_pareja';
            $params['id_pareja'] = $id_pareja;
        }

        $fecha = $filters['fecha_cruce'] ?? null;
        if (is_string($fecha) && $fecha !== '' && $this->validDate($fecha)) {
            $conditions[] = 'c.fecha_cruce = :fecha_cruce';
            $params['fecha_cruce'] = $fecha;
        }

        $sql = $this->detailedSelect()
            . ' WHERE ' . implode(' AND ', $conditions)
            . ' ORDER BY c.fecha_cruce DESC, c.id_cruce DESC';

        return $this->fetchAll($sql, $params);
    }

    /**
     * Lista los cruces de una pareja perteneciente al criadero indicado.
     *
     * @return array<int, array<string, mixed>>
     */
    public function findAllForPair(int $id_pareja, int $id_criador): array {
        return $this->findAllForBreeder($id_criador, ['id_pareja' => $id_pareja]);
    }

    /**
     * Verifica si un cruce pertenece al criadero indicado.
     */
    public function belongsToBreeder(int $id_cruce, int $id_criador): bool {
        $sql = 'SELECT 1
                  FROM ' . $this->quoteIdentifier($this->table) . ' c
                  INNER JOIN pareja p ON p.id_pareja = c.id_pareja
                 WHERE c.id_cruce = :id_cruce
                   AND p.id_criador = :id_criador
                 LIMIT 1';

        return $this->fetch($sql, [
            'id_cruce'   => $id_cruce,
            'id_criador' => $id_criador,
        ]) !== null;
    }

    /**
     * Registra un cruce para una pareja activa del criadero indicado.
     *
     * @param array<string, mixed> $data
     * @return int|string ID del cruce creado o código de error de dominio.
     */
    public function createForBreeder(array $data, int $id_criador): int|string {
        $id_pareja = $this->positiveInt($data['id_pareja'] ?? null);
        if ($id_pareja === null) {
            return self::ERROR_INVALID_DATA;
        }

        $fecha = $this->resolveFecha($data);
        if ($fecha === null) {
            return self::ERROR_INVALID_DATA;
        }

        $pareja = $this->findPairForBreeder($id_pareja, $id_criador);
        if ($pareja === null) {
            return self::ERROR_NOT_FOUND;
        }

        if (($pareja['estado'] ?? null) !== 'activa') {
            return self::ERROR_CONFLICT;
        }

        try {
            $id = $this->insert([
                'id_pareja'  => $id_pareja,
                'fecha_cruce' => $fecha,
            ]);
        } catch (PDOException $exception) {
            return $this->mapWriteException($exception);
        }

        return $id ?? self::ERROR_INVALID_DATA;
    }

    /**
     * Obtiene una pareja del criadero indicado.
     *
     * @return array<string, mixed>|null
     */
    private function findPairForBreeder(int $id_pareja, int $id_criador): ?array {
        $sql = 'SELECT id_pareja, id_criador, estado
                  FROM pareja
                 WHERE id_pareja = :id_pareja
                   AND id_criador = :id_criador
                 LIMIT 1';

        return $this->fetch($sql, [
            'id_pareja'  => $id_pareja,
            'id_criador' => $id_criador,
        ]);
    }

    /**
     * La fecha es obligatoria, tiene formato YYYY-MM-DD y no es futura
     * (SRS-RF016, CHECK de cruce.fecha_cruce).
     */
    private function resolveFecha(array $data): ?string {
        if (!array_key_exists('fecha_cruce', $data)) {
            return null;
        }

        $value = $data['fecha_cruce'];
        if (!is_string($value) || !$this->validDate($value)) {
            return null;
        }

        return $value > date('Y-m-d') ? null : $value;
    }

    private function validDate(string $value): bool {
        $parsed = DateTimeImmutable::createFromFormat('!Y-m-d', $value);

        return $parsed !== false
            && $parsed->format('Y-m-d') === $value;
    }

    /**
     * Consulta SELECT base con los anillos de los progenitores y el criadero.
     */
    private function detailedSelect(): string {
        return 'SELECT c.id_cruce, c.id_pareja, c.fecha_cruce,
                       p.id_criador, p.id_macho, p.id_hembra,
                       cm.anillo AS anillo_macho,
                       ch.anillo AS anillo_hembra
                  FROM ' . $this->quoteIdentifier($this->table) . ' c
                  INNER JOIN pareja p ON p.id_pareja = c.id_pareja
                  INNER JOIN canario cm ON cm.id_canario = p.id_macho
                  INNER JOIN canario ch ON ch.id_canario = p.id_hembra';
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

    /**
     * Traduce códigos SQLSTATE de PostgreSQL a códigos de error de dominio.
     */
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

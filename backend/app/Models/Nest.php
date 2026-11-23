<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use DateTimeImmutable;
use PDOException;

/** Modelo para nidada: cada registro pertenece a un cruce de una pareja. */
class Nest extends BaseModel {
    public const ERROR_INVALID_DATA = 'invalid_data';
    public const ERROR_INVALID_REFERENCE = 'invalid_reference';
    public const ERROR_NOT_FOUND = 'not_found';

    protected string $table = 'nidada';
    protected string $primaryKey = 'id_nidada';

    /** @param array<string,mixed> $filters @return array<int,array<string,mixed>> */
    public function findAllForBreeder(int $id_criador, array $filters = []): array {
        $where = ['p.id_criador = :id_criador'];
        $params = ['id_criador' => $id_criador];
        $id_cruce = $this->positiveInt($filters['id_cruce'] ?? null);
        if ($id_cruce !== null) {
            $where[] = 'n.id_cruce = :id_cruce';
            $params['id_cruce'] = $id_cruce;
        }
        $fecha = $filters['fecha_nacimiento'] ?? null;
        if (is_string($fecha) && $this->validDate($fecha)) {
            $where[] = 'n.fecha_nacimiento = :fecha_nacimiento';
            $params['fecha_nacimiento'] = $fecha;
        }
        return $this->fetchAll(
            $this->detailedSelect() . ' WHERE ' . implode(' AND ', $where)
            . ' ORDER BY n.fecha_nacimiento DESC, n.id_nidada DESC',
            $params
        );
    }

    /** @return array<int,array<string,mixed>> */
    public function findAllForMating(int $id_cruce, int $id_criador): array {
        return $this->findAllForBreeder($id_criador, ['id_cruce' => $id_cruce]);
    }

    /** @return array<string,mixed>|null */
    public function findDetailed(int $id_nidada): ?array {
        return $this->fetch($this->detailedSelect() . ' WHERE n.id_nidada = :id_nidada LIMIT 1', [
            'id_nidada' => $id_nidada,
        ]);
    }

    /** @param array<string,mixed> $data @return int|string */
    public function createForBreeder(array $data, int $id_criador): int|string {
        $id_cruce = $this->positiveInt($data['id_cruce'] ?? null);
        $fecha = $data['fecha_nacimiento'] ?? null;
        if ($id_cruce === null || !is_string($fecha) || !$this->validDate($fecha) || $fecha > date('Y-m-d')) {
            return self::ERROR_INVALID_DATA;
        }

        $cruce = $this->fetch(
            'SELECT c.id_cruce, c.fecha_cruce
               FROM cruce c INNER JOIN pareja p ON p.id_pareja = c.id_pareja
              WHERE c.id_cruce = :id_cruce AND p.id_criador = :id_criador LIMIT 1',
            ['id_cruce' => $id_cruce, 'id_criador' => $id_criador]
        );
        if ($cruce === null) {
            return self::ERROR_NOT_FOUND;
        }
        // SRS-RF018: fecha de nacimiento igual o posterior a la fecha del cruce.
        if ($fecha < (string) $cruce['fecha_cruce']) {
            return self::ERROR_INVALID_DATA;
        }

        try {
            $id = $this->insert(['id_cruce' => $id_cruce, 'fecha_nacimiento' => $fecha]);
        } catch (PDOException $exception) {
            return match ((string) $exception->getCode()) {
                '23503' => self::ERROR_INVALID_REFERENCE,
                '23502', '23514', '22P02', '22007', 'P0001' => self::ERROR_INVALID_DATA,
                default => throw $exception,
            };
        }
        return $id ?? self::ERROR_INVALID_DATA;
    }

    private function detailedSelect(): string {
        return 'SELECT n.id_nidada, n.id_cruce, n.fecha_nacimiento,
                       p.id_criador, p.id_pareja, c.fecha_cruce,
                       p.id_macho, p.id_hembra,
                       cm.anillo AS anillo_macho, ch.anillo AS anillo_hembra
                  FROM ' . $this->quoteIdentifier($this->table) . ' n
                  INNER JOIN cruce c ON c.id_cruce = n.id_cruce
                  INNER JOIN pareja p ON p.id_pareja = c.id_pareja
                  INNER JOIN canario cm ON cm.id_canario = p.id_macho
                  INNER JOIN canario ch ON ch.id_canario = p.id_hembra';
    }

    private function positiveInt(mixed $value): ?int {
        if (is_string($value)) $value = trim($value);
        if (!is_int($value) && !(is_string($value) && preg_match('/^[0-9]+$/', $value) === 1)) return null;
        $integer = (int) $value;
        return $integer > 0 ? $integer : null;
    }

    private function validDate(string $value): bool {
        $parsed = DateTimeImmutable::createFromFormat('!Y-m-d', $value);
        return $parsed !== false && $parsed->format('Y-m-d') === $value;
    }
}

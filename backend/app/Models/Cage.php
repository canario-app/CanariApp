<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use PDOException;

/**
 * Acceso a los datos de jaulas del criadero.
 *
 * La disponibilidad no se almacena en jaula: se calcula comprobando si
 * existe una pareja activa asociada (SRS-RF014 y SRS-RF017).
 */
class Cage extends BaseModel {
    public const ERROR_CONFLICT = 'conflict';
    public const ERROR_INVALID_REFERENCE = 'invalid_reference';
    public const ERROR_INVALID_DATA = 'invalid_data';

    protected string $table = 'jaula';
    protected string $primaryKey = 'id_jaula';

    /**
     * Lista las jaulas de un criador e informa si están ocupadas.
     *
     * @return array<int, array<string, mixed>>
     */
    public function findAllDetailed(int $idCriador): array {
        $sql = "
            SELECT
                j.id_jaula,
                j.numero_jaula,
                j.id_criador,
                CASE WHEN EXISTS (
                    SELECT 1
                    FROM pareja p
                    WHERE p.id_jaula = j.id_jaula
                      AND p.id_criador = j.id_criador
                      AND p.estado = 'activa'
                ) THEN TRUE ELSE FALSE END AS ocupada
            FROM jaula j
            WHERE j.id_criador = :id_criador
            ORDER BY j.numero_jaula ASC
        ";

        return $this->fetchAll($sql, ['id_criador' => $idCriador]);
    }

    /**
     * Busca una jaula perteneciente al criador indicado.
     *
     * @return array<string, mixed>|null
     */
    public function findDetailed(int $idJaula, int $idCriador): ?array {
        $sql = "
            SELECT
                j.id_jaula,
                j.numero_jaula,
                j.id_criador,
                CASE WHEN EXISTS (
                    SELECT 1
                    FROM pareja p
                    WHERE p.id_jaula = j.id_jaula
                      AND p.id_criador = j.id_criador
                      AND p.estado = 'activa'
                ) THEN TRUE ELSE FALSE END AS ocupada
            FROM jaula j
            WHERE j.id_jaula = :id_jaula
              AND j.id_criador = :id_criador
            LIMIT 1
        ";

        return $this->fetch($sql, [
            'id_jaula' => $idJaula,
            'id_criador' => $idCriador,
        ]);
    }

    /**
     * Registra una jaula para el criadero autenticado.
     *
     * @return int|string Código de error o ID generado.
     */
    public function createForBreeder(int $numeroJaula, int $idCriador): int|string {
        try {
            $id = $this->insert([
                'numero_jaula' => $numeroJaula,
                'id_criador' => $idCriador,
            ]);

            return $id ?? self::ERROR_INVALID_DATA;
        } catch (PDOException $exception) {
            return match ((string) $exception->getCode()) {
                '23505' => self::ERROR_CONFLICT,
                '23503' => self::ERROR_INVALID_REFERENCE,
                '23502', '23514', '22P02', '22003' => self::ERROR_INVALID_DATA,
                default => throw $exception,
            };
        }
    }
}

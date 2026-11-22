<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use PDOException;
use RuntimeException;

/**
 * Modelo para la tabla "pareja" según el esquema v7.1.
 *
 * Aplica el aislamiento por criadero mediante id_criador y traduce las
 * restricciones y triggers de la base de datos a códigos de dominio.
 */
class Pair extends BaseModel {
    protected string $table = 'pareja';
    protected string $primaryKey = 'id_pareja';

    /**
     * Campos permitidos al crear una nueva pareja.
     *
     * @var array<int, string>
     */
    private const CREATABLE_FIELDS = [
        'id_macho',
        'id_hembra',
        'id_jaula',
        'fecha_formacion',
    ];

    /**
     * Campos permitidos al actualizar una pareja existente.
     *
     * @var array<int, string>
     */
    private const UPDATABLE_FIELDS = [
        'id_jaula',
        'estado',
        'fecha_fin',
    ];

    private const ALLOWED_STATES = ['activa', 'finalizada', 'anulada'];

    private const ERROR_INVALID_DATA = 'invalid_data';
    private const ERROR_INVALID_REFERENCE = 'invalid_reference';
    private const ERROR_NOT_FOUND = 'not_found';
    private const ERROR_CONFLICT = 'conflict';

    /**
     * Busca una pareja por su clave primaria junto con datos de jaula y progenitores.
     *
     * @return array<string, mixed>|null
     */
    public function findDetailed(int $id): ?array {
        $sql = $this->detailedSelect()
            . ' WHERE p.id_pareja = :id_pareja'
            . ' LIMIT 1';

        return $this->fetch($sql, ['id_pareja' => $id]);
    }

    /**
     * Lista las parejas de un criador con filtros opcionales.
     *
     * @param array<string, mixed> $filters
     * @return array<int, array<string, mixed>>
     */
    public function findAllForBreeder(int $id_criador, array $filters = []): array {
        $conditions = ['p.id_criador = :id_criador'];
        $params = ['id_criador' => $id_criador];

        $estado = $filters['estado'] ?? null;
        if (is_string($estado) && in_array($estado, self::ALLOWED_STATES, true)) {
            $conditions[] = 'p.estado = :estado';
            $params['estado'] = $estado;
        }

        foreach (['id_macho', 'id_hembra', 'id_jaula'] as $field) {
            $value = $filters[$field] ?? null;
            if (is_scalar($value) && trim((string) $value) !== '') {
                $intVal = $this->positiveInt($value);
                if ($intVal !== null) {
                    $conditions[] = 'p.' . $field . ' = :' . $field;
                    $params[$field] = $intVal;
                }
            }
        }

        $sql = $this->detailedSelect()
            . ' WHERE ' . implode(' AND ', $conditions)
            . ' ORDER BY p.id_pareja DESC';

        return $this->fetchAll($sql, $params);
    }

    /**
     * Verifica si una pareja pertenece al criador indicado.
     */
    public function belongsToBreeder(int $id_pareja, int $id_criador): bool {
        return $this->existsBy([
            'id_pareja'  => $id_pareja,
            'id_criador' => $id_criador,
        ]);
    }

    /**
     * Crea una nueva pareja para el criador indicado.
     *
     * @param array<string, mixed> $data
     */
    public function createForBreeder(array $data, int $id_criador): int|string {
        $payload = array_intersect_key($data, array_flip(self::CREATABLE_FIELDS));

        foreach (['id_macho', 'id_hembra', 'id_jaula'] as $required_id) {
            if (!array_key_exists($required_id, $payload) || $this->positiveInt($payload[$required_id]) === null) {
                return self::ERROR_INVALID_DATA;
            }
            $payload[$required_id] = (int) $payload[$required_id];
        }

        if ($payload['id_macho'] === $payload['id_hembra']) {
            return self::ERROR_INVALID_DATA;
        }

        if (array_key_exists('fecha_formacion', $payload) && $payload['fecha_formacion'] !== null && $payload['fecha_formacion'] !== '') {
            if (!is_string($payload['fecha_formacion']) || preg_match('/^\d{4}-\d{2}-\d{2}$/', $payload['fecha_formacion']) !== 1) {
                return self::ERROR_INVALID_DATA;
            }
        } else {
            unset($payload['fecha_formacion']);
        }

        $payload['id_criador'] = $id_criador;
        $payload['estado'] = 'activa';
        $payload['fecha_fin'] = null;

        try {
            $id = $this->insert($payload);
        } catch (PDOException $exception) {
            return $this->mapWriteException($exception);
        }

        if ($id === null) {
            throw new RuntimeException('No se pudo obtener el ID de la pareja creada.');
        }

        return $id;
    }

    /**
     * Actualiza una pareja que pertenece al criador indicado.
     *
     * @param array<string, mixed> $data
     */
    public function updateForBreeder(int $id_pareja, array $data, int $id_criador): int|string {
        $payload = array_intersect_key($data, array_flip(self::UPDATABLE_FIELDS));
        if ($payload === []) {
            return $this->belongsToBreeder($id_pareja, $id_criador) ? 0 : self::ERROR_NOT_FOUND;
        }

        $current = $this->find($id_pareja);
        if ($current === null || (int) $current['id_criador'] !== $id_criador) {
            return self::ERROR_NOT_FOUND;
        }

        if (array_key_exists('id_jaula', $payload)) {
            $cage_id = $this->positiveInt($payload['id_jaula']);
            if ($cage_id === null) {
                return self::ERROR_INVALID_DATA;
            }
            $payload['id_jaula'] = $cage_id;
        }

        if (array_key_exists('estado', $payload)) {
            if (!is_string($payload['estado']) || !in_array($payload['estado'], self::ALLOWED_STATES, true)) {
                return self::ERROR_INVALID_DATA;
            }

            if ($payload['estado'] !== 'activa') {
                if (!array_key_exists('fecha_fin', $payload) || $payload['fecha_fin'] === null || $payload['fecha_fin'] === '') {
                    $payload['fecha_fin'] = date('Y-m-d');
                }
            }
        }

        if (array_key_exists('fecha_fin', $payload) && $payload['fecha_fin'] !== null && $payload['fecha_fin'] !== '') {
            if (!is_string($payload['fecha_fin']) || preg_match('/^\d{4}-\d{2}-\d{2}$/', $payload['fecha_fin']) !== 1) {
                return self::ERROR_INVALID_DATA;
            }

            // Verifica que fecha_fin no sea anterior a fecha_formacion antes de consultar la BD.
            if (isset($current['fecha_formacion']) && $payload['fecha_fin'] < (string) $current['fecha_formacion']) {
                return self::ERROR_INVALID_DATA;
            }
        }

        try {
            $affected = $this->updateBy(
                ['id_pareja' => $id_pareja, 'id_criador' => $id_criador],
                $payload
            );
        } catch (PDOException $exception) {
            return $this->mapWriteException($exception);
        }

        if ($affected === 0 && !$this->belongsToBreeder($id_pareja, $id_criador)) {
            return self::ERROR_NOT_FOUND;
        }

        return $affected;
    }

    /**
     * Consulta SELECT base uniendo la jaula y los anillos de ambos progenitores.
     */
    private function detailedSelect(): string {
        return 'SELECT p.id_pareja, p.id_criador, p.id_macho, p.id_hembra,
                        p.id_jaula, j.numero_jaula, p.fecha_formacion,
                        p.estado, p.fecha_fin,
                        cm.anillo AS anillo_macho,
                        ch.anillo AS anillo_hembra
                 FROM ' . $this->quoteIdentifier($this->table) . ' p
                 INNER JOIN jaula j ON p.id_jaula = j.id_jaula
                 INNER JOIN canario cm ON p.id_macho = cm.id_canario
                 INNER JOIN canario ch ON p.id_hembra = ch.id_canario';
    }

    /**
     * Convierte un valor en entero positivo o devuelve null.
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

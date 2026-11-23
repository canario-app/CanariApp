<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use PDOException;
use RuntimeException;
use Throwable;

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
     * Campos permitidos al actualizar una pareja en modo estándar.
     *
     * @var array<int, string>
     */
    private const UPDATABLE_FIELDS = [
        'id_jaula',
        'estado',
        'fecha_fin',
    ];

    /**
     * Campos permitidos al actualizar una pareja con Modo de Corrección activo.
     * Permite reasignar progenitores en parejas con cruces (SRS-RF031).
     *
     * @var array<int, string>
     */
    private const CORRECTION_UPDATABLE_FIELDS = [
        'id_macho',
        'id_hembra',
        'id_jaula',
        'estado',
        'fecha_fin',
    ];

    private const ALLOWED_STATES = ['activa', 'finalizada', 'anulada'];

    private const ERROR_INVALID_DATA = 'invalid_data';
    private const ERROR_INVALID_REFERENCE = 'invalid_reference';
    private const ERROR_NOT_FOUND = 'not_found';
    private const ERROR_CONFLICT = 'conflict';
    private const ERROR_CORRECTION_REQUIRED = 'correction_mode_required';
    private const ERROR_MATINGS_ANNUL_CONFLICT = 'matings_annul_conflict';
    private const ERROR_CONSANGUINITY = 'consanguinity_conflict';

    /**
     * Busca una pareja por su clave primaria junto con datos de jaula y progenitores.
     *
     * @return array<string, mixed>|null
     */
    public function findDetailed(int $id): ?array {
        $sql =$this->detailedSelect()
            . ' WHERE p.id_pareja = :id_pareja'
            . ' LIMIT 1';

        return $this->fetch($sql, ['id_pareja' =>$id]);
    }

    /**
     * Lista las parejas de un criador con filtros opcionales.
     *
     * @param array<string, mixed> $filters
     * @return array<int, array<string, mixed>>
     */
    public function findAllForBreeder(int $id_criador, array $filters = []): array {$conditions = ['p.id_criador = :id_criador'];
        $params = ['id_criador' =>$id_criador];

        $estado =$filters['estado'] ?? null;
        if (is_string($estado) && in_array($estado, self::ALLOWED_STATES, true)) {$conditions[] = 'p.estado = :estado';
            $params['estado'] =$estado;
        }

        foreach (['id_macho', 'id_hembra', 'id_jaula'] as $field) {$value = $filters[$field] ?? null;
            if (is_scalar($value) && trim((string) $value) !== '') {$intVal = $this->positiveInt($value);
                if ($intVal !== null) {$conditions[] = 'p.' . $field . ' = :' .$field;
                    $params[$field] =$intVal;
                }
            }
        }

        $sql =$this->detailedSelect()
            . ' WHERE ' . implode(' AND ', $conditions)
            . ' ORDER BY p.id_pareja DESC';

        return $this->fetchAll($sql,$params);
    }

    /**
     * Verifica si una pareja pertenece al criador indicado.
     */
    public function belongsToBreeder(int $id_pareja, int$id_criador): bool {
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
    public function createForBreeder(array $data, int$id_criador): int|string {
        $payload = array_intersect_key($data, array_flip(self::CREATABLE_FIELDS));

        foreach (['id_macho', 'id_hembra', 'id_jaula'] as $required_id) {
            if (!array_key_exists($required_id, $payload) || $this->positiveInt($payload[$required_id]) === null) {
                return self::ERROR_INVALID_DATA;
            }
            $payload[$required_id] = (int) $payload[$required_id];
        }

        if ($payload['id_macho'] ===$payload['id_hembra']) {
            return self::ERROR_INVALID_DATA;
        }

        if (array_key_exists('fecha_formacion', $payload) && $payload['fecha_formacion'] !== null &&$payload['fecha_formacion'] !== '') {
            if (!is_string($payload['fecha_formacion']) || preg_match('/^\d{4}-\d{2}-\d{2}$/',$payload['fecha_formacion']) !== 1) {
                return self::ERROR_INVALID_DATA;
            }
        } else {
            unset($payload['fecha_formacion']);
        }

        $payload['id_criador'] =$id_criador;
        $payload['estado'] = 'activa';$payload['fecha_fin'] = null;

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
     * Actualiza una pareja en modo estándar (solo jaula, estado o fecha_fin).
     * Rechaza cualquier intento de modificar id_macho o id_hembra sin Modo de Corrección.
     *
     * @param array<string, mixed> $data
     */
    public function updateForBreeder(int $id_pareja, array $data, int $id_criador): int|string {
        $current = $this->find($id_pareja);
        if ($current === null || (int) $current['id_criador'] !== $id_criador) {
            return self::ERROR_NOT_FOUND;
        }

        if (array_key_exists('id_macho', $data) || array_key_exists('id_hembra', $data)) {
            return self::ERROR_CORRECTION_REQUIRED;
        }

        $payload = array_intersect_key($data, array_flip(self::UPDATABLE_FIELDS));
        if ($payload === []) {
            return 0;
        }

        $normalized = $this->validateAndNormalizeUpdatePayload($payload, $current);
        if (is_string($normalized)) {
            return $normalized;
        }

        try {
            $affected = $this->updateBy(
                ['id_pareja' => $id_pareja, 'id_criador' => $id_criador],
                $normalized
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
     * Actualiza una pareja con Modo de Corrección activo (SRS-RF031).
     *
     * Permite reasignar id_macho o id_hembra dentro de una transacción,
     * respetando las validaciones de sexo, criadero, límite de parejas activas
     * y consanguinidad directa verificadas por trg_validar_pareja.
     *
     * @param array<string, mixed> $data
     * @return array{previous: array<string, mixed>, updated: array<string, mixed>}|string
     */
    public function updateWithCorrection(int $id_pareja, array $data, int$id_criador): array|string {
        $payload = array_intersect_key($data, array_flip(self::CORRECTION_UPDATABLE_FIELDS));

        try {
            $this->beginTransaction();

            $current =$this->fetch(
                'SELECT * FROM ' . $this->quoteIdentifier($this->table)
                . ' WHERE id_pareja = :id_pareja AND id_criador = :id_criador FOR UPDATE',
                ['id_pareja' => $id_pareja, 'id_criador' =>$id_criador]
            );

            if ($current === null) {$this->rollBack();

                return self::ERROR_NOT_FOUND;
            }

            if ($payload === []) {$this->commit();
                $detailed =$this->findDetailed($id_pareja) ?? $current;

                return ['previous' => $current, 'updated' =>$detailed];
            }

            $normalized =$this->validateAndNormalizeUpdatePayload($payload,$current);
            if (is_string($normalized)) {$this->rollBack();

                return $normalized;
            }

            $this->updateBy(
                ['id_pareja' => $id_pareja, 'id_criador' => $id_criador],$normalized
            );

            $this->commit();
        } catch (PDOException $exception) {$this->rollBack();

            return $this->mapWriteException($exception);
        } catch (Throwable $exception) {$this->rollBack();
            throw $exception;
        }

        $updated =$this->findDetailed($id_pareja) ?? $current;

        return [
            'previous' => $current,
            'updated'  => $updated,
        ];
    }

    /**
     * Valida y normaliza los campos de actualización de una pareja.
     *
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $current
     * @return array<string, mixed>|string
     */
    private function validateAndNormalizeUpdatePayload(array $payload, array$current): array|string {
        foreach (['id_macho', 'id_hembra', 'id_jaula'] as $fkField) {
            if (array_key_exists($fkField,$payload)) {
                $idValue =$this->positiveInt($payload[$fkField]);
                if ($idValue === null) { return self::ERROR_INVALID_DATA; }$payload[$fkField] =$idValue;
            }
        }

        $effectiveMacho = (int) ($payload['id_macho'] ?? $current['id_macho']);$effectiveHembra = (int) ($payload['id_hembra'] ?? $current['id_hembra']);
        if ($effectiveMacho ===$effectiveHembra) {
            return self::ERROR_INVALID_DATA;
        }

        if (array_key_exists('estado', $payload)) {
            if (!is_string($payload['estado']) || !in_array($payload['estado'], self::ALLOWED_STATES, true)) {
                return self::ERROR_INVALID_DATA;
            }

            if ($payload['estado'] !== 'activa') {
                if (!array_key_exists('fecha_fin', $payload) || $payload['fecha_fin'] === null || $payload['fecha_fin'] === '') {$payload['fecha_fin'] = date('Y-m-d');
                }
            }
        }

        if (array_key_exists('fecha_fin', $payload) && $payload['fecha_fin'] !== null &&$payload['fecha_fin'] !== '') {
            if (!is_string($payload['fecha_fin']) || preg_match('/^\d{4}-\d{2}-\d{2}$/',$payload['fecha_fin']) !== 1) {
                return self::ERROR_INVALID_DATA;
            }

            if (isset($current['fecha_formacion']) && $payload['fecha_fin'] < (string)$current['fecha_formacion']) {
                return self::ERROR_INVALID_DATA;
            }
        }

        return $payload;
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
        if (!is_int($value) && !(is_string($value) && preg_match('/^[0-9]+$/',$value) === 1)) {
            return null;
        }

        $integer = (int)$value;

        return $integer > 0 ?$integer : null;
    }

    /**
     * Traduce códigos SQLSTATE y mensajes de triggers de PostgreSQL a códigos de dominio.
     */
    private function mapWriteException(PDOException $exception): string {
        $message =$exception->getMessage();

        if (str_contains($message, 'Una pareja con cruces no se anula')) {
            return self::ERROR_MATINGS_ANNUL_CONFLICT;
        }

        if (str_contains($message, 'no puede ser padre o madre en la pareja de la que es cría')) {
            return self::ERROR_CONSANGUINITY;
        }

        return match ((string) $exception->getCode()) {
            '23505' => self::ERROR_CONFLICT,
            '23503' => self::ERROR_INVALID_REFERENCE,
            '23502', '23514', '22P02', '22007' => self::ERROR_INVALID_DATA,
            'P0001' => self::ERROR_CONFLICT,
            default => throw $exception,
        };
    }
}
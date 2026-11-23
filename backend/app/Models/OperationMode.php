<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use CanariApp\Backend\Helpers\AuditHelper;
use PDOException;
use RuntimeException;
use Throwable;

/**
 * Modelo de la tabla modo_operacion según el esquema v7.1 (SRS-RF028, DAT-003).
 *
 * Reglas aplicadas por la base de datos y el modelo:
 *  - Modo normal = no existe ninguna fila con fecha_desactivacion IS NULL.
 *  - Solo puede haber un modo especial ('mantenimiento' o 'emergencia') activo a la vez.
 *  - diagnostico y fecha_diagnostico se registran siempre juntos (ck_modo_diagnostico).
 *  - Una emergencia no puede cerrarse sin diagnostico ni acciones_recuperacion (ck_modo_emergencia).
 *  - Solo usuarios con rol 'administrador' pueden activar o cerrar modos.
 */
class OperationMode extends BaseModel {
    protected string $table = 'modo_operacion';
    protected string $primaryKey = 'id_modo';

    public const ALLOWED_MODES = ['mantenimiento', 'emergencia'];

    public const ERROR_INVALID_DATA = 'invalid_data';
    public const ERROR_ALREADY_ACTIVE = 'already_active';
    public const ERROR_NOT_FOUND = 'not_found';
    public const ERROR_ALREADY_CLOSED = 'already_closed';
    public const ERROR_EMERGENCY_INCOMPLETE = 'emergency_incomplete';
    public const ERROR_FORBIDDEN_ROLE = 'forbidden_role';

    /**
     * Devuelve el modo especial activo actualmente, o null si el sistema opera en modo normal.
     *
     * @return array<string, mixed>|null
     */
    public function findActive(): ?array {
        $sql = $this->detailedSelect()
            . ' WHERE m.fecha_desactivacion IS NULL'
            . ' LIMIT 1';

        return $this->fetch($sql);
    }

    /**
     * Busca un registro de modo de operación por su ID.
     *
     * @return array<string, mixed>|null
     */
    public function findDetailed(int $id): ?array {
        $sql = $this->detailedSelect()
            . ' WHERE m.id_modo = :id_modo'
            . ' LIMIT 1';

        return $this->fetch($sql, ['id_modo' => $id]);
    }

    /**
     * Lista el historial de modos de operación con filtros opcionales.
     *
     * @param array<string, mixed> $filters
     * @return array<int, array<string, mixed>>
     */
    public function findAllDetailed(array $filters = []): array {
        $conditions = [];
        $params = [];

        $modo = $filters['modo'] ?? null;
        if (is_string($modo) && in_array($modo, self::ALLOWED_MODES, true)) {
            $conditions[] = 'm.modo = :modo';
            $params['modo'] = $modo;
        }

        if (array_key_exists('activo', $filters) && $filters['activo'] !== null && $filters['activo'] !== '') {
            $isActive = filter_var($filters['activo'], FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE);
            if ($isActive === true) {
                $conditions[] = 'm.fecha_desactivacion IS NULL';
            } elseif ($isActive === false) {
                $conditions[] = 'm.fecha_desactivacion IS NOT NULL';
            }
        }

        $sql = $this->detailedSelect();

        if ($conditions !== []) {
            $sql .= ' WHERE ' . implode(' AND ', $conditions);
        }

        $sql .= ' ORDER BY m.fecha_activacion DESC, m.id_modo DESC';

        return $this->fetchAll($sql, $params);
    }

    /**
     * Activa un modo especial ('mantenimiento' o 'emergencia') si no hay otro activo.
     */
    public function activate(
        string $modo,
        int $adminUserId,
        ?string $diagnostico = null
    ): int|string {
        if (!in_array($modo, self::ALLOWED_MODES, true) || $adminUserId <= 0) {
            return self::ERROR_INVALID_DATA;
        }

        if ($this->findActive() !== null) {
            return self::ERROR_ALREADY_ACTIVE;
        }

        $cleanDiagnosis = is_string($diagnostico) && trim($diagnostico) !== ''
            ? trim($diagnostico)
            : null;

        try {
            $id = AuditHelper::withoutAutoAudit(function () use ($modo, $adminUserId, $cleanDiagnosis): int|string|null {
                if ($cleanDiagnosis !== null) {
                    $sql = 'INSERT INTO modo_operacion (
                                modo,
                                id_usuario,
                                diagnostico,
                                fecha_diagnostico
                            ) VALUES (
                                :modo,
                                :id_usuario,
                                :diagnostico,
                                CURRENT_TIMESTAMP
                            ) RETURNING id_modo';

                    return $this->normalizeInsertId($this->fetchColumn($sql, [
                        'modo'        => $modo,
                        'id_usuario'  => $adminUserId,
                        'diagnostico' => $cleanDiagnosis,
                    ]));
                }

                return $this->insert([
                    'modo'       => $modo,
                    'id_usuario' => $adminUserId,
                ]);
            });
        } catch (PDOException $exception) {
            return $this->mapWriteException($exception);
        }

        if ($id === null) {
            throw new RuntimeException('No se pudo obtener el ID del modo de operación activado.');
        }

        return $id;
    }

    /**
     * Registra o actualiza el diagnóstico (plazo objetivo de 4 horas en emergencia)
     * y opcionalmente las acciones de recuperación sobre un modo activo.
     *
     * @return array{previous: array<string, mixed>, updated: array<string, mixed>}|string
     */
    public function registerDiagnosis(
        int $idModo,
        string $diagnostico,
        ?string $accionesRecuperacion = null
    ): array|string {
        $cleanDiagnosis = trim($diagnostico);
        if ($idModo <= 0 || $cleanDiagnosis === '') {
            return self::ERROR_INVALID_DATA;
        }

        $cleanActions = is_string($accionesRecuperacion) && trim($accionesRecuperacion) !== ''
            ? trim($accionesRecuperacion)
            : null;

        try {
            $this->beginTransaction();

            $current = $this->fetch(
                'SELECT * FROM ' . $this->quoteIdentifier($this->table)
                . ' WHERE id_modo = :id_modo FOR UPDATE',
                ['id_modo' => $idModo]
            );

            if ($current === null) {
                $this->rollBack();

                return self::ERROR_NOT_FOUND;
            }

            if ($current['fecha_desactivacion'] !== null) {
                $this->rollBack();

                return self::ERROR_ALREADY_CLOSED;
            }

            $effectiveActions = $cleanActions ?? $current['acciones_recuperacion'];

            $this->execute(
                'UPDATE modo_operacion
                    SET diagnostico = :diagnostico,
                        fecha_diagnostico = CURRENT_TIMESTAMP,
                        acciones_recuperacion = :acciones_recuperacion
                  WHERE id_modo = :id_modo',
                [
                    'diagnostico'           => $cleanDiagnosis,
                    'acciones_recuperacion' => $effectiveActions,
                    'id_modo'               => $idModo,
                ]
            );

            $this->commit();
        } catch (PDOException $exception) {
            $this->rollBack();

            return $this->mapWriteException($exception);
        } catch (Throwable $exception) {
            $this->rollBack();
            throw $exception;
        }

        $updated = $this->findDetailed($idModo) ?? $current;

        return [
            'previous' => $current,
            'updated'  => $updated,
        ];
    }

    /**
     * Desactiva un modo especial y devuelve el sistema a modo normal.
     * Si el modo es 'emergencia', exige diagnostico y acciones_recuperacion (ck_modo_emergencia).
     *
     * @return array{previous: array<string, mixed>, updated: array<string, mixed>}|string
     */
    public function deactivate(
        int $idModo,
        int $adminUserId,
        ?string $diagnostico = null,
        ?string $accionesRecuperacion = null
    ): array|string {
        if ($idModo <= 0 || $adminUserId <= 0) {
            return self::ERROR_INVALID_DATA;
        }

        $cleanDiagnosis = is_string($diagnostico) && trim($diagnostico) !== ''
            ? trim($diagnostico)
            : null;
        $cleanActions = is_string($accionesRecuperacion) && trim($accionesRecuperacion) !== ''
            ? trim($accionesRecuperacion)
            : null;

        try {
            $this->beginTransaction();

            $current = $this->fetch(
                'SELECT * FROM ' . $this->quoteIdentifier($this->table)
                . ' WHERE id_modo = :id_modo FOR UPDATE',
                ['id_modo' => $idModo]
            );

            if ($current === null) {
                $this->rollBack();

                return self::ERROR_NOT_FOUND;
            }

            if ($current['fecha_desactivacion'] !== null) {
                $this->rollBack();

                return self::ERROR_ALREADY_CLOSED;
            }

            $effectiveDiagnosis = $cleanDiagnosis ?? $current['diagnostico'];
            $effectiveActions = $cleanActions ?? $current['acciones_recuperacion'];

            if (
                $current['modo'] === 'emergencia'
                && ($effectiveDiagnosis === null || trim((string) $effectiveDiagnosis) === ''
                    || $effectiveActions === null || trim((string) $effectiveActions) === '')
            ) {
                $this->rollBack();

                return self::ERROR_EMERGENCY_INCOMPLETE;
            }

            if ($cleanDiagnosis !== null) {
                $this->execute(
                    'UPDATE modo_operacion
                        SET fecha_desactivacion = CURRENT_TIMESTAMP,
                            id_usuario_cierre = :id_usuario_cierre,
                            diagnostico = :diagnostico,
                            fecha_diagnostico = CURRENT_TIMESTAMP,
                            acciones_recuperacion = :acciones_recuperacion
                      WHERE id_modo = :id_modo',
                    [
                        'id_usuario_cierre'     => $adminUserId,
                        'diagnostico'           => $cleanDiagnosis,
                        'acciones_recuperacion' => $effectiveActions,
                        'id_modo'               => $idModo,
                    ]
                );
            } else {
                $this->execute(
                    'UPDATE modo_operacion
                        SET fecha_desactivacion = CURRENT_TIMESTAMP,
                            id_usuario_cierre = :id_usuario_cierre,
                            acciones_recuperacion = :acciones_recuperacion
                      WHERE id_modo = :id_modo',
                    [
                        'id_usuario_cierre'     => $adminUserId,
                        'acciones_recuperacion' => $effectiveActions,
                        'id_modo'               => $idModo,
                    ]
                );
            }

            $this->commit();
        } catch (PDOException $exception) {
            $this->rollBack();

            return $this->mapWriteException($exception);
        } catch (Throwable $exception) {
            $this->rollBack();
            throw $exception;
        }

        $updated = $this->findDetailed($idModo) ?? $current;

        return [
            'previous' => $current,
            'updated'  => $updated,
        ];
    }

    /**
     * SELECT base con los datos del modo de operación y los administradores responsables.
     */
    private function detailedSelect(): string {
        return 'SELECT m.id_modo,
                       m.modo,
                       m.fecha_activacion,
                       m.fecha_desactivacion,
                       (m.fecha_desactivacion IS NULL) AS activo,
                       m.id_usuario,
                       ua.nombre AS activado_por_nombre,
                       m.id_usuario_cierre,
                       uc.nombre AS cerrado_por_nombre,
                       m.diagnostico,
                       m.fecha_diagnostico,
                       m.acciones_recuperacion,
                       CASE
                           WHEN m.modo = \'emergencia\' THEN (m.fecha_activacion + INTERVAL \'4 hours\')
                           ELSE NULL
                       END AS plazo_diagnostico
                  FROM ' . $this->quoteIdentifier($this->table) . ' m
                  INNER JOIN usuario ua ON m.id_usuario = ua.id_usuario
                  LEFT JOIN usuario uc ON m.id_usuario_cierre = uc.id_usuario';
    }

    /**
     * Traduce errores de PostgreSQL a códigos de dominio.
     */
    private function mapWriteException(PDOException $exception): string {
        $message = $exception->getMessage();

        if (str_contains($message, 'debe tener el rol administrador')) {
            return self::ERROR_FORBIDDEN_ROLE;
        }

        return match ((string) $exception->getCode()) {
            '23505' => self::ERROR_ALREADY_ACTIVE,
            '23502', '23514', '22P02', '22007' => self::ERROR_INVALID_DATA,
            default => throw $exception,
        };
    }
}
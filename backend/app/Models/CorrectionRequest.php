<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use CanariApp\Backend\Helpers\AuditHelper;
use PDOException;
use RuntimeException;
use Throwable;

/**
 * Modelo de la tabla solicitud_correccion según el esquema v7.1 (SRS-RF033).
 *
 * Reglas aplicadas por la base de datos y el modelo:
 *  - Solo el dueño del ejemplar puede solicitar su corrección (fk_solicitud_canario).
 *  - Solo se admite dato_a_corregir en ('sexo', 'variedad').
 *  - Solo puede existir una solicitud en estado 'pendiente' por ejemplar (uq_solicitud_pendiente).
 *  - El cierre ('aprobada', 'rechazada', 'cancelada') fija fecha_cierre (ck_solicitud_cierre).
 */
class CorrectionRequest extends BaseModel {
    protected string $table = 'solicitud_correccion';
    protected string $primaryKey = 'id_solicitud';

    public const ALLOWED_FIELDS = ['sexo', 'variedad'];
    public const STATES = ['pendiente', 'aprobada', 'rechazada', 'cancelada'];
    public const RESOLUTION_STATES = ['aprobada', 'rechazada'];

    public const ERROR_INVALID_DATA = 'invalid_data';
    public const ERROR_NOT_FOUND = 'not_found';
    public const ERROR_FORBIDDEN_CANARY = 'forbidden_canary';
    public const ERROR_CONFLICT_PENDING = 'conflict_pending';
    public const ERROR_INVALID_STATE = 'invalid_state';

    /**
     * Busca una solicitud por su ID con datos del ejemplar y del criador.
     *
     * @return array<string, mixed>|null
     */
    public function findDetailed(int $id): ?array {
        $sql = $this->detailedSelect()
            . ' WHERE sc.id_solicitud = :id_solicitud'
            . ' LIMIT 1';

        return $this->fetch($sql, ['id_solicitud' => $id]);
    }

    /**
     * Lista solicitudes con filtros opcionales. Si $idCriador no es null,
     * filtra únicamente las del criador indicado.
     *
     * @param array<string, mixed> $filters
     * @return array<int, array<string, mixed>>
     */
    public function findAllDetailed(array $filters = [], ?int $idCriador = null): array {
        $conditions = [];
        $params = [];

        if ($idCriador !== null) {
            $conditions[] = 'sc.id_criador = :id_criador';
            $params['id_criador'] = $idCriador;
        } elseif (isset($filters['id_criador']) && $this->positiveInt($filters['id_criador']) !== null) {
            $conditions[] = 'sc.id_criador = :id_criador';
            $params['id_criador'] = (int) $filters['id_criador'];
        }

        $estado = $filters['estado'] ?? null;
        if (is_string($estado) && in_array($estado, self::STATES, true)) {
            $conditions[] = 'sc.estado = :estado';
            $params['estado'] = $estado;
        }

        $dato = $filters['dato_a_corregir'] ?? null;
        if (is_string($dato) && in_array($dato, self::ALLOWED_FIELDS, true)) {
            $conditions[] = 'sc.dato_a_corregir = :dato_a_corregir';
            $params['dato_a_corregir'] = $dato;
        }

        if (isset($filters['id_canario']) && $this->positiveInt($filters['id_canario']) !== null) {
            $conditions[] = 'sc.id_canario = :id_canario';
            $params['id_canario'] = (int) $filters['id_canario'];
        }

        $sql = $this->detailedSelect();

        if ($conditions !== []) {
            $sql .= ' WHERE ' . implode(' AND ', $conditions);
        }

        $sql .= ' ORDER BY sc.fecha_solicitud DESC, sc.id_solicitud DESC';

        return $this->fetchAll($sql, $params);
    }

    /**
     * Crea una solicitud de corrección en estado 'pendiente' para un ejemplar
     * perteneciente al criador autenticado.
     */
    public function createForBreeder(
        int $idCanario,
        string $datoACorregir,
        string $motivo,
        int $idCriador
    ): int|string {
        $cleanReason = trim($motivo);
        if (
            $idCanario <= 0
            || !in_array($datoACorregir, self::ALLOWED_FIELDS, true)
            || $cleanReason === ''
        ) {
            return self::ERROR_INVALID_DATA;
        }

        $canary = $this->fetch(
            'SELECT id_canario, id_criador FROM canario WHERE id_canario = :id_canario LIMIT 1',
            ['id_canario' => $idCanario]
        );

        if ($canary === null) {
            return self::ERROR_NOT_FOUND;
        }

        if ((int) $canary['id_criador'] !== $idCriador) {
            return self::ERROR_FORBIDDEN_CANARY;
        }

        $hasPending = $this->existsBy([
            'id_canario' => $idCanario,
            'estado'     => 'pendiente',
        ]);

        if ($hasPending) {
            return self::ERROR_CONFLICT_PENDING;
        }

        try {
            $id = AuditHelper::withoutAutoAudit(
                fn (): int|string|null => $this->insert([
                    'id_canario'      => $idCanario,
                    'id_criador'      => $idCriador,
                    'dato_a_corregir' => $datoACorregir,
                    'motivo'          => $cleanReason,
                    'estado'          => 'pendiente',
                    'fecha_cierre'    => null,
                ])
            );
        } catch (PDOException $exception) {
            return $this->mapWriteException($exception);
        }

        if ($id === null) {
            throw new RuntimeException('No se pudo obtener el ID de la solicitud de corrección.');
        }

        return $id;
    }

    /**
     * Cancela una solicitud pendiente del criador autenticado.
     *
     * @return array{previous: array<string, mixed>, updated: array<string, mixed>}|string
     */
    public function cancelByBreeder(int $idSolicitud, int $idCriador): array|string {
        try {
            $this->beginTransaction();

            $current = $this->fetch(
                'SELECT * FROM ' . $this->quoteIdentifier($this->table)
                . ' WHERE id_solicitud = :id_solicitud FOR UPDATE',
                ['id_solicitud' => $idSolicitud]
            );

            if ($current === null) {
                $this->rollBack();

                return self::ERROR_NOT_FOUND;
            }

            if ((int) $current['id_criador'] !== $idCriador) {
                $this->rollBack();

                return self::ERROR_FORBIDDEN_CANARY;
            }

            if ($current['estado'] !== 'pendiente') {
                $this->rollBack();

                return self::ERROR_INVALID_STATE;
            }

            $this->execute(
                "UPDATE solicitud_correccion
                    SET estado = 'cancelada',
                        fecha_cierre = CURRENT_TIMESTAMP
                  WHERE id_solicitud = :id_solicitud",
                ['id_solicitud' => $idSolicitud]
            );

            $this->commit();
        } catch (PDOException $exception) {
            $this->rollBack();

            return $this->mapWriteException($exception);
        } catch (Throwable $exception) {
            $this->rollBack();
            throw $exception;
        }

        $updated = $this->findDetailed($idSolicitud) ?? $current;

        return [
            'previous' => $current,
            'updated'  => $updated,
        ];
    }

    /**
     * Resuelve ('aprobada' o 'rechazada') una solicitud pendiente por el administrador.
     *
     * @return array{previous: array<string, mixed>, updated: array<string, mixed>}|string
     */
    public function resolveByAdmin(int $idSolicitud, string $nuevoEstado): array|string {
        if (!in_array($nuevoEstado, self::RESOLUTION_STATES, true)) {
            return self::ERROR_INVALID_DATA;
        }

        try {
            $this->beginTransaction();

            $current = $this->fetch(
                'SELECT * FROM ' . $this->quoteIdentifier($this->table)
                . ' WHERE id_solicitud = :id_solicitud FOR UPDATE',
                ['id_solicitud' => $idSolicitud]
            );

            if ($current === null) {
                $this->rollBack();

                return self::ERROR_NOT_FOUND;
            }

            if ($current['estado'] !== 'pendiente') {
                $this->rollBack();

                return self::ERROR_INVALID_STATE;
            }

            $this->execute(
                'UPDATE solicitud_correccion
                    SET estado = :estado,
                        fecha_cierre = CURRENT_TIMESTAMP
                  WHERE id_solicitud = :id_solicitud',
                [
                    'estado'       => $nuevoEstado,
                    'id_solicitud' => $idSolicitud,
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

        $updated = $this->findDetailed($idSolicitud) ?? $current;

        return [
            'previous' => $current,
            'updated'  => $updated,
        ];
    }

    /**
     * SELECT base uniendo ejemplar, club, variedad actual y criador solicitante.
     */
    private function detailedSelect(): string {
        return 'SELECT sc.id_solicitud,
                       sc.id_canario,
                       c.anillo,
                       cl.sigla AS club_sigla,
                       c.numero_socio,
                       c.temporada,
                       c.sexo AS sexo_actual,
                       c.id_variedad AS id_variedad_actual,
                       v.nombre AS variedad_actual_nombre,
                       sc.id_criador,
                       u.nombre AS criador_nombre,
                       sc.dato_a_corregir,
                       sc.motivo,
                       sc.estado,
                       sc.fecha_solicitud,
                       sc.fecha_cierre
                  FROM ' . $this->quoteIdentifier($this->table) . ' sc
                  INNER JOIN canario c ON sc.id_canario = c.id_canario
                  INNER JOIN club cl ON c.id_club = cl.id_club
                  LEFT JOIN variedad v ON c.id_variedad = v.id_variedad
                  INNER JOIN criador cr ON sc.id_criador = cr.id_criador
                  INNER JOIN usuario u ON cr.id_usuario = u.id_usuario';
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
     * Traduce errores de PostgreSQL a códigos de dominio.
     */
    private function mapWriteException(PDOException $exception): string {
        return match ((string) $exception->getCode()) {
            '23505' => self::ERROR_CONFLICT_PENDING,
            '23503' => self::ERROR_FORBIDDEN_CANARY,
            '23502', '23514', '22P02', '22007' => self::ERROR_INVALID_DATA,
            default => throw $exception,
        };
    }
}
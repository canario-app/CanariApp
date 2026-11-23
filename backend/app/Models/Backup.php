<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use CanariApp\Backend\Helpers\AuditHelper;
use PDOException;
use RuntimeException;
use Throwable;

/**
 * Modelo de la tabla respaldo según el esquema v7.1 (DAT-003).
 *
 * Reglas aplicadas por la base de datos y el modelo:
 *  - Solo un usuario con rol 'administrador' (o NULL si es automático) puede
 *    registrar respaldos (trg_respaldo_rol).
 *  - El nombre de archivo es único y no vacío (uq / CHECK btrim(archivo) <> '').
 *  - Se conservan únicamente los 7 respaldos más recientes; al registrar uno
 *    nuevo se rotan y eliminan los excedentes más antiguos (DAT-003).
 *  - Política automática: al menos 1 respaldo cada 2 días (48 horas).
 */
class Backup extends BaseModel {
    protected string $table = 'respaldo';
    protected string $primaryKey = 'id_respaldo';

    public const MAX_RETENTION = 7;
    public const AUTO_BACKUP_INTERVAL_SECONDS = 172800; // 48 horas (2 días)

    public const ERROR_INVALID_DATA = 'invalid_data';
    public const ERROR_DUPLICATE_FILE = 'duplicate_file';
    public const ERROR_FORBIDDEN_ROLE = 'forbidden_role';

    /**
     * Busca un respaldo por su clave primaria junto con el administrador responsable.
     *
     * @return array<string, mixed>|null
     */
    public function findDetailed(int $id): ?array {
        $sql = $this->detailedSelect()
            . ' WHERE r.id_respaldo = :id_respaldo'
            . ' LIMIT 1';

        return $this->fetch($sql, ['id_respaldo' => $id]);
    }

    /**
     * Lista los respaldos ordenados del más reciente al más antiguo.
     *
     * @return array<int, array<string, mixed>>
     */
    public function findAllDetailed(): array {
        $sql = $this->detailedSelect()
            . ' ORDER BY r.fecha_hora DESC, r.id_respaldo DESC';

        return $this->fetchAll($sql);
    }

    /**
     * Indica si ya transcurrieron al menos 48 horas desde el último respaldo registrado
     * (o si no existe ningún respaldo aún).
     */
    public function isAutoBackupDue(int $intervalSeconds = self::AUTO_BACKUP_INTERVAL_SECONDS): bool {
        $row = $this->fetch(
            'SELECT EXTRACT(EPOCH FROM MAX(fecha_hora))::BIGINT AS last_epoch
               FROM ' . $this->quoteIdentifier($this->table)
        );

        $lastEpoch = $row['last_epoch'] ?? null;
        if ($lastEpoch === null || !is_numeric($lastEpoch)) {
            return true;
        }

        return (time() - (int) $lastEpoch) >= $intervalSeconds;
    }

    /**
     * Registra un respaldo y ejecuta la rotación para conservar solo los 7 más recientes.
     *
     * @return array{id_respaldo: int, rotated_files: array<int, string>}|string
     */
    public function registerAndRotate(string $archivo, ?int $adminUserId): array|string {
        $cleanFile = trim($archivo);
        if ($cleanFile === '' || mb_strlen($cleanFile) > 255) {
            return self::ERROR_INVALID_DATA;
        }

        if ($adminUserId !== null && $adminUserId <= 0) {
            return self::ERROR_INVALID_DATA;
        }

        $rotatedFiles = [];

        try {
            $this->beginTransaction();

            $insertedId = AuditHelper::withoutAutoAudit(
                fn (): int|string|null => $this->insert([
                    'archivo'    => $cleanFile,
                    'id_usuario' => $adminUserId,
                ])
            );

            if ($insertedId === null) {
                $this->rollBack();
                throw new RuntimeException('No se pudo obtener el ID del respaldo registrado.');
            }

            $expiredRows = $this->fetchAll(
                sprintf(
                    'SELECT id_respaldo, archivo
                       FROM %s
                      ORDER BY fecha_hora DESC, id_respaldo DESC
                      OFFSET %d',
                    $this->quoteIdentifier($this->table),
                    self::MAX_RETENTION
                )
            );

            if ($expiredRows !== []) {
                $expiredIds = [];
                foreach ($expiredRows as $row) {
                    $expiredIds[] = (int) $row['id_respaldo'];
                    $rotatedFiles[] = (string) $row['archivo'];
                }

                $this->deleteBy(['id_respaldo' => $expiredIds]);
            }

            $this->commit();
        } catch (PDOException $exception) {
            $this->rollBack();

            return $this->mapWriteException($exception);
        } catch (Throwable $exception) {
            $this->rollBack();
            throw $exception;
        }

        return [
            'id_respaldo'   => (int) $insertedId,
            'rotated_files' => $rotatedFiles,
        ];
    }

    /**
     * SELECT base uniendo los datos del administrador que generó el respaldo.
     */
    private function detailedSelect(): string {
        return 'SELECT r.id_respaldo,
                       r.fecha_hora,
                       r.archivo,
                       r.id_usuario,
                       u.nombre AS usuario_nombre,
                       u.correo AS usuario_correo
                  FROM ' . $this->quoteIdentifier($this->table) . ' r
                  LEFT JOIN usuario u ON r.id_usuario = u.id_usuario';
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
            '23505' => self::ERROR_DUPLICATE_FILE,
            '23502', '23514', '22P02', '22007' => self::ERROR_INVALID_DATA,
            default => throw $exception,
        };
    }
}
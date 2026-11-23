<?php

declare(strict_types=1);

namespace CanariApp\Backend\Helpers;

use CanariApp\Backend\Config\Db;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use PDO;

/**
 * Helper centralizado para registrar eventos en la tabla auditoria (SEG-003).
 *
 * La tabla auditoria solo permite INSERT y SELECT; nunca se almacenan
 * contraseñas ni secretos en valor_anterior o valor_nuevo.
 */
final class AuditHelper {
    /** Campos sensibles que jamás deben persistirse en auditoría (SEG-003). */
    private const SENSITIVE_KEYS = [
        'password',
        'password_hash',
        'new_password',
        'current_password',
        'jwt_secret',
    ];

    private static bool $autoAuditEnabled = true;

    /**
     * Inserta un registro en la tabla auditoria.
     */
    public static function log(
        string $action,
        ?string $entity = null,
        ?int $recordId = null,
        mixed $previousValue = null,
        mixed $newValue = null,
        ?string $reason = null,
        ?int $userId = null,
        ?int $requestingBreederId = null,
        ?int $requestId = null,
        ?PDO $db = null
    ): void {
        $cleanAction = trim($action);
        if ($cleanAction === '') {
            return;
        }

        $resolvedUserId = $userId;
        if ($resolvedUserId === null) {
            $authId = AuthMiddleware::userId();
            if ($authId !== null && is_numeric($authId)) {
                $resolvedUserId = (int) $authId;
            }
        }

        $connection = $db ?? Db::getConnection();

        $sql = 'INSERT INTO auditoria (
                    id_usuario,
                    accion,
                    entidad,
                    id_registro,
                    valor_anterior,
                    valor_nuevo,
                    motivo,
                    id_criador_solicitante,
                    id_solicitud
                ) VALUES (
                    :id_usuario,
                    :accion,
                    :entidad,
                    :id_registro,
                    :valor_anterior,
                    :valor_nuevo,
                    :motivo,
                    :id_criador_solicitante,
                    :id_solicitud
                )';

        $stmt = $connection->prepare($sql);
        $stmt->bindValue(':id_usuario', $resolvedUserId, $resolvedUserId === null ? PDO::PARAM_NULL : PDO::PARAM_INT);
        $stmt->bindValue(':accion', mb_substr($cleanAction, 0, 50), PDO::PARAM_STR);
        $stmt->bindValue(':entidad', $entity !== null ? mb_substr(trim($entity), 0, 50) : null, $entity === null ? PDO::PARAM_NULL : PDO::PARAM_STR);
        $stmt->bindValue(':id_registro', $recordId, $recordId === null ? PDO::PARAM_NULL : PDO::PARAM_INT);

        $serializedPrev = self::serializeValue($previousValue);
        $serializedNew = self::serializeValue($newValue);
        $cleanReason = $reason !== null && trim($reason) !== '' ? trim($reason) : null;

        $stmt->bindValue(':valor_anterior', $serializedPrev, $serializedPrev === null ? PDO::PARAM_NULL : PDO::PARAM_STR);
        $stmt->bindValue(':valor_nuevo', $serializedNew, $serializedNew === null ? PDO::PARAM_NULL : PDO::PARAM_STR);
        $stmt->bindValue(':motivo', $cleanReason, $cleanReason === null ? PDO::PARAM_NULL : PDO::PARAM_STR);
        $stmt->bindValue(
            ':id_criador_solicitante',
            $requestingBreederId,
            $requestingBreederId === null ? PDO::PARAM_NULL : PDO::PARAM_INT
        );
        $stmt->bindValue(':id_solicitud', $requestId, $requestId === null ? PDO::PARAM_NULL : PDO::PARAM_INT);

        $stmt->execute();
    }

    /**
     * Ejecuta una operación desactivando temporalmente la auditoría automática
     * de BaseModel cuando el controlador registra un evento enriquecido propio.
     */
    public static function withoutAutoAudit(callable $callback): mixed {
        $previousState = self::$autoAuditEnabled;
        self::$autoAuditEnabled = false;

        try {
            return $callback();
        } finally {
            self::$autoAuditEnabled = $previousState;
        }
    }

    /**
     * Indica si BaseModel debe auditar automáticamente escrituras.
     */
    public static function isAutoAuditEnabled(): bool {
        return self::$autoAuditEnabled;
    }

    /**
     * Serializa valores a texto/JSON eliminando claves sensibles.
     */
    private static function serializeValue(mixed $value): ?string {
        if ($value === null) {
            return null;
        }

        if (is_array($value)) {
            $sanitized = self::sanitizeArray($value);
            if ($sanitized === []) {
                return null;
            }

            $encoded = json_encode($sanitized, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

            return $encoded === false ? null : $encoded;
        }

        if (is_bool($value)) {
            return $value ? 'true' : 'false';
        }

        if (is_scalar($value)) {
            $text = trim((string) $value);

            return $text === '' ? null : $text;
        }

        return null;
    }

    /**
     * Elimina recursivamente campos de contraseñas o secretos.
     *
     * @param array<mixed, mixed> $data
     * @return array<mixed, mixed>
     */
    private static function sanitizeArray(array $data): array {
        $clean = [];

        foreach ($data as $key => $value) {
            if (is_string($key) && in_array(mb_strtolower($key), self::SENSITIVE_KEYS, true)) {
                continue;
            }

            $clean[$key] = is_array($value) ? self::sanitizeArray($value) : $value;
        }

        return $clean;
    }
}
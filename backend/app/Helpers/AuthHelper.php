<?php

declare(strict_types=1);

namespace CanariApp\Backend\Helpers;

use CanariApp\Backend\Config\App;
use CanariApp\Backend\Config\Db;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Exception;
use RuntimeException;

class AuthHelper {
    /**
     * Obtiene la clave secreta JWT verificando que esté configurada y no vacía.
     */
    private static function getJwtSecret(): string {
        $problem = App::jwtSecretProblem();
        if ($problem !== null) {
            throw new RuntimeException($problem);
        }

        return (string) App::get('jwt.secret');
    }

    /**
     * Obtiene la duración de la sesión en segundos desde la configuración o JWT_EXPIRATION.
     */
    public static function getTokenExpiration(): int {
        $configured = App::get('jwt.expiration')
            ?? $_ENV['JWT_EXPIRATION']
            ?? getenv('JWT_EXPIRATION');

        if (is_numeric($configured) && (int) $configured > 0) {
            return (int) $configured;
        }

        return 7200;
    }

    /**
     * Genera un token JWT incluyendo el ID, correo y rol del usuario.
     * $sessionId (claim jti) identifica la sesión: se conserva al renovar el token.
     */
    public static function generateToken(int|string $userId, string $correo, string $rol, ?string $sessionId = null): string {
        $secret = self::getJwtSecret();
        $issuedAt = time();
        $expirationTime = $issuedAt + self::getTokenExpiration();

        $payload = [
            'jti'    => $sessionId !== null && preg_match('/^[a-f0-9]{32}$/', $sessionId) === 1
                ? $sessionId
                : bin2hex(random_bytes(16)),
            'iat'    => $issuedAt,
            'exp'    => $expirationTime,
            'sub'    => $userId,
            'correo' => $correo,
            'rol'    => $rol,
        ];

        return JWT::encode($payload, $secret, 'HS256');
    }

    /**
     * Renueva un token válido (SEG-004: cierre tras 30 minutos SIN ACTIVIDAD).
     * El nuevo token vence JWT_EXPIRATION segundos después de este uso y conserva
     * la misma sesión (jti), de modo que el cierre de sesión revoca todos sus tokens.
     */
    public static function renewToken(object $payload): ?string {
        if (!isset($payload->sub, $payload->correo, $payload->rol)) {
            return null;
        }

        return self::generateToken(
            $payload->sub,
            (string) $payload->correo,
            (string) $payload->rol,
            isset($payload->jti) ? (string) $payload->jti : null
        );
    }

    /**
     * Valida un token JWT. Retorna el payload si es válido, o null si fue alterado, expiró o cerró sesión.
     */
    public static function validateToken(string $token): ?object {
        try {
            $secret = self::getJwtSecret();
            $decoded = JWT::decode($token, new Key($secret, 'HS256'));

            $sessionId = isset($decoded->jti) ? (string) $decoded->jti : null;
            if (self::isTokenRevoked($token, $sessionId)) {
                return null;
            }

            return $decoded;
        } catch (Exception $e) {
            return null;
        }
    }

    /**
     * Registra el cierre de sesión en auditoria. Guarda el hash SHA-256 de la sesión (jti),
     * que invalida el token actual y todos los renovados de la misma sesión; sin jti,
     * guarda el hash del token como antes.
     */
    public static function revokeToken(string $token, int $userId, ?string $sessionId = null): void {
        AuditHelper::log(
            action: 'logout',
            entity: 'sesion',
            recordId: $userId,
            newValue: $sessionId !== null && $sessionId !== ''
                ? self::sessionHash($sessionId)
                : hash('sha256', $token),
            reason: 'Cierre de sesión de usuario',
            userId: $userId
        );
    }

    /**
     * Comprueba en auditoria si el token, o su sesión (jti), fue revocado mediante cierre de sesión.
     */
    public static function isTokenRevoked(string $token, ?string $sessionId = null): bool {
        $db = Db::getConnection();

        $stmt = $db->prepare(
            "SELECT 1 FROM auditoria
             WHERE accion = 'logout'
               AND entidad = 'sesion'
               AND valor_nuevo IN (:token_hash, :session_hash)
             LIMIT 1"
        );
        $stmt->execute([
            'token_hash'   => hash('sha256', $token),
            'session_hash' => $sessionId !== null && $sessionId !== '' ? self::sessionHash($sessionId) : hash('sha256', $token),
        ]);

        return $stmt->fetchColumn() !== false;
    }

    private static function sessionHash(string $sessionId): string {
        return hash('sha256', 'jti:' . $sessionId);
    }
}
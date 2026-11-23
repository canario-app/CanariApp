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
        $secret = App::get('jwt.secret')
            ?? $_ENV['JWT_SECRET']
            ?? getenv('JWT_SECRET');

        if (!is_string($secret) || trim($secret) === '') {
            throw new RuntimeException(
                'Error de configuración del servidor: falta definir JWT_SECRET en el entorno.'
            );
        }

        return $secret;
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
     */
    public static function generateToken(int|string $userId, string $correo, string $rol): string {
        $secret = self::getJwtSecret();
        $issuedAt = time();
        $expirationTime = $issuedAt + self::getTokenExpiration();

        $payload = [
            'jti'    => bin2hex(random_bytes(16)),
            'iat'    => $issuedAt,
            'exp'    => $expirationTime,
            'sub'    => $userId,
            'correo' => $correo,
            'rol'    => $rol,
        ];

        return JWT::encode($payload, $secret, 'HS256');
    }

    /**
     * Valida un token JWT. Retorna el payload si es válido, o null si fue alterado, expiró o cerró sesión.
     */
    public static function validateToken(string $token): ?object {
        try {
            $secret = self::getJwtSecret();
            $decoded = JWT::decode($token, new Key($secret, 'HS256'));

            if (self::isTokenRevoked($token)) {
                return null;
            }

            return $decoded;
        } catch (Exception $e) {
            return null;
        }
    }

    /**
     * Registra el cierre de sesión en auditoria invalidando el hash SHA-256 del token actual.
     */
    public static function revokeToken(string $token, int $userId): void {
        AuditHelper::log(
            action: 'logout',
            entity: 'sesion',
            recordId: $userId,
            newValue: hash('sha256', $token),
            reason: 'Cierre de sesión de usuario',
            userId: $userId
        );
    }

    /**
     * Comprueba en auditoria si el token fue revocado mediante cierre de sesión.
     */
    public static function isTokenRevoked(string $token): bool {
        $db = Db::getConnection();

        $stmt = $db->prepare(
            "SELECT 1 FROM auditoria
             WHERE accion = 'logout'
               AND entidad = 'sesion'
               AND valor_nuevo = :token_hash
             LIMIT 1"
        );
        $stmt->execute([
            'token_hash' => hash('sha256', $token),
        ]);

        return $stmt->fetchColumn() !== false;
    }
}
<?php

declare(strict_types=1);

namespace CanariApp\Backend\Helpers;

use CanariApp\Backend\Config\App;
use CanariApp\Backend\Config\Db;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Exception;

class AuthHelper {
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
        $secret = App::get('jwt.secret');
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
            $secret = App::get('jwt.secret');
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
        $db = Db::getConnection();

        $stmt = $db->prepare(
            "INSERT INTO auditoria (id_usuario, accion, entidad, id_registro, valor_nuevo, motivo)
             VALUES (:id_usuario, 'logout', 'sesion', :id_registro, :token_hash, 'Cierre de sesión de usuario')"
        );
        $stmt->execute([
            'id_usuario'  => $userId,
            'id_registro' => $userId,
            'token_hash'  => hash('sha256', $token),
        ]);
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
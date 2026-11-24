<?php

declare(strict_types=1);

namespace CanariApp\Backend\Helpers;

use RuntimeException;

/**
 * Cifrado de los archivos de respaldo (SRS DAT-003: respaldos cifrados).
 *
 * Formato del archivo .sql.enc:
 *   MAGIC (15 bytes) | sal (16) | IV (12) | etiqueta GCM (16) | texto cifrado
 *
 * - Algoritmo AES-256-GCM (cifra y además detecta si el archivo fue alterado).
 * - La clave se deriva de BACKUP_ENCRYPTION_KEY con PBKDF2-SHA256 y una sal aleatoria
 *   por archivo, así dos respaldos nunca usan la misma clave efectiva.
 * - Todo ocurre en memoria: el SQL en texto plano nunca se escribe en disco.
 */
final class BackupCrypto {
    public const MIN_KEY_LENGTH = 32;
    public const EXTENSION = '.sql.enc';

    private const MAGIC = "CANARIAPP-ENC1\n";
    private const CIPHER = 'aes-256-gcm';
    private const SALT_LENGTH = 16;
    private const IV_LENGTH = 12;
    private const TAG_LENGTH = 16;
    private const PBKDF2_ITERATIONS = 200000;

    private function __construct() {}

    /**
     * Lee BACKUP_ENCRYPTION_KEY del entorno y exige al menos 32 caracteres.
     */
    public static function secretFromEnvironment(): string {
        $value = $_ENV['BACKUP_ENCRYPTION_KEY'] ?? getenv('BACKUP_ENCRYPTION_KEY');
        $secret = is_string($value) ? trim($value) : '';

        if (strlen($secret) < self::MIN_KEY_LENGTH) {
            throw new RuntimeException(sprintf(
                'BACKUP_ENCRYPTION_KEY no está definida o tiene menos de %d caracteres; no se generan respaldos sin cifrar.',
                self::MIN_KEY_LENGTH
            ));
        }

        return $secret;
    }

    public static function encrypt(string $plain, string $secret): string {
        if (!function_exists('openssl_encrypt')) {
            throw new RuntimeException('La extensión openssl de PHP no está disponible.');
        }

        $salt = random_bytes(self::SALT_LENGTH);
        $iv = random_bytes(self::IV_LENGTH);
        $tag = '';

        $cipherText = openssl_encrypt(
            $plain,
            self::CIPHER,
            self::deriveKey($secret, $salt),
            OPENSSL_RAW_DATA,
            $iv,
            $tag,
            self::MAGIC,
            self::TAG_LENGTH
        );

        if ($cipherText === false || strlen($tag) !== self::TAG_LENGTH) {
            throw new RuntimeException('No se pudo cifrar el respaldo.');
        }

        return self::MAGIC . $salt . $iv . $tag . $cipherText;
    }

    public static function decrypt(string $data, string $secret): string {
        if (!self::isEncrypted($data)) {
            throw new RuntimeException('El archivo no tiene el formato de respaldo cifrado de CanariApp.');
        }

        $offset = strlen(self::MAGIC);
        $salt = substr($data, $offset, self::SALT_LENGTH);
        $offset += self::SALT_LENGTH;
        $iv = substr($data, $offset, self::IV_LENGTH);
        $offset += self::IV_LENGTH;
        $tag = substr($data, $offset, self::TAG_LENGTH);
        $offset += self::TAG_LENGTH;
        $cipherText = substr($data, $offset);

        if (strlen($tag) !== self::TAG_LENGTH) {
            throw new RuntimeException('El archivo de respaldo cifrado está incompleto.');
        }

        $plain = openssl_decrypt(
            $cipherText,
            self::CIPHER,
            self::deriveKey($secret, $salt),
            OPENSSL_RAW_DATA,
            $iv,
            $tag,
            self::MAGIC
        );

        if ($plain === false) {
            throw new RuntimeException(
                'No se pudo descifrar el respaldo: la clave BACKUP_ENCRYPTION_KEY no coincide o el archivo fue alterado.'
            );
        }

        return $plain;
    }

    public static function isEncrypted(string $data): bool {
        return str_starts_with($data, self::MAGIC);
    }

    private static function deriveKey(string $secret, string $salt): string {
        return hash_pbkdf2('sha256', $secret, $salt, self::PBKDF2_ITERATIONS, 32, true);
    }
}

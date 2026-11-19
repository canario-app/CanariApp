<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use CanariApp\Backend\Config\Db;

class User extends BaseModel {
    protected string $table = 'usuario';
    protected string $primaryKey = 'id_usuario';

    /**
     * Busca un usuario por su correo electrónico.
     */
    public function findByCorreo(string $correo): ?array {
        $sql = "SELECT * FROM {$this->table} WHERE LOWER(correo) = :correo LIMIT 1";
        return $this->fetch($sql, ['correo' => $this->normalizeCorreo($correo)]);
    }

    /**
     * Verifica si un correo ya está registrado (opcionalmente excluyendo un ID de usuario).
     */
    public function existsByEmail(string $email, ?int $excludeUserId = null): bool {
        $normalized = $this->normalizeCorreo($email);

        if ($excludeUserId !== null) {
            $sql = "SELECT 1 FROM {$this->table}
                    WHERE LOWER(correo) = :correo AND id_usuario <> :id_usuario
                    LIMIT 1";

            return $this->fetch($sql, [
                'correo'     => $normalized,
                'id_usuario' => $excludeUserId,
            ]) !== null;
        }

        $sql = "SELECT 1 FROM {$this->table} WHERE LOWER(correo) = :correo LIMIT 1";

        return $this->fetch($sql, ['correo' => $normalized]) !== null;
    }

    /**
     * Crea un nuevo usuario encriptando la contraseña en password_hash.
     */
    public function create(array $data): int|string|null {
        if (isset($data['correo'])) {
            $data['correo'] = $this->normalizeCorreo((string) $data['correo']);
        }

        if (isset($data['password'])) {
            $data['password_hash'] = password_hash((string) $data['password'], PASSWORD_DEFAULT);
            unset($data['password']);
        }

        // Asegura cumplir el CHECK (rol IN ('criador','administrador'))
        $data['rol'] ??= 'criador';

        return $this->insert($data);
    }

    /**
     * Actualiza nombre, correo y opcionalmente la contraseña de un usuario.
     */
    public function updateUser(int $userId, array $data): bool {
        $fields = [
            'nombre' => $data['nombre'],
            'correo' => $this->normalizeCorreo((string) $data['correo']),
        ];

        $plainPassword = $data['password'] ?? null;
        if (!empty($plainPassword)) {
            $fields['password_hash'] = password_hash((string) $plainPassword, PASSWORD_DEFAULT);
        }

        return $this->update($userId, $fields) > 0;
    }

    /**
     * Actualiza únicamente la contraseña de un usuario.
     */
    public function updatePassword(int $userId, string $newPassword): bool {
        return $this->update($userId, [
            'password_hash' => password_hash($newPassword, PASSWORD_DEFAULT),
        ]) > 0;
    }

    /**
     * Elimina una cuenta de usuario siempre que tenga rol 'criador'.
     */
    public function deleteBreederUser(int $userId): bool {
        $db = Db::getConnection();
        $stmt = $db->prepare("DELETE FROM {$this->table} WHERE id_usuario = :id_usuario AND rol = :rol");
        $stmt->execute([
            'id_usuario' => $userId,
            'rol'        => 'criador',
        ]);

        return $stmt->rowCount() > 0;
    }

    /**
     * Verifica si una contraseña en texto plano coincide con password_hash.
     */
    public function verifyPassword(string $password, string $hash): bool {
        return password_verify($password, $hash);
    }

    /**
     * Normaliza un correo electrónico eliminando espacios y pasando a minúsculas.
     */
    private function normalizeCorreo(string $correo): string {
        return mb_strtolower(trim($correo), 'UTF-8');
    }
}
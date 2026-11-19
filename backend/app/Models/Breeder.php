<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use CanariApp\Backend\Config\Db;
use PDOException;
use Throwable;

class Breeder extends BaseModel {
    protected string $table = 'criador';
    protected string $primaryKey = 'id_criador';

    /**
     * Busca el perfil de criador asociado a un ID de usuario (del token JWT).
     */
    public function findByUserId(int|string $userId): ?array {
        $sql = "SELECT c.id_criador, c.id_usuario, c.numero_socio, c.fecha_creacion,
                       u.nombre, u.correo, u.rol
                FROM {$this->table} c
                INNER JOIN usuario u ON c.id_usuario = u.id_usuario
                WHERE c.id_usuario = :id_usuario
                LIMIT 1";

        return $this->fetch($sql, ['id_usuario' => $userId]);
    }

    /**
     * Obtiene un criador por su PK junto con los datos de su cuenta de usuario.
     */
    public function findWithUser(int|string $breederId): ?array {
        $sql = "SELECT c.id_criador, c.id_usuario, c.numero_socio, c.fecha_creacion,
                       u.nombre, u.correo, u.rol
                FROM {$this->table} c
                INNER JOIN usuario u ON c.id_usuario = u.id_usuario
                WHERE c.id_criador = :id_criador
                LIMIT 1";

        return $this->fetch($sql, ['id_criador' => $breederId]);
    }

    /**
     * Lista todos los criadores ordenados del más reciente al más antiguo.
     */
    public function findAllWithUser(): array {
        $sql = "SELECT c.id_criador, c.id_usuario, c.numero_socio, c.fecha_creacion,
                       u.nombre, u.correo, u.rol
                FROM {$this->table} c
                INNER JOIN usuario u ON c.id_usuario = u.id_usuario
                ORDER BY c.id_criador DESC";

        return $this->fetchAll($sql);
    }

    /**
     * Busca criadores por coincidencia parcial en nombre, número de socio o correo.
     */
    public function search(string $term): array {
        $sql = "SELECT c.id_criador, c.id_usuario, c.numero_socio, c.fecha_creacion,
                       u.nombre, u.correo, u.rol
                FROM {$this->table} c
                INNER JOIN usuario u ON c.id_usuario = u.id_usuario
                WHERE u.nombre ILIKE :term
                   OR c.numero_socio ILIKE :term
                   OR u.correo ILIKE :term
                ORDER BY c.id_criador DESC";

        return $this->fetchAll($sql, [
            'term' => '%' . trim($term) . '%',
        ]);
    }

    public function create(array $data): array|int|string|null {
        $db = Db::getConnection();
        $startedTransaction = !$db->inTransaction();

        try {
            if ($startedTransaction) {
                $db->beginTransaction();
            }

            $memberNumber = trim((string) ($data['numero_socio'] ?? ''));

            // Caso 1: AuthController::register ya creó el usuario y envía 'id_usuario'
            if (isset($data['id_usuario'])) {
                if ($memberNumber === '' || $this->existsByMemberNumber($memberNumber)) {
                    if ($startedTransaction) {
                        $db->rollBack();
                    }
                    return 'conflict_member_number';
                }

                $breederId = (int) $this->insert([
                    'id_usuario'   => (int) $data['id_usuario'],
                    'numero_socio' => $memberNumber,
                ]);

                if ($startedTransaction) {
                    $db->commit();
                }

                return $breederId;
            }

            // Caso 2: Alta completa de usuario + criador (BreederController::store)
            $userModel = new User();
            $normalizedEmail = mb_strtolower(trim((string) $data['correo']), 'UTF-8');

            if ($userModel->existsByEmail($normalizedEmail)) {
                if ($startedTransaction) {
                    $db->rollBack();
                }
                return 'conflict_email';
            }

            if ($this->existsByMemberNumber($memberNumber)) {
                if ($startedTransaction) {
                    $db->rollBack();
                }
                return 'conflict_member_number';
            }

            $userId = (int) $userModel->create([
                'nombre'   => $data['nombre'],
                'correo'   => $normalizedEmail,
                'password' => $data['password'],
                'rol'      => 'criador',
            ]);

            $breederId = (int) $this->insert([
                'id_usuario'   => $userId,
                'numero_socio' => $memberNumber,
            ]);

            if ($startedTransaction) {
                $db->commit();
            }

            return $this->findWithUser($breederId) ?? [
                'id_criador'   => $breederId,
                'id_usuario'   => $userId,
                'nombre'       => $data['nombre'],
                'correo'       => $normalizedEmail,
                'rol'          => 'criador',
                'numero_socio' => $memberNumber,
            ];
        } catch (Throwable $e) {
            if ($startedTransaction && $db->inTransaction()) {
                $db->rollBack();
            }
            throw $e;
        }
    }

    /**
     * [Admin] Actualiza el perfil de criador y delega en User los cambios de cuenta en una transacción.
     */
    public function updateWithUser(int $breederId, array $data): array|string {
        $db = Db::getConnection();
        $userModel = new User();
        $normalizedEmail = mb_strtolower(trim((string) $data['correo']), 'UTF-8');

        try {
            $db->beginTransaction();

            // 1. Verificar que el criador exista
            $existing = $this->find($breederId);
            if ($existing === null) {
                $db->rollBack();
                return 'not_found';
            }
            $userId = (int) $existing['id_usuario'];

            // 2. Verificar que el correo no esté ocupado por otro usuario
            if ($userModel->existsByEmail($normalizedEmail, $userId)) {
                $db->rollBack();
                return 'conflict_email';
            }

            // 3. Verificar que el número de socio no pertenezca a otro criador
            if ($this->existsByMemberNumber((string) $data['numero_socio'], $breederId)) {
                $db->rollBack();
                return 'conflict_member_number';
            }

            // 4. Actualizar tabla criador
            $this->update($breederId, [
                'numero_socio' => $data['numero_socio'],
            ]);

            // 5. Delegar actualización de usuario al modelo User
            $userModel->updateUser($userId, [
                'nombre'   => $data['nombre'],
                'correo'   => $normalizedEmail,
                'password' => $data['password'] ?? null,
            ]);

            $db->commit();

            return $this->findWithUser($breederId) ?? [
                'id_criador'   => $breederId,
                'id_usuario'   => $userId,
                'nombre'       => $data['nombre'],
                'correo'       => $normalizedEmail,
                'numero_socio' => $data['numero_socio'],
            ];
        } catch (Throwable $e) {
            if ($db->inTransaction()) {
                $db->rollBack();
            }
            throw $e;
        }
    }

    /**
     * Elimina el perfil de criador y delega en User la eliminación de su cuenta.
     *
     * @return string 'deleted' | 'not_found' | 'forbidden' | 'conflict'
     */
    public function deleteWithUser(int $breederId): string {
        $db = Db::getConnection();
        $userModel = new User();

        try {
            $db->beginTransaction();

            $existing = $this->find($breederId);
            if ($existing === null) {
                $db->rollBack();
                return 'not_found';
            }
            $userId = (int) $existing['id_usuario'];

            $this->delete($breederId);
            $deleted = $userModel->deleteBreederUser($userId);

            if (!$deleted) {
                $db->rollBack();
                return 'not_found';
            }

            $db->commit();

            return 'deleted';
        } catch (PDOException $e) {
            if ($db->inTransaction()) {
                $db->rollBack();
            }

            $sqlState = (string) $e->getCode();

            if ($sqlState === '42501') {
                return 'forbidden';
            }

            if ($sqlState === '23503') {
                return 'conflict';
            }

            throw $e;
        } catch (Throwable $e) {
            if ($db->inTransaction()) {
                $db->rollBack();
            }
            throw $e;
        }
    }

    /**
     * Verifica si un número de socio ya está registrado por otro criador.
     */
    public function existsByMemberNumber(string $memberNumber, ?int $excludeBreederId = null): bool {
        if ($excludeBreederId !== null) {
            $sql = "SELECT 1 FROM {$this->table}
                    WHERE numero_socio = :numero_socio AND id_criador <> :id_criador
                    LIMIT 1";

            return $this->fetch($sql, [
                'numero_socio' => $memberNumber,
                'id_criador'   => $excludeBreederId,
            ]) !== null;
        }

        $sql = "SELECT 1 FROM {$this->table}
                WHERE numero_socio = :numero_socio
                LIMIT 1";

        return $this->fetch($sql, ['numero_socio' => $memberNumber]) !== null;
    }
}
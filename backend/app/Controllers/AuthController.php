<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\AuditHelper;
use CanariApp\Backend\Helpers\AuthHelper;
use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Breeder;
use CanariApp\Backend\Models\OperationMode;
use CanariApp\Backend\Models\User;
use Throwable;

class AuthController {
    /**
     * Inicia sesión verificando credenciales y devolviendo un JWT.
     * Si el sistema está en modo mantenimiento o emergencia, rechaza el login
     * de criadores con HTTP 503 y el mensaje del modo activo (SRS-RF028).
     */
    public function login(): void {
        $decoded = json_decode(file_get_contents('php://input') ?: '', true);
        $input = is_array($decoded) ? $decoded : [];

        $correo = is_string($input['correo'] ?? null) ? mb_strtolower(trim($input['correo'])) : '';
        $password = is_string($input['password'] ?? null) ? $input['password'] : '';

        if ($correo === '' || $password === '') {
            ResponseHelper::badRequest('El correo y la contraseña son obligatorios.');
        }

        $userModel = new User();
        $user = $userModel->findByCorreo($correo);

        if (!$user || !$userModel->verifyPassword($password, $user['password_hash'])) {
            $failedUserId = $user !== null && isset($user['id_usuario'])
                ? (int) $user['id_usuario']
                : null;

            $reason = $user !== null
                ? 'Intento de inicio de sesión fallido: contraseña incorrecta'
                : 'Intento de inicio de sesión fallido: correo no registrado';

            try {
                // SEG-003: Nunca se registra la contraseña ingresada
                AuditHelper::log(
                    action: 'login_fallido',
                    entity: 'sesion',
                    recordId: $failedUserId,
                    newValue: [
                        'correo'             => $correo,
                        'usuario_registrado' => $user !== null,
                    ],
                    reason: $reason,
                    userId: $failedUserId
                );
            } catch (Throwable) {
                // No interrumpir la respuesta 401 si falla el registro en auditoría
            }

            ResponseHelper::unauthorized('Credenciales incorrectas.');
        }

        // SRS-RF028: Bloquea el acceso de criadores cuando hay mantenimiento o emergencia activos
        if (($user['rol'] ?? null) === 'criador') {
            $activeMode = (new OperationMode())->findActive();
            if ($activeMode !== null) {
                $this->respondServiceUnavailableForMode($activeMode);
            }
        }

        $userId = (int) $user['id_usuario'];
        $token = AuthHelper::generateToken(
            $userId,
            $user['correo'],
            $user['rol']
        );

        AuditHelper::log(
            action: 'login',
            entity: 'sesion',
            recordId: $userId,
            newValue: [
                'correo' => $user['correo'],
                'rol'    => $user['rol'],
            ],
            reason: 'Inicio de sesión exitoso',
            userId: $userId
        );

        unset($user['password_hash']);

        ResponseHelper::success([
            'token' => $token,
            'user'  => $user,
        ], 'Inicio de sesión exitoso.');
    }

    /**
     * [Autenticado] Cierra la sesión actual revocando el token JWT enviado.
     */
    public function logout(): void {
        $authHeader = $_SERVER['HTTP_AUTHORIZATION']
            ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
            ?? '';

        if ($authHeader === '' && function_exists('getallheaders')) {
            $headers = getallheaders();
            $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? '';
        }

        if (!preg_match('/^Bearer\s+(\S+)$/i', trim($authHeader), $matches)) {
            ResponseHelper::unauthorized('Token de autorización no proporcionado.');
        }

        $token = $matches[1];
        $payload = AuthHelper::validateToken($token);

        if ($payload === null || !isset($payload->sub)) {
            ResponseHelper::unauthorized('Token inválido, expirado o sesión ya cerrada.');
        }

        AuthHelper::revokeToken($token, (int) $payload->sub);

        ResponseHelper::success(null, 'Sesión cerrada exitosamente.');
    }

    /**
     * [Admin] Registra un nuevo usuario con rol 'criador' y crea su perfil asociado.
     */
    public function register(): void {
        $decoded = json_decode(file_get_contents('php://input') ?: '', true);
        $input = is_array($decoded) ? $decoded : [];

        $nombre = is_string($input['nombre'] ?? null) ? trim($input['nombre']) : '';
        $correo = is_string($input['correo'] ?? null) ? mb_strtolower(trim($input['correo'])) : '';
        $password = is_string($input['password'] ?? null) ? trim($input['password']) : '';
        $numeroSocioRaw = $input['numero_socio'] ?? null;

        $isMissingMemberNumber = !array_key_exists('numero_socio', $input)
            || $numeroSocioRaw === null
            || (is_string($numeroSocioRaw) && trim($numeroSocioRaw) === '');

        if ($nombre === '' || $correo === '' || $password === '' || $isMissingMemberNumber) {
            ResponseHelper::badRequest('Nombre, correo, contraseña y número de socio son obligatorios.');
        }

        $numeroSocio = (is_string($numeroSocioRaw) || is_int($numeroSocioRaw))
            ? trim((string) $numeroSocioRaw)
            : '';

        $errors = [];
        if (mb_strlen($nombre) > 100) {
            $errors['nombre'] = 'El nombre no puede superar los 100 caracteres.';
        } elseif (strip_tags($nombre) !== $nombre || !preg_match("/^[\p{L}\p{M}\s.'-]+$/u", $nombre)) {
            $errors['nombre'] = 'El nombre contiene caracteres o etiquetas HTML no permitidos.';
        }

        if (mb_strlen($correo) > 100 || !filter_var($correo, FILTER_VALIDATE_EMAIL)) {
            $errors['correo'] = 'El correo electrónico no tiene un formato válido o supera los 100 caracteres.';
        }

        if (mb_strlen($password) < 8) {
            $errors['password'] = 'La contraseña debe tener al menos 8 caracteres.';
        }

        if (!preg_match('/^\d{1,5}$/', $numeroSocio)) {
            $errors['numero_socio'] = 'El número de socio debe contener entre 1 y 5 dígitos numéricos.';
        }

        if (!empty($errors)) {
            ResponseHelper::validationError($errors);
        }

        $userModel = new User();
        if ($userModel->findByCorreo($correo)) {
            ResponseHelper::conflict('El correo ya está registrado en el sistema.');
        }

        $criadorModel = new Breeder();
        if ($criadorModel->existsByMemberNumber($numeroSocio)) {
            ResponseHelper::conflict('El número de socio ya está registrado por otro criador.');
        }

        $rol = 'criador';
        $adminId = AuthMiddleware::userId() !== null ? (int) AuthMiddleware::userId() : null;

        try {
            $userModel->beginTransaction();

            [$userId, $criadorId] = AuditHelper::withoutAutoAudit(
                function () use ($userModel, $criadorModel, $nombre, $correo, $password, $rol, $numeroSocio, $adminId): array {
                    $newUserId = (int) $userModel->create([
                        'nombre'   => $nombre,
                        'correo'   => $correo,
                        'password' => $password,
                        'rol'      => $rol,
                    ]);

                    $newCriadorId = (int) $criadorModel->create([
                        'id_usuario'   => $newUserId,
                        'numero_socio' => $numeroSocio,
                    ]);

                    AuditHelper::log(
                        action: 'insert',
                        entity: 'usuario',
                        recordId: $newUserId,
                        newValue: [
                            'nombre' => $nombre,
                            'correo' => $correo,
                            'rol'    => $rol,
                        ],
                        reason: 'Registro de usuario criador por administrador',
                        userId: $adminId,
                        db: $userModel->getConnection()
                    );

                    AuditHelper::log(
                        action: 'insert',
                        entity: 'criador',
                        recordId: $newCriadorId,
                        newValue: [
                            'id_usuario'   => $newUserId,
                            'numero_socio' => $numeroSocio,
                        ],
                        reason: 'Creación de criadero asociado al registro',
                        userId: $adminId,
                        db: $userModel->getConnection()
                    );

                    return [$newUserId, $newCriadorId];
                }
            );

            $userModel->commit();
        } catch (Throwable $e) {
            $userModel->rollBack();
            throw $e;
        }

        ResponseHelper::created([
            'user' => [
                'id_usuario'   => $userId,
                'id_criador'   => $criadorId,
                'nombre'       => $nombre,
                'correo'       => $correo,
                'rol'          => $rol,
                'numero_socio' => $numeroSocio,
            ],
        ], 'Criador registrado exitosamente por el administrador.');
    }

    /**
     * Corta el inicio de sesión de criadores devolviendo HTTP 503 con el detalle del modo activo.
     *
     * @param array<string, mixed> $activeMode
     */
    private function respondServiceUnavailableForMode(array $activeMode): never {
        $modo = (string) ($activeMode['modo'] ?? 'mantenimiento');
        $message = $modo === 'emergencia'
            ? 'El sistema se encuentra temporalmente en modo de emergencia. Intente nuevamente más tarde.'
            : 'El sistema se encuentra en mantenimiento programado. Intente nuevamente más tarde.';

        http_response_code(503);
        header('Content-Type: application/json; charset=utf-8');
        header('Retry-After: 300');

        echo json_encode([
            'status'  => 'error',
            'success' => false,
            'message' => $message,
            'data'    => [
                'modo'             => $modo,
                'fecha_activacion' => $activeMode['fecha_activacion'] ?? null,
                'diagnostico'      => $activeMode['diagnostico'] ?? null,
            ],
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

        exit;
    }
}
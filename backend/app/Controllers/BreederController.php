<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Breeder;
use CanariApp\Backend\Models\User;

class BreederController {
    /**
     * [Criador] Obtiene el perfil del usuario autenticado.
     */
    public function myProfile(): void {
        $userId = AuthMiddleware::userId();
        $breederModel = new Breeder();
        $profile = $breederModel->findByUserId($userId);

        if ($profile === null) {
            ResponseHelper::notFound('El usuario actual no tiene un perfil de criador asociado.');
        }

        ResponseHelper::success($profile, 'Perfil de criador obtenido.');
    }

    /**
     * [Criador] Actualiza únicamente la contraseña del perfil propio.
     */
    public function updateProfile(): void {
        $userId = AuthMiddleware::userId();
        $breederModel = new Breeder();
        $profile = $breederModel->findByUserId($userId);

        if ($profile === null) {
            ResponseHelper::notFound('El usuario actual no tiene un perfil de criador asociado.');
        }

        $input = $this->getJsonInput();

        if (array_key_exists('numero_socio', $input)) {
            ResponseHelper::badRequest('El número de socio se asigna automáticamente y no puede ser modificado.');
        }

        if (!array_key_exists('password', $input) || !is_string($input['password'])) {
            ResponseHelper::validationError([
                'password' => 'Debe enviar la nueva contraseña.',
            ]);
        }

        $password = trim($input['password']);
        if (mb_strlen($password) < 8) {
            ResponseHelper::validationError([
                'password' => 'La contraseña debe tener al menos 8 caracteres.',
            ]);
        }

        $userModel = new User();
        $userModel->updatePassword((int) $userId, $password);

        $updated = $breederModel->findByUserId($userId);
        ResponseHelper::success($updated, 'Contraseña actualizada correctamente.');
    }

    /**
     * [Admin] Lista todos los criadores o filtra por nombre, número de socio o correo (?buscar=...).
     */
    public function index(): void {
        $breederModel = new Breeder();
        $search = trim((string) ($_GET['buscar'] ?? ''));

        $breeders = $search !== ''
            ? $breederModel->search($search)
            : $breederModel->findAllWithUser();

        ResponseHelper::success($breeders, 'Listado de criadores obtenido.');
    }

    /**
     * [Admin] Muestra el detalle de un criador específico.
     */
    public function show(int|string $id): void {
        $breederId = (int) $id;

        if ($breederId <= 0) {
            ResponseHelper::badRequest('El ID del criador no es válido.');
        }

        $breederModel = new Breeder();
        $breeder = $breederModel->findWithUser($breederId);

        if ($breeder === null) {
            ResponseHelper::notFound('Criador no encontrado.');
        }

        ResponseHelper::success($breeder, 'Detalle del criador obtenido.');
    }

    /**
     * [Admin] Crea la cuenta de usuario y el perfil de criador.
     */
    public function store(): void {
        $input = $this->getJsonInput();

        $name = is_string($input['nombre'] ?? null) ? trim($input['nombre']) : '';
        $email = is_string($input['correo'] ?? null) ? mb_strtolower(trim($input['correo']), 'UTF-8') : '';
        $password = is_string($input['password'] ?? null) ? trim($input['password']) : '';
        $rawMemberNumber = $input['numero_socio'] ?? null;

        $errors = [];

        $nameError = $this->getNameError($name);
        if ($nameError !== null) {
            $errors['nombre'] = $nameError;
        }

        $emailError = $this->getEmailError($email);
        if ($emailError !== null) {
            $errors['correo'] = $emailError;
        }

        if ($password === '' || mb_strlen($password) < 8) {
            $errors['password'] = 'La contraseña es obligatoria y debe tener al menos 8 caracteres.';
        }

        $memberNumberError = $this->getMemberNumberError($rawMemberNumber);
        if ($memberNumberError !== null) {
            $errors['numero_socio'] = $memberNumberError;
        }

        if (!empty($errors)) {
            ResponseHelper::validationError($errors);
        }

        $memberNumber = trim((string) $rawMemberNumber);

        $breederModel = new Breeder();
        $result = $breederModel->create([
            'nombre'       => $name,
            'correo'       => $email,
            'password'     => $password,
            'numero_socio' => $memberNumber,
        ]);

        if ($result === 'conflict_email') {
            ResponseHelper::conflict('El correo electrónico ya está registrado.');
        }

        if ($result === 'conflict_member_number') {
            ResponseHelper::conflict('El número de socio ya está registrado por otro criador.');
        }

        ResponseHelper::created($result, 'Criador creado exitosamente.');
    }

    /**
     * [Admin] Actualiza los datos de un criador y su cuenta de usuario por su ID.
     */
    public function update(int|string $id): void {
        $breederId = (int) $id;

        if ($breederId <= 0) {
            ResponseHelper::badRequest('El ID del criador no es válido.');
        }

        $breederModel = new Breeder();
        $existing = $breederModel->findWithUser($breederId);

        if ($existing === null) {
            ResponseHelper::notFound('Criador no encontrado.');
        }

        $input = $this->getJsonInput();

        $name = array_key_exists('nombre', $input)
            ? (is_string($input['nombre']) ? trim($input['nombre']) : '')
            : (string) $existing['nombre'];

        $email = array_key_exists('correo', $input)
            ? (is_string($input['correo']) ? mb_strtolower(trim($input['correo']), 'UTF-8') : '')
            : mb_strtolower(trim((string) $existing['correo']), 'UTF-8');

        $rawMemberNumber = array_key_exists('numero_socio', $input)
            ? $input['numero_socio']
            : (string) $existing['numero_socio'];

        $errors = [];

        $nameError = $this->getNameError($name);
        if ($nameError !== null) {
            $errors['nombre'] = $nameError;
        }

        $emailError = $this->getEmailError($email);
        if ($emailError !== null) {
            $errors['correo'] = $emailError;
        }

        $memberNumberError = $this->getMemberNumberError($rawMemberNumber);
        if ($memberNumberError !== null) {
            $errors['numero_socio'] = $memberNumberError;
        }

        $password = null;
        if (array_key_exists('password', $input) && $input['password'] !== null && $input['password'] !== '') {
            if (!is_string($input['password'])) {
                $errors['password'] = 'La contraseña debe ser una cadena de texto de al menos 8 caracteres.';
            } else {
                $trimmedPassword = trim($input['password']);
                if (mb_strlen($trimmedPassword) < 8) {
                    $errors['password'] = 'La contraseña debe tener al menos 8 caracteres.';
                } else {
                    $password = $trimmedPassword;
                }
            }
        }

        if (!empty($errors)) {
            ResponseHelper::validationError($errors);
        }

        $memberNumber = trim((string) $rawMemberNumber);

        $result = $breederModel->updateWithUser($breederId, [
            'nombre'       => $name,
            'correo'       => $email,
            'numero_socio' => $memberNumber,
            'password'     => $password,
        ]);

        if ($result === 'not_found') {
            ResponseHelper::notFound('Criador no encontrado.');
        }

        if ($result === 'conflict_email') {
            ResponseHelper::conflict('El correo electrónico ya está registrado por otro usuario.');
        }

        if ($result === 'conflict_member_number') {
            ResponseHelper::conflict('El número de socio ya está registrado por otro criador.');
        }

        ResponseHelper::success($result, 'Criador actualizado exitosamente.');
    }

    /**
     * [Admin] Elimina un perfil de criador junto con su cuenta de usuario.
     */
    public function destroy(int|string $id): void {
        $breederId = (int) $id;

        if ($breederId <= 0) {
            ResponseHelper::badRequest('El ID del criador no es válido.');
        }

        $breederModel = new Breeder();
        $result = $breederModel->deleteWithUser($breederId);

        if ($result === 'not_found') {
            ResponseHelper::notFound('No se encontró el criador especificado.');
        }

        if ($result === 'forbidden') {
            ResponseHelper::forbidden('La base de datos no permite eliminar criadores según las políticas de seguridad del sistema.');
        }

        if ($result === 'conflict') {
            ResponseHelper::conflict('No se puede eliminar el criador porque tiene registros o historial de auditoría asociado.');
        }

        ResponseHelper::noContent();
    }

    /**
     * Lee y decodifica el cuerpo JSON de la petición.
     */
    private function getJsonInput(): array {
        $raw = file_get_contents('php://input');
        if ($raw === false || trim($raw) === '') {
            return [];
        }

        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            ResponseHelper::badRequest('El cuerpo de la petición debe ser un JSON válido.');
        }

        return $decoded;
    }

    /**
     * Comprueba que numero_socio sea obligatorio y tenga entre 1 y 5 dígitos numéricos.
     */
    private function getMemberNumberError(mixed $value): ?string {
        if (!is_string($value) && !is_int($value)) {
            return 'El número de socio es obligatorio y debe contener entre 1 y 5 dígitos.';
        }

        $trimmed = trim((string) $value);
        if (!preg_match('/^\d{1,5}$/', $trimmed)) {
            return 'El número de socio debe contener entre 1 y 5 dígitos numéricos.';
        }

        return null;
    }

    /**
     * Comprueba que el nombre sea obligatorio, tenga máximo 100 caracteres y no incluya HTML.
     */
    private function getNameError(string $name): ?string {
        if ($name === '') {
            return 'El nombre es obligatorio.';
        }

        if (mb_strlen($name) > 100) {
            return 'El nombre no puede superar los 100 caracteres.';
        }

        if (strip_tags($name) !== $name || !preg_match("/^[\p{L}\p{M}\s.'-]+$/u", $name)) {
            return 'El nombre contiene caracteres o etiquetas HTML no permitidos.';
        }

        return null;
    }

    /**
     * Comprueba que el correo sea obligatorio, válido y no supere los 100 caracteres.
     */
    private function getEmailError(string $email): ?string {
        if ($email === '') {
            return 'El correo electrónico es obligatorio.';
        }

        if (mb_strlen($email) > 100 || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            return 'El correo electrónico no tiene un formato válido o supera los 100 caracteres.';
        }

        return null;
    }
}
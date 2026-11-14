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
     * [Admin] Crea automáticamente la cuenta de usuario y el perfil de criador con número de socio autogenerado.
     */
    public function store(): void {
        $input = $this->getJsonInput();

        $name = is_string($input['nombre'] ?? null) ? trim($input['nombre']) : '';
        $email = is_string($input['correo'] ?? null) ? trim($input['correo']) : '';
        $password = is_string($input['password'] ?? null) ? trim($input['password']) : '';

        $errors = [];
        if ($name === '') {
            $errors['nombre'] = 'El nombre es obligatorio.';
        }
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $errors['correo'] = 'El correo electrónico no es válido.';
        }
        if ($password === '' || mb_strlen($password) < 8) {
            $errors['password'] = 'La contraseña es obligatoria y debe tener al menos 8 caracteres.';
        }

        if (!empty($errors)) {
            ResponseHelper::validationError($errors);
        }

        $breederModel = new Breeder();
        $result = $breederModel->create([
            'nombre'   => $name,
            'correo'   => $email,
            'password' => $password,
        ]);

        if ($result === 'conflict_email') {
            ResponseHelper::conflict('El correo electrónico ya está registrado.');
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
            : $existing['nombre'];

        $email = array_key_exists('correo', $input)
            ? (is_string($input['correo']) ? trim($input['correo']) : '')
            : $existing['correo'];

        // Si se envía numero_socio, no puede ser null ni vacío; si se omite, conserva el actual
        $memberNumber = array_key_exists('numero_socio', $input)
            ? $this->validateMemberNumber($input['numero_socio'])
            : $existing['numero_socio'];

        $hasPassword = array_key_exists('password', $input) && $input['password'] !== null && $input['password'] !== '';
        $password = null;

        $errors = [];
        if ($name === '') {
            $errors['nombre'] = 'El nombre es obligatorio.';
        }
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $errors['correo'] = 'El correo electrónico no es válido.';
        }
        if ($hasPassword) {
            if (!is_string($input['password']) || mb_strlen(trim($input['password'])) < 8) {
                $errors['password'] = 'La contraseña debe tener al menos 8 caracteres.';
            } else {
                $password = trim($input['password']);
            }
        }

        if (!empty($errors)) {
            ResponseHelper::validationError($errors);
        }

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
        $deleted = $breederModel->deleteWithUser($breederId);

        if (!$deleted) {
            ResponseHelper::notFound('No se encontró el criador especificado.');
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
     * Valida y normaliza numero_socio (VARCHAR(5) NOT NULL en PostgreSQL).
     */
    private function validateMemberNumber(mixed $value): string {
        if ($value === null || (!is_string($value) && !is_numeric($value))) {
            ResponseHelper::validationError([
                'numero_socio' => 'El número de socio es obligatorio y no puede ser nulo.',
            ]);
        }

        $trimmed = trim((string) $value);
        if ($trimmed === '') {
            ResponseHelper::validationError([
                'numero_socio' => 'El número de socio no puede estar vacío.',
            ]);
        }

        if (mb_strlen($trimmed) > 5) {
            ResponseHelper::validationError([
                'numero_socio' => 'El número de socio no puede exceder los 5 caracteres.',
            ]);
        }

        return $trimmed;
    }
}
<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\ResponseHelper;

class HomeController {
    /**
     * Punto de entrada raíz de la API.
     */
    public function index(): void {
        ResponseHelper::success([
            'service' => 'CanariApp API',
            'version' => 'v1',
            'links'   => [
                'health' => 'GET /api/health',
                'v1'     => 'GET /api/v1',
                'login'  => 'POST /api/login',
            ],
        ], 'Bienvenido a la API de CanariApp.');
    }

    /**
     * Verifica el estado operativo del servicio.
     */
    public function health(): void {
        ResponseHelper::success([
            'status'    => 'ok',
            'timezone'  => date_default_timezone_get(),
            'timestamp' => date(DATE_ATOM),
        ], 'Servicio operativo.');
    }

    /**
     * Devuelve el índice general de endpoints disponibles en la versión 1.
     */
    public function v1(): void {
        ResponseHelper::success([
            'base_path' => '/api/v1',
            'endpoints' => [
                'public' => [
                    'GET /',
                    'GET /api/health',
                    'GET /api/v1',
                    'POST /api/login',
                ],
                'session' => [
                    'GET /api/v1/me',
                    'POST /api/v1/logout',
                ],
                'breeder_profile' => [
                    'GET /api/v1/criador/perfil',
                    'PUT /api/v1/criador/perfil',
                ],
                'admin_breeders' => [
                    'GET /api/v1/admin/criadores',
                    'GET /api/v1/admin/criadores/{id}',
                    'POST /api/v1/admin/criadores',
                    'POST /api/v1/admin/register',
                    'PUT /api/v1/admin/criadores/{id}',
                    'DELETE /api/v1/admin/criadores/{id}',
                ],
                'canaries' => [
                    'GET /api/v1/canarios',
                    'GET /api/v1/canarios/{id}',
                    'POST /api/v1/canarios',
                    'PUT /api/v1/canarios/{id}',
                    'PATCH /api/v1/canarios/{id}',
                ],
                'cages' => [
                    'GET /api/v1/jaulas',
                    'GET /api/v1/jaulas/{id}',
                    'POST /api/v1/jaulas',
                ],
            ],
        ], 'Índice de endpoints de CanariApp API v1.');
    }
}

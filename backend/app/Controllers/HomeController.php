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
                'wiki'   => 'GET /api/v1/wiki',
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
     * Devuelve el índice general de endpoints disponibles en la versión v1.
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
                    'GET /api/v1/modo-operacion/estado',
                ],
                'breeder_profile' => [
                    'GET /api/v1/criador/perfil',
                    'PUT /api/v1/criador/perfil',
                ],
                'canaries' => [
                    'GET /api/v1/canarios',
                    'GET /api/v1/canarios/{id}',
                    'GET /api/v1/canarios/{id}/ascendencia',
                    'POST /api/v1/canarios',
                    'PUT /api/v1/canarios/{id}',
                    'PATCH /api/v1/canarios/{id}',
                ],
                'correction_requests' => [
                    'GET /api/v1/solicitudes-correccion',
                    'GET /api/v1/solicitudes-correccion/{id}',
                    'POST /api/v1/solicitudes-correccion',
                    'PATCH /api/v1/solicitudes-correccion/{id}/cancelar',
                ],
                'cages' => [
                    'GET /api/v1/jaulas',
                    'GET /api/v1/jaulas/{id}',
                    'POST /api/v1/jaulas',
                ],
                'pairs' => [
                    'GET /api/v1/parejas',
                    'GET /api/v1/parejas/{id}',
                    'POST /api/v1/parejas',
                    'PUT /api/v1/parejas/{id}',
                    'PATCH /api/v1/parejas/{id}',
                ],
                'matings' => [
                    'GET /api/v1/cruces',
                    'GET /api/v1/cruces/pareja/{id}',
                    'GET /api/v1/cruces/{id}',
                    'POST /api/v1/cruces',
                ],
                'nests' => [
                    'GET /api/v1/nidadas',
                    'GET /api/v1/nidadas/cruce/{id}',
                    'GET /api/v1/nidadas/{id}',
                    'POST /api/v1/nidadas',
                ],
                'chicks' => [
                    'GET /api/v1/crias',
                    'GET /api/v1/crias/nidada/{id}',
                    'GET /api/v1/crias/{id}',
                    'GET /api/v1/crias/{id}/ascendencia',
                    'POST /api/v1/crias',
                    'PUT /api/v1/crias/{id}',
                    'PATCH /api/v1/crias/{id}',
                ],
                'titles' => [
                    'GET /api/v1/titulos',
                    'GET /api/v1/titulos/canario/{id}',
                    'GET /api/v1/titulos/canario/{id}/descendencia',
                    'GET /api/v1/titulos/{id}',
                    'POST /api/v1/titulos',
                    'PUT /api/v1/titulos/{id}',
                    'PATCH /api/v1/titulos/{id}',
                ],
                'simulations' => [
                    'GET /api/v1/simulaciones',
                    'GET /api/v1/simulaciones/{id}',
                    'POST /api/v1/simulaciones',
                ],
                'catalogs' => [
                    'GET /api/v1/wiki',
                    'GET /api/v1/wiki/clubes',
                    'GET /api/v1/wiki/variedades',
                    'GET /api/v1/wiki/variedades/codigo/{codigo}',
                    'GET /api/v1/wiki/variedades/{id}',
                    'GET /api/v1/wiki/mutaciones',
                ],
                'admin' => [
                    'GET /api/v1/admin/criadores',
                    'GET /api/v1/admin/criadores/{id}',
                    'POST /api/v1/admin/criadores',
                    'POST /api/v1/admin/register',
                    'PUT /api/v1/admin/criadores/{id}',
                    'GET /api/v1/admin/solicitudes-correccion',
                    'GET /api/v1/admin/solicitudes-correccion/{id}',
                    'PATCH /api/v1/admin/solicitudes-correccion/{id}',
                    'PATCH /api/v1/admin/canarios/{id}',
                    'GET /api/v1/admin/modo-operacion',
                    'GET /api/v1/admin/modo-operacion/activo',
                    'GET /api/v1/admin/modo-operacion/{id}',
                    'POST /api/v1/admin/modo-operacion',
                    'PATCH /api/v1/admin/modo-operacion/{id}/diagnostico',
                    'PATCH /api/v1/admin/modo-operacion/{id}/desactivar',
                    'GET /api/v1/admin/auditoria',
                    'GET /api/v1/admin/auditoria/{id}',
                    'GET /api/v1/admin/respaldos',
                    'GET /api/v1/admin/respaldos/{id}',
                    'POST /api/v1/admin/respaldos',
                    'POST /api/v1/admin/respaldos/{id}/restaurar',
                    'POST /api/v1/admin/nomenclador',
                    'POST /api/v1/admin/clubes',
                    'POST /api/v1/admin/mutaciones',
                ],
            ],
        ], 'Índice de endpoints de CanariApp API v1.');
    }
}
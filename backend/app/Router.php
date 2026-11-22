<?php

declare(strict_types=1);

namespace CanariApp\Backend;

use Bramus\Router\Router as BramusRouter;
use CanariApp\Backend\Controllers\Api\WikiController;
use CanariApp\Backend\Controllers\AuthController;
use CanariApp\Backend\Controllers\BreederController;
use CanariApp\Backend\Controllers\CanaryController;
use CanariApp\Backend\Controllers\HomeController;
use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Middlewares\AuthMiddleware;

final class Router {
    private BramusRouter $router;

    public function __construct() {
        $this->router = new BramusRouter();
        $this->registerRoutes();
    }

    private function registerRoutes(): void {
        // --- RUTAS PÚBLICAS ---
        $this->router->get('/', HomeController::class . '@index');
        $this->router->get('/api/health', HomeController::class . '@health');
        $this->router->get('/api/v1', HomeController::class . '@v1');

        $this->router->post('/api/login', AuthController::class . '@login');

        // --- MIDDLEWARES DE SEGURIDAD ---
        $this->router->before('GET|POST|PUT|PATCH|DELETE', '/api/v1/.+', function (): void {
            AuthMiddleware::handle();
        });

        $this->router->before('GET|POST|PUT|PATCH|DELETE', '/api/v1/admin/.+', function (): void {
            AuthMiddleware::requireRole('administrador');
        });

        // --- RUTAS PRIVADAS ---
        $this->router->get('/api/v1/me', function (): void {
            ResponseHelper::success(
                ['user' => AuthMiddleware::user()],
                'Usuario autenticado.'
            );
        });

        $this->router->post('/api/v1/logout', AuthController::class . '@logout');

        // Perfil del criador autenticado
        $this->router->get('/api/v1/criador/perfil', BreederController::class . '@myProfile');
        $this->router->put('/api/v1/criador/perfil', BreederController::class . '@updateProfile');

        // Gestión administrativa de criadores
        $this->router->get('/api/v1/admin/criadores', BreederController::class . '@index');
        $this->router->get('/api/v1/admin/criadores/(\d+)', BreederController::class . '@show');

        $this->router->post('/api/v1/admin/register', AuthController::class . '@register');
        $this->router->post('/api/v1/admin/criadores', BreederController::class . '@store');
        
        $this->router->put('/api/v1/admin/criadores/(\d+)', BreederController::class . '@update');
        
        $this->router->delete('/api/v1/admin/criadores/(\d+)', BreederController::class . '@destroy');

        // Canarios: sin borrado (SRS 1.2, BD v7.1 no concede DELETE)
        $this->router->get('/api/v1/canarios', CanaryController::class . '@index');
        $this->router->get('/api/v1/canarios/(\d+)', CanaryController::class . '@show');
        $this->router->post('/api/v1/canarios', CanaryController::class . '@store');
        $this->router->put('/api/v1/canarios/(\d+)', CanaryController::class . '@update');
        $this->router->patch('/api/v1/canarios/(\d+)', CanaryController::class . '@update');

        // Catálogos oficiales (wiki): solo lectura, SRS-RF002/007/008/009/011/025/027
        $this->router->get('/api/v1/wiki', WikiController::class . '@index');
        $this->router->get('/api/v1/wiki/clubes', WikiController::class . '@clubes');
        $this->router->get('/api/v1/wiki/variedades', WikiController::class . '@variedades');
        $this->router->get('/api/v1/wiki/variedades/codigo/([^/]+)', WikiController::class . '@variedadPorCodigo');
        $this->router->get('/api/v1/wiki/variedades/(\d+)', WikiController::class . '@variedad');
        $this->router->get('/api/v1/wiki/mutaciones', WikiController::class . '@mutaciones');

        // --- 404 ---
        $this->router->set404(function (): void {
            ResponseHelper::notFound('La ruta solicitada no existe.');
        });
    }

    public function run(): void {
        $this->router->run();
    }
}
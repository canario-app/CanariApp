<?php

declare(strict_types=1);

namespace CanariApp\Backend;

use Bramus\Router\Router as BramusRouter;
use CanariApp\Backend\Controllers\Api\WikiController;
use CanariApp\Backend\Controllers\AuthController;
use CanariApp\Backend\Controllers\BreederController;
use CanariApp\Backend\Controllers\CanaryController;
use CanariApp\Backend\Controllers\CageController;
use CanariApp\Backend\Controllers\HomeController;
use CanariApp\Backend\Controllers\MatingController;
use CanariApp\Backend\Controllers\NestController;
use CanariApp\Backend\Controllers\PairController;
use CanariApp\Backend\Controllers\TitleController;
use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Controllers\ChickController;

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
        
        // Jaulas: solo el criador autenticado, dentro de su propio criadero.
        $this->router->get('/api/v1/jaulas', CageController::class . '@index');
        $this->router->get('/api/v1/jaulas/(\d+)', CageController::class . '@show');
        $this->router->post('/api/v1/jaulas', CageController::class . '@store');

        // Parejas y jaulas: sin borrado físico (SRS 1.2, ciclo de vida en BD v7.1)
        $this->router->get('/api/v1/parejas', PairController::class . '@index');
        $this->router->get('/api/v1/parejas/(\d+)', PairController::class . '@show');
        $this->router->post('/api/v1/parejas', PairController::class . '@store');
        $this->router->put('/api/v1/parejas/(\d+)', PairController::class . '@update');
        $this->router->patch('/api/v1/parejas/(\d+)', PairController::class . '@update');

        // Cruces: una pareja puede tener varios; sin edición ni borrado (SRS-RF016, SQL-01)
        $this->router->get('/api/v1/cruces', MatingController::class . '@index');
        $this->router->get('/api/v1/cruces/pareja/(\d+)', MatingController::class . '@byPair');
        $this->router->get('/api/v1/cruces/(\d+)', MatingController::class . '@show');
        $this->router->post('/api/v1/cruces', MatingController::class . '@store');

        // Nidadas: asociadas a un cruce; sin edición ni borrado en este alcance (SRS-RF018, SQL-01).
        $this->router->get('/api/v1/nidadas', NestController::class . '@index');
        $this->router->get('/api/v1/nidadas/cruce/(\d+)', NestController::class . '@byMating');
        $this->router->get('/api/v1/nidadas/(\d+)', NestController::class . '@show');
        $this->router->post('/api/v1/nidadas', NestController::class . '@store');
        
        

        // Crías: asociadas a una nidada y a un canario; sin borrado físico
        $this->router->get('/api/v1/crias', ChickController::class . '@index');
        $this->router->get('/api/v1/crias/nidada/(\d+)', ChickController::class . '@byNest');
        $this->router->get('/api/v1/crias/(\d+)', ChickController::class . '@show');
        $this->router->post('/api/v1/crias', ChickController::class . '@store');
        $this->router->put('/api/v1/crias/(\d+)', ChickController::class . '@update');
        $this->router->patch('/api/v1/crias/(\d+)', ChickController::class . '@update');

        // Títulos de competencia: el ejemplar es inmutable; sin borrado físico (SRS-RF023/024)
        $this->router->get('/api/v1/titulos', TitleController::class . '@index');
        $this->router->get('/api/v1/titulos/canario/(\d+)/descendencia', TitleController::class . '@offspring');
        $this->router->get('/api/v1/titulos/canario/(\d+)', TitleController::class . '@byCanary');
        $this->router->get('/api/v1/titulos/(\d+)', TitleController::class . '@show');
        $this->router->post('/api/v1/titulos', TitleController::class . '@store');
        $this->router->put('/api/v1/titulos/(\d+)', TitleController::class . '@update');
        $this->router->patch('/api/v1/titulos/(\d+)', TitleController::class . '@update');

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

<?php

declare(strict_types=1);

namespace CanariApp\Backend;

use Bramus\Router\Router as BramusRouter;
use CanariApp\Backend\Controllers\Api\WikiController;
use CanariApp\Backend\Controllers\AuditController;
use CanariApp\Backend\Controllers\AuthController;
use CanariApp\Backend\Controllers\BackupController;
use CanariApp\Backend\Controllers\BreederController;
use CanariApp\Backend\Controllers\CageController;
use CanariApp\Backend\Controllers\CanaryController;
use CanariApp\Backend\Controllers\ChickController;
use CanariApp\Backend\Controllers\CorrectionRequestController;
use CanariApp\Backend\Controllers\HomeController;
use CanariApp\Backend\Controllers\MatingController;
use CanariApp\Backend\Controllers\NestController;
use CanariApp\Backend\Controllers\OperationModeController;
use CanariApp\Backend\Controllers\PairController;
use CanariApp\Backend\Controllers\SimulationController;
use CanariApp\Backend\Controllers\TitleController;
use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Middlewares\OperationModeMiddleware;

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

        // Solo el rol criador puede acceder a los módulos operativos de crianza (administrador recibe 403)
        // Si existe modo mantenimiento o emergencia activo, devuelve 503 Service Unavailable
        $breederRoutes = '/api/v1/(?:criador|canarios|jaulas|parejas|cruces|nidadas|crias|titulos|simulaciones|solicitudes-correccion)(?:/.*)?';
        $this->router->before('GET|POST|PUT|PATCH|DELETE', $breederRoutes, function (): void {
            AuthMiddleware::requireRole('criador');
            OperationModeMiddleware::ensureNormalMode();
        });

        // --- RUTAS PRIVADAS ---
        $this->router->get('/api/v1/me', function (): void {
            ResponseHelper::success(
                ['user' => AuthMiddleware::user()],
                'Usuario autenticado.'
            );
        });

        $this->router->post('/api/v1/logout', AuthController::class . '@logout');

        // Consulta del estado de operación del sistema (normal, mantenimiento o emergencia)
        $this->router->get('/api/v1/modo-operacion/estado', OperationModeController::class . '@status');

        // Perfil del criador autenticado
        $this->router->get('/api/v1/criador/perfil', BreederController::class . '@myProfile');
        $this->router->put('/api/v1/criador/perfil', BreederController::class . '@updateProfile');

        // Gestión administrativa de criadores (sin DELETE: BD v7.1 no concede borrado ni baja de criadero)
        $this->router->get('/api/v1/admin/criadores', BreederController::class . '@index');
        $this->router->get('/api/v1/admin/criadores/(\d+)', BreederController::class . '@show');
        $this->router->post('/api/v1/admin/register', AuthController::class . '@register');
        $this->router->post('/api/v1/admin/criadores', BreederController::class . '@store');
        $this->router->put('/api/v1/admin/criadores/(\d+)', BreederController::class . '@update');

        // Gestión administrativa de solicitudes de corrección (SRS-RF033)
        $this->router->get('/api/v1/admin/solicitudes-correccion', CorrectionRequestController::class . '@adminIndex');
        $this->router->get('/api/v1/admin/solicitudes-correccion/(\d+)', CorrectionRequestController::class . '@adminShow');
        $this->router->patch('/api/v1/admin/solicitudes-correccion/(\d+)', CorrectionRequestController::class . '@resolve');

        // Gestión administrativa de modos de operación (SRS-RF028, DAT-003)
        $this->router->get('/api/v1/admin/modo-operacion', OperationModeController::class . '@index');
        $this->router->get('/api/v1/admin/modo-operacion/activo', OperationModeController::class . '@status');
        $this->router->get('/api/v1/admin/modo-operacion/(\d+)', OperationModeController::class . '@show');
        $this->router->post('/api/v1/admin/modo-operacion', OperationModeController::class . '@activate');
        $this->router->patch('/api/v1/admin/modo-operacion/(\d+)/diagnostico', OperationModeController::class . '@diagnose');
        $this->router->patch('/api/v1/admin/modo-operacion/(\d+)/desactivar', OperationModeController::class . '@deactivate');

        // Consulta administrativa de auditoría (SEG-003, solo lectura)
        $this->router->get('/api/v1/admin/auditoria', AuditController::class . '@index');
        $this->router->get('/api/v1/admin/auditoria/(\d+)', AuditController::class . '@show');

        // Gestión administrativa de respaldos con rotación de los 7 más recientes (DAT-003)
        $this->router->get('/api/v1/admin/respaldos', BackupController::class . '@index');
        $this->router->get('/api/v1/admin/respaldos/(\d+)', BackupController::class . '@show');
        $this->router->post('/api/v1/admin/respaldos', BackupController::class . '@store');

        // Canarios: sin borrado (SRS 1.2, BD v7.1 no concede DELETE)
        $this->router->get('/api/v1/canarios', CanaryController::class . '@index');
        $this->router->get('/api/v1/canarios/(\d+)/ascendencia', CanaryController::class . '@ancestry');
        $this->router->get('/api/v1/canarios/(\d+)', CanaryController::class . '@show');
        $this->router->post('/api/v1/canarios', CanaryController::class . '@store');
        $this->router->put('/api/v1/canarios/(\d+)', CanaryController::class . '@update');
        $this->router->patch('/api/v1/canarios/(\d+)', CanaryController::class . '@update');

        // Solicitudes de corrección del criador (SRS-RF033)
        $this->router->get('/api/v1/solicitudes-correccion', CorrectionRequestController::class . '@index');
        $this->router->get('/api/v1/solicitudes-correccion/(\d+)', CorrectionRequestController::class . '@show');
        $this->router->post('/api/v1/solicitudes-correccion', CorrectionRequestController::class . '@store');
        $this->router->patch('/api/v1/solicitudes-correccion/(\d+)/cancelar', CorrectionRequestController::class . '@cancel');

        // Jaulas: solo el criador autenticado, dentro de su propio criadero
        $this->router->get('/api/v1/jaulas', CageController::class . '@index');
        $this->router->get('/api/v1/jaulas/(\d+)', CageController::class . '@show');
        $this->router->post('/api/v1/jaulas', CageController::class . '@store');

        // Parejas: sin borrado físico (SRS 1.2, ciclo de vida en BD v7.1)
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

        // Nidadas: asociadas a un cruce; sin edición ni borrado en este alcance (SRS-RF018, SQL-01)
        $this->router->get('/api/v1/nidadas', NestController::class . '@index');
        $this->router->get('/api/v1/nidadas/cruce/(\d+)', NestController::class . '@byMating');
        $this->router->get('/api/v1/nidadas/(\d+)', NestController::class . '@show');
        $this->router->post('/api/v1/nidadas', NestController::class . '@store');

        // Crías: asociadas a una nidada y a un canario; sin borrado físico
        $this->router->get('/api/v1/crias', ChickController::class . '@index');
        $this->router->get('/api/v1/crias/nidada/(\d+)', ChickController::class . '@byNest');
        $this->router->get('/api/v1/crias/(\d+)/ascendencia', ChickController::class . '@ancestry');
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

        // Simulación genética: consulta e historial por criadero; sin edición ni borrado físico
        $this->router->get('/api/v1/simulaciones', SimulationController::class . '@index');
        $this->router->get('/api/v1/simulaciones/(\d+)', SimulationController::class . '@show');
        $this->router->post('/api/v1/simulaciones', SimulationController::class . '@store');

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
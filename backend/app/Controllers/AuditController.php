<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Helpers\Sanitizer;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\Audit;
use Throwable;

/**
 * Controlador administrativo de solo lectura para consultar auditoria (SEG-003).
 */
class AuditController {
    private Audit $auditModel;

    public function __construct(?Audit $auditModel = null) {
        $this->auditModel = $auditModel ?? new Audit();
    }

    /**
     * [Admin] Lista los registros de auditoría con filtros y paginación.
     */
    public function index(): void {
        $this->ensureAdminRole();

        try {
            $filters = [
                'id_usuario'             => $_GET['id_usuario'] ?? null,
                'accion'                 => $_GET['accion'] ?? null,
                'entidad'                => $_GET['entidad'] ?? null,
                'id_registro'            => $_GET['id_registro'] ?? null,
                'id_criador_solicitante' => $_GET['id_criador_solicitante'] ?? null,
                'id_solicitud'           => $_GET['id_solicitud'] ?? null,
                'fecha_desde'            => $_GET['fecha_desde'] ?? null,
                'fecha_hasta'            => $_GET['fecha_hasta'] ?? null,
                'buscar'                 => $_GET['buscar'] ?? null,
                'limit'                  => $_GET['limit'] ?? null,
                'offset'                 => $_GET['offset'] ?? null,
            ];

            $result = $this->auditModel->findAllPaginated($filters);
            ResponseHelper::success($result, 'Registros de auditoría obtenidos.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudieron obtener los registros de auditoría.');
        }
    }

    /**
     * [Admin] Muestra el detalle completo de un evento de auditoría.
     */
    public function show(int|string $id): void {
        $this->ensureAdminRole();

        $idAuditoria = Sanitizer::int($id, 1);
        if ($idAuditoria === null) {
            ResponseHelper::badRequest('El ID de auditoría no es válido.');
            return;
        }

        try {
            $record = $this->auditModel->findDetailed($idAuditoria);
            if ($record === null) {
                ResponseHelper::notFound('Registro de auditoría no encontrado.');
                return;
            }

            ResponseHelper::success($record, 'Detalle de auditoría obtenido.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo obtener el registro de auditoría.');
        }
    }

    private function ensureAdminRole(): void {
        if (AuthMiddleware::userRole() !== 'administrador') {
            ResponseHelper::forbidden('Solo un administrador puede consultar la auditoría del sistema.');
        }
    }
}
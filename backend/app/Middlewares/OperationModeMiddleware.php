<?php

declare(strict_types=1);

namespace CanariApp\Backend\Middlewares;

use CanariApp\Backend\Models\OperationMode;

/**
 * Impide operar sobre los módulos de crianza mientras el sistema se encuentre
 * en modo 'mantenimiento' o 'emergencia' (SRS-RF028, DAT-003).
 */
final class OperationModeMiddleware {
    /**
     * Verifica que el sistema opere en modo normal; si hay un modo especial
     * activo, corta la petición con HTTP 503 Service Unavailable.
     */
    public static function ensureNormalMode(): void {
        $active = (new OperationMode())->findActive();

        if ($active === null) {
            return;
        }

        $modo = (string) $active['modo'];
        $message = $modo === 'emergencia'
            ? 'El sistema se encuentra temporalmente en modo de emergencia. Intente nuevamente más tarde.'
            : 'El sistema se encuentra en mantenimiento programado. Intente nuevamente más tarde.';

        http_response_code(503);
        header('Content-Type: application/json; charset=utf-8');
        header('Retry-After: 300');

        echo json_encode([
            'success' => false,
            'message' => $message,
            'data'    => [
                'modo'             => $modo,
                'fecha_activacion' => $active['fecha_activacion'] ?? null,
                'diagnostico'      => $active['diagnostico'] ?? null,
            ],
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

        exit;
    }
}
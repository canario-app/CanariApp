<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

class Audit extends BaseModel {
    protected string $table = 'auditoria';
    protected string $primaryKey = 'id_auditoria';

    /** Campos sensibles que nunca deben guardarse en auditoría (SEG-003). */
    private const SENSITIVE_KEYS = [
        'password',
        'password_hash',
        'token',
    ];

    /**
     * Registra una acción en la tabla auditoria.
     */
    public function log(
        ?int $userId,
        string $action,
        ?string $entity = null,
        ?int $recordId = null,
        mixed $previousValue = null,
        mixed $newValue = null,
        ?string $reason = null,
        ?int $requestingBreederId = null,
        ?int $requestId = null
    ): int {
        $id = $this->insert([
            'id_usuario'             => $userId,
            'accion'                 => trim($action),
            'entidad'                => $entity,
            'id_registro'            => $recordId,
            'valor_anterior'         => $this->serializeValue($previousValue),
            'valor_nuevo'            => $this->serializeValue($newValue),
            'motivo'                 => $reason,
            'id_criador_solicitante' => $requestingBreederId,
            'id_solicitud'           => $requestId,
        ]);

        return (int) $id;
    }

    /**
     * Convierte arreglos o escalares a texto seguro para auditoría.
     */
    private function serializeValue(mixed $value): ?string {
        if ($value === null) {
            return null;
        }

        if (is_array($value)) {
            $cleaned = array_diff_key($value, array_flip(self::SENSITIVE_KEYS));
            $encoded = json_encode($cleaned, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

            return $encoded === false ? null : $encoded;
        }

        return (string) $value;
    }
}
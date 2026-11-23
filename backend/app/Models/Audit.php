<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

/**
 * Modelo de consulta de la tabla auditoria según el esquema v7.1 (SEG-003).
 *
 * La tabla auditoria es de solo lectura e inserción (trg_auditoria_inmutable);
 * la escritura se realiza únicamente mediante AuditHelper::log().
 */
class Audit extends BaseModel {
    protected string $table = 'auditoria';
    protected string $primaryKey = 'id_auditoria';

    private const DEFAULT_LIMIT = 50;
    private const MAX_LIMIT = 200;

    /**
     * Busca un evento de auditoría por su clave primaria con datos relacionados.
     *
     * @return array<string, mixed>|null
     */
    public function findDetailed(int $id): ?array {
        $sql = $this->detailedSelect()
            . ' WHERE a.id_auditoria = :id_auditoria'
            . ' LIMIT 1';

        return $this->fetch($sql, ['id_auditoria' => $id]);
    }

    /**
     * Lista eventos de auditoría con filtros y paginación.
     *
     * Filtros admitidos: id_usuario, accion, entidad, id_registro,
     * id_criador_solicitante, id_solicitud, fecha_desde, fecha_hasta, buscar.
     *
     * @param array<string, mixed> $filters
     * @return array{items: array<int, array<string, mixed>>, total: int, limit: int, offset: int}
     */
    public function findAllPaginated(array $filters = []): array {
        [$whereClause, $params] = $this->buildAuditFilters($filters);

        $limit = $this->normalizeLimit($filters['limit'] ?? null);
        $offset = $this->normalizeOffset($filters['offset'] ?? null);

        $countSql = 'SELECT COUNT(*) FROM ' . $this->quoteIdentifier($this->table) . ' a' . $whereClause;
        $total = (int) $this->fetchColumn($countSql, $params);

        $sql = $this->detailedSelect()
            . $whereClause
            . ' ORDER BY a.fecha_hora DESC, a.id_auditoria DESC'
            . sprintf(' LIMIT %d OFFSET %d', $limit, $offset);

        $items = $this->fetchAll($sql, $params);

        return [
            'items'  => $items,
            'total'  => $total,
            'limit'  => $limit,
            'offset' => $offset,
        ];
    }

    /**
     * Construye cláusulas WHERE seguras con parámetros ligados.
     *
     * @param array<string, mixed> $filters
     * @return array{0: string, 1: array<string, mixed>}
     */
    private function buildAuditFilters(array $filters): array {
        $conditions = [];
        $params = [];

        foreach (['id_usuario', 'id_registro', 'id_criador_solicitante', 'id_solicitud'] as $intField) {
            $intVal = $this->positiveInt($filters[$intField] ?? null);
            if ($intVal !== null) {
                $conditions[] = 'a.' . $intField . ' = :' . $intField;
                $params[$intField] = $intVal;
            }
        }

        foreach (['accion', 'entidad'] as $textField) {
            $value = $filters[$textField] ?? null;
            if (is_scalar($value) && trim((string) $value) !== '') {
                $conditions[] = 'a.' . $textField . ' = :' . $textField;
                $params[$textField] = trim((string) $value);
            }
        }

        $fechaDesde = $filters['fecha_desde'] ?? null;
        if (is_string($fechaDesde) && preg_match('/^\d{4}-\d{2}-\d{2}$/', trim($fechaDesde)) === 1) {
            $conditions[] = 'a.fecha_hora >= :fecha_desde';
            $params['fecha_desde'] = trim($fechaDesde) . ' 00:00:00';
        }

        $fechaHasta = $filters['fecha_hasta'] ?? null;
        if (is_string($fechaHasta) && preg_match('/^\d{4}-\d{2}-\d{2}$/', trim($fechaHasta)) === 1) {
            $conditions[] = 'a.fecha_hora <= :fecha_hasta';
            $params['fecha_hasta'] = trim($fechaHasta) . ' 23:59:59.999999';
        }

        $buscar = $filters['buscar'] ?? null;
        if (is_scalar($buscar) && trim((string) $buscar) !== '') {
            $term = '%' . trim((string) $buscar) . '%';
            $conditions[] = '(a.motivo ILIKE :buscar_motivo OR a.valor_anterior ILIKE :buscar_prev OR a.valor_nuevo ILIKE :buscar_new)';
            $params['buscar_motivo'] = $term;
            $params['buscar_prev'] = $term;
            $params['buscar_new'] = $term;
        }

        if ($conditions === []) {
            return ['', []];
        }

        return [' WHERE ' . implode(' AND ', $conditions), $params];
    }

    /**
     * SELECT base uniendo el usuario ejecutor y el criador solicitante (si aplica).
     */
    private function detailedSelect(): string {
        return 'SELECT a.id_auditoria,
                       a.id_usuario,
                       u.nombre AS usuario_nombre,
                       u.correo AS usuario_correo,
                       u.rol AS usuario_rol,
                       a.fecha_hora,
                       a.accion,
                       a.entidad,
                       a.id_registro,
                       a.valor_anterior,
                       a.valor_nuevo,
                       a.motivo,
                       a.id_criador_solicitante,
                       uc.nombre AS criador_solicitante_nombre,
                       a.id_solicitud
                  FROM ' . $this->quoteIdentifier($this->table) . ' a
                  LEFT JOIN usuario u ON a.id_usuario = u.id_usuario
                  LEFT JOIN criador cr ON a.id_criador_solicitante = cr.id_criador
                  LEFT JOIN usuario uc ON cr.id_usuario = uc.id_usuario';
    }

    private function positiveInt(mixed $value): ?int {
        if (is_string($value)) {
            $value = trim($value);
        }
        if (!is_int($value) && !(is_string($value) && preg_match('/^[0-9]+$/', $value) === 1)) {
            return null;
        }

        $integer = (int) $value;

        return $integer > 0 ? $integer : null;
    }

    private function normalizeLimit(mixed $value): int {
        $parsed = $this->positiveInt($value);
        if ($parsed === null) {
            return self::DEFAULT_LIMIT;
        }

        return min($parsed, self::MAX_LIMIT);
    }

    private function normalizeOffset(mixed $value): int {
        if (is_string($value)) {
            $value = trim($value);
        }
        if (!is_int($value) && !(is_string($value) && preg_match('/^[0-9]+$/', $value) === 1)) {
            return 0;
        }

        return max(0, (int) $value);
    }
}
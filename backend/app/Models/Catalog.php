<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

/**
 * Catálogos de solo lectura del esquema v7.1.
 *
 * Expone club, variedad (nomenclador oficial) y mutación. No hay escritura:
 * la carga administrativa del nomenclador (SRS-RF010), de siglas de club
 * (SRS-RF011) y de mutaciones (SRS-RF027) se resuelve en otro flujo.
 *
 * `variedad.sexo` es una columna generada por la BD a partir de MACHO/HEMBRA
 * en el nombre (SRS-RF009); se devuelve, nunca se escribe desde PHP.
 */
class Catalog extends BaseModel {
    protected string $table = 'variedad';
    protected string $primaryKey = 'id_variedad';

    /**
     * Siglas de club disponibles para el anillo (SRS-RF002, SRS-RF011).
     *
     * @return array<int, array<string, mixed>>
     */
    public function clubes(): array {
        return $this->fetchAll(
            'SELECT id_club, sigla FROM club ORDER BY sigla ASC, id_club ASC'
        );
    }

    /**
     * Variedades del nomenclador con filtros opcionales.
     *
     * Filtros admitidos: buscar (código o nombre), codigo (exacto),
     * tipo (CC/CP) y sexo (M/H, calculado por la BD).
     *
     * @param array<string, mixed> $filters
     * @return array<int, array<string, mixed>>
     */
    public function variedades(array $filters = []): array {
        [$conditions, $params] = $this->variedadConditions($filters);

        $sql = $this->variedadSelect();
        if ($conditions !== []) {
            $sql .= ' WHERE ' . implode(' AND ', $conditions);
        }
        $sql .= ' ORDER BY codigo ASC, id_variedad ASC';

        return $this->fetchAll($sql, $params);
    }

    /**
     * Detalle de una variedad por su ID.
     *
     * @return array<string, mixed>|null
     */
    public function variedadPorId(int $id): ?array {
        return $this->fetch(
            $this->variedadSelect() . ' WHERE id_variedad = :id_variedad LIMIT 1',
            ['id_variedad' => $id]
        );
    }

    /**
     * Detalle de una variedad por código exacto del nomenclador (SRS-RF008).
     *
     * @return array<string, mixed>|null
     */
    public function variedadPorCodigo(string $codigo): ?array {
        return $this->fetch(
            $this->variedadSelect() . ' WHERE codigo = :codigo LIMIT 1',
            ['codigo' => $codigo]
        );
    }

    /**
     * Catálogo de mutaciones para el simulador (SRS-RF025, SRS-RF027).
     *
     * @return array<int, array<string, mixed>>
     */
    public function mutaciones(): array {
        return $this->fetchAll(
            'SELECT id_mutacion, nombre, tipo_herencia
               FROM mutacion
              ORDER BY nombre ASC, id_mutacion ASC'
        );
    }

    /**
     * Paquete completo para cargar los desplegables de una sola vez.
     *
     * @return array<string, array<int, array<string, mixed>>>
     */
    public function todos(): array {
        return [
            'clubes'     => $this->clubes(),
            'variedades' => $this->variedades(),
            'mutaciones' => $this->mutaciones(),
        ];
    }

    private function variedadSelect(): string {
        return 'SELECT id_variedad, codigo, nombre, tipo, serie, sexo FROM variedad';
    }

    /**
     * Construye condiciones con parámetros ligados; los nombres de columna
     * son fijos y nunca vienen del cliente.
     *
     * @param array<string, mixed> $filters
     * @return array{0: array<int, string>, 1: array<string, mixed>}
     */
    private function variedadConditions(array $filters): array {
        $conditions = [];
        $params = [];

        $codigo = $this->textValue($filters['codigo'] ?? null);
        if ($codigo !== null) {
            $conditions[] = 'codigo = :codigo';
            $params['codigo'] = $codigo;
        }

        $tipo = $this->textValue($filters['tipo'] ?? null);
        if ($tipo !== null) {
            $conditions[] = 'tipo = :tipo';
            $params['tipo'] = $tipo;
        }

        $sexo = $this->textValue($filters['sexo'] ?? null);
        if ($sexo !== null) {
            $conditions[] = 'sexo = :sexo';
            $params['sexo'] = $sexo;
        }

        $buscar = $this->textValue($filters['buscar'] ?? null);
        if ($buscar !== null) {
            // Con prepares nativos no se puede repetir el mismo parámetro.
            $conditions[] = '(codigo ILIKE :buscar_codigo OR nombre ILIKE :buscar_nombre)';
            $params['buscar_codigo'] = '%' . $buscar . '%';
            $params['buscar_nombre'] = '%' . $buscar . '%';
        }

        return [$conditions, $params];
    }

    private function textValue(mixed $value): ?string {
        if (!is_scalar($value)) {
            return null;
        }

        $text = trim((string) $value);

        return $text === '' ? null : $text;
    }
}

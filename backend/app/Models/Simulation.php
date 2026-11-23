<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use PDOException;

/**
 * Modelo para las tablas "simulacion" y "simulacion_resultado" del esquema v7.1.
 */
class Simulation extends BaseModel {
    public const ERROR_INVALID_DATA = 'invalid_data';
    public const ERROR_INVALID_REFERENCE = 'invalid_reference';
    public const ERROR_NOT_FOUND = 'not_found';
    public const ERROR_CONFLICT = 'conflict';

    private const VALID_GENOTYPES = ['visual', 'portador', 'sin factor'];

    protected string $table = 'simulacion';
    protected string $primaryKey = 'id_simulacion';

    /**
     * Busca una simulación por su clave primaria junto con sus resultados y datos relacionados.
     *
     * @return array<string, mixed>|null
     */
    public function findDetailed(int $id_simulacion): ?array {
        $sql = $this->detailedSelect()
            . ' WHERE s.id_simulacion = :id_simulacion'
            . ' LIMIT 1';

        $simulation = $this->fetch($sql, ['id_simulacion' => $id_simulacion]);
        if ($simulation === null) {
            return null;
        }

        $simulation['resultados'] = $this->fetchResultsForSimulation($id_simulacion);

        return $simulation;
    }

    /**
     * Lista las simulaciones pertenecientes al criadero indicado con filtros opcionales.
     *
     * @param array<string, mixed> $filters
     * @return array<int, array<string, mixed>>
     */
    public function findAllForBreeder(int $id_criador, array $filters = []): array {
        $where = ['s.id_criador = :id_criador'];
        $params = ['id_criador' => $id_criador];

        foreach (['id_mutacion', 'id_macho', 'id_hembra'] as $intField) {
            $parsed = $this->positiveInt($filters[$intField] ?? null);
            if ($parsed !== null) {
                $where[] = 's.' . $intField . ' = :' . $intField;
                $params[$intField] = $parsed;
            }
        }

        $sql = $this->detailedSelect()
            . ' WHERE ' . implode(' AND ', $where)
            . ' ORDER BY s.fecha DESC, s.id_simulacion DESC';

        $simulations = $this->fetchAll($sql, $params);
        if ($simulations === []) {
            return [];
        }

        $ids = array_map(static fn (array $row): int => (int) $row['id_simulacion'], $simulations);
        $resultsBySimulation = $this->fetchResultsForSimulations($ids);

        foreach ($simulations as &$simulation) {
            $simId = (int) $simulation['id_simulacion'];
            $simulation['resultados'] = $resultsBySimulation[$simId] ?? [];
        }
        unset($simulation);

        return $simulations;
    }

    /**
     * Calcula y registra una simulación y sus filas en "simulacion_resultado"
     * dentro de una transacción para el criadero autenticado.
     *
     * @param array<string, mixed> $data
     * @return int|string ID generado o código de error de dominio.
     */
    public function simulateAndCreate(array $data, int $id_criador): int|string {
        $id_macho = $this->positiveInt($data['id_macho'] ?? null);
        $id_hembra = $this->positiveInt($data['id_hembra'] ?? null);
        $id_mutacion = $this->positiveInt($data['id_mutacion'] ?? null);

        if ($id_macho === null || $id_hembra === null || $id_mutacion === null || $id_macho === $id_hembra) {
            return self::ERROR_INVALID_DATA;
        }

        $genotipoMacho = $this->normalizeGenotype($data['genotipo_macho'] ?? null);
        $genotipoHembra = $this->normalizeGenotype($data['genotipo_hembra'] ?? null);

        if ($genotipoMacho === null || $genotipoHembra === null) {
            return self::ERROR_INVALID_DATA;
        }

        // Verifica existencia y pertenencia de macho y hembra al criadero.
        $male = $this->fetch(
            'SELECT id_canario, id_criador, sexo FROM canario WHERE id_canario = :id LIMIT 1',
            ['id' => $id_macho]
        );
        $female = $this->fetch(
            'SELECT id_canario, id_criador, sexo FROM canario WHERE id_canario = :id LIMIT 1',
            ['id' => $id_hembra]
        );
        if ($male === null || $female === null) {
            return self::ERROR_INVALID_REFERENCE;
        }
        if ((int) $male['id_criador'] !== $id_criador || (int) $female['id_criador'] !== $id_criador) {
            return self::ERROR_INVALID_REFERENCE;
        }
        if ((string) $male['sexo'] !== 'M' || (string) $female['sexo'] !== 'H') {
            return self::ERROR_INVALID_DATA;
        }

        // Verifica existencia de la mutación en el catálogo.
        $mutation = $this->fetch(
            'SELECT id_mutacion, tipo_herencia FROM mutacion WHERE id_mutacion = :id LIMIT 1',
            ['id' => $id_mutacion]
        );
        if ($mutation === null) {
            return self::ERROR_INVALID_REFERENCE;
        }

        $tipoHerencia = mb_strtolower(trim((string) $mutation['tipo_herencia']), 'UTF-8');
        if ($tipoHerencia === 'ligada al sexo recesiva' && $genotipoHembra === 'portador') {
            return self::ERROR_INVALID_DATA;
        }

        $resultados = $this->calculateProbabilities(
            $tipoHerencia,
            $genotipoMacho,
            $genotipoHembra
        );

        $pdo = $this->db->getConnection();
        $pdo->beginTransaction();

        try {
            $idSimulacion = $this->insert([
                'id_criador'      => $id_criador,
                'id_macho'        => $id_macho,
                'id_hembra'       => $id_hembra,
                'id_mutacion'     => $id_mutacion,
                'genotipo_macho'  => $genotipoMacho,
                'genotipo_hembra' => $genotipoHembra,
            ]);

            if ($idSimulacion === null) {
                $pdo->rollBack();
                return self::ERROR_INVALID_DATA;
            }

            $stmt = $pdo->prepare(
                'INSERT INTO simulacion_resultado (id_simulacion, sexo_cria, genotipo_resultado, probabilidad)
                 VALUES (:id_simulacion, :sexo_cria, :genotipo_resultado, :probabilidad)'
            );

            foreach ($resultados as $item) {
                $stmt->execute([
                    'id_simulacion'      => $idSimulacion,
                    'sexo_cria'          => $item['sexo_cria'],
                    'genotipo_resultado' => $item['genotipo_resultado'],
                    'probabilidad'       => number_format((float) $item['probabilidad'], 5, '.', ''),
                ]);
            }

            $pdo->commit();

            return $idSimulacion;
        } catch (PDOException $exception) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            return $this->mapWriteException($exception);
        }
    }

    /**
     * Calcula las probabilidades (entre 0 y 1) para "simulacion_resultado"
     * según el tipo de herencia ("autosómica recesiva" o "ligada al sexo recesiva").
     *
     * @return array<int, array{sexo_cria: ?string, genotipo_resultado: string, probabilidad: float}>
     */
    public function calculateProbabilities(
        string $tipoHerencia,
        string $genotipoMacho,
        string $genotipoHembra
    ): array {
        $normalized = mb_strtolower(trim($tipoHerencia), 'UTF-8');

        if ($normalized === 'ligada al sexo recesiva') {
            // Macho ZZ: 'visual' = (m, m), 'portador' = (+, m), 'sin factor' = (+, +)
            $maleGametes = match ($genotipoMacho) {
                'visual'     => ['m', 'm'],
                'portador'   => ['+', 'm'],
                default      => ['+', '+'],
            };
            // Hembra ZW: 'visual' = (m, W), 'sin factor' = (+, W)
            $femaleGametes = ($genotipoHembra === 'visual') ? ['m', 'W'] : ['+', 'W'];

            $counts = [];
            foreach ($maleGametes as $m) {
                foreach ($femaleGametes as $f) {
                    if ($f === 'W') {
                        // Cría hembra (ZW)
                        $sexo = 'H';
                        $geno = ($m === 'm') ? 'visual' : 'sin factor';
                    } else {
                        // Cría macho (ZZ)
                        $sexo = 'M';
                        if ($m === 'm' && $f === 'm') {
                            $geno = 'visual';
                        } elseif ($m === 'm' || $f === 'm') {
                            $geno = 'portador';
                        } else {
                            $geno = 'sin factor';
                        }
                    }

                    $key = $sexo . '|' . $geno;
                    $counts[$key] = ($counts[$key] ?? 0) + 1;
                }
            }

            $total = count($maleGametes) * count($femaleGametes);
            $rows = [];
            foreach ($counts as $key => $count) {
                [$sexo, $geno] = explode('|', $key, 2);
                $rows[] = [
                    'sexo_cria'          => $sexo,
                    'genotipo_resultado' => $geno,
                    'probabilidad'       => round($count / $total, 5),
                ];
            }

            return $rows;
        }

        // Herencia autosómica recesiva: sexo_cria = null
        $maleAlleles = match ($genotipoMacho) {
            'visual'     => ['m', 'm'],
            'portador'   => ['+', 'm'],
            default      => ['+', '+'],
        };
        $femaleAlleles = match ($genotipoHembra) {
            'visual'     => ['m', 'm'],
            'portador'   => ['+', 'm'],
            default      => ['+', '+'],
        };

        $counts = [];
        foreach ($maleAlleles as $m) {
            foreach ($femaleAlleles as $f) {
                if ($m === 'm' && $f === 'm') {
                    $geno = 'visual';
                } elseif ($m === 'm' || $f === 'm') {
                    $geno = 'portador';
                } else {
                    $geno = 'sin factor';
                }

                $counts[$geno] = ($counts[$geno] ?? 0) + 1;
            }
        }

        $total = count($maleAlleles) * count($femaleAlleles);
        $rows = [];
        foreach ($counts as $geno => $count) {
            $rows[] = [
                'sexo_cria'          => null,
                'genotipo_resultado' => $geno,
                'probabilidad'       => round($count / $total, 5),
            ];
        }

        return $rows;
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function fetchResultsForSimulation(int $id_simulacion): array {
        $rows = $this->fetchAll(
            'SELECT id_resultado, id_simulacion, sexo_cria, genotipo_resultado, probabilidad
               FROM simulacion_resultado
              WHERE id_simulacion = :id_simulacion
              ORDER BY id_resultado ASC',
            ['id_simulacion' => $id_simulacion]
        );

        return array_map(static function (array $row): array {
            $row['probabilidad'] = (float) $row['probabilidad'];
            return $row;
        }, $rows);
    }

    /**
     * @param array<int, int> $ids
     * @return array<int, array<int, array<string, mixed>>>
     */
    private function fetchResultsForSimulations(array $ids): array {
        if ($ids === []) {
            return [];
        }

        $placeholders = [];
        $params = [];
        foreach (array_values($ids) as $index => $id) {
            $key = ':id_' . $index;
            $placeholders[] = $key;
            $params['id_' . $index] = $id;
        }

        $sql = 'SELECT id_resultado, id_simulacion, sexo_cria, genotipo_resultado, probabilidad
                  FROM simulacion_resultado
                 WHERE id_simulacion IN (' . implode(', ', $placeholders) . ')
                 ORDER BY id_simulacion ASC, id_resultado ASC';

        $rows = $this->fetchAll($sql, $params);
        $grouped = [];
        foreach ($rows as $row) {
            $simId = (int) $row['id_simulacion'];
            $row['probabilidad'] = (float) $row['probabilidad'];
            $grouped[$simId][] = $row;
        }

        return $grouped;
    }

    private function detailedSelect(): string {
        return 'SELECT s.id_simulacion, s.id_criador, s.id_macho, s.id_hembra,
                       s.id_mutacion, s.genotipo_macho, s.genotipo_hembra, s.fecha,
                       m.nombre AS mutacion_nombre, m.tipo_herencia,
                       cm.anillo AS anillo_macho,
                       ch.anillo AS anillo_hembra
                  FROM ' . $this->quoteIdentifier($this->table) . ' s
                  INNER JOIN mutacion m ON m.id_mutacion = s.id_mutacion
                  INNER JOIN canario cm ON cm.id_canario = s.id_macho
                  INNER JOIN canario ch ON ch.id_canario = s.id_hembra';
    }

    private function normalizeGenotype(mixed $value): ?string {
        if (!is_string($value)) {
            return null;
        }
        $normalized = strtolower(trim($value));

        return in_array($normalized, self::VALID_GENOTYPES, true) ? $normalized : null;
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

    private function mapWriteException(PDOException $exception): string {
        return match ((string) $exception->getCode()) {
            '23505' => self::ERROR_CONFLICT,
            '23503' => self::ERROR_INVALID_REFERENCE,
            '23502', '23514', '22P02', '22007' => self::ERROR_INVALID_DATA,
            'P0001' => self::ERROR_CONFLICT,
            default => throw $exception,
        };
    }
}

<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use CanariApp\Backend\Helpers\AuditHelper;
use PDO;
use PDOException;
use RuntimeException;
use Throwable;

/**
 * Modelo para la tabla "cria" y su relación con "nidada", "cruce", "pareja",
 * "canario" y "mutacion".
 *
 * Aplica el aislamiento por criadero mediante la pareja asociada a la nidada
 * y la propiedad del ejemplar en "canario".
 */
class Chick extends BaseModel {
    public const ERROR_INVALID_DATA = 'invalid_data';
    public const ERROR_INVALID_REFERENCE = 'invalid_reference';
    public const ERROR_NOT_FOUND = 'not_found';
    public const ERROR_CONFLICT = 'conflict';
    public const ERROR_CONFLICT_ANILLO = 'conflict_anillo';

    protected string $table = 'cria';
    protected string $primaryKey = 'id_cria';

    /**
     * Campos permitidos al crear una cría asociada a un canario existente.
     *
     * @var array<int, string>
     */
    private const CREATABLE_FIELDS = [
        'id_nidada',
        'id_canario',
        'factor_genetico',
        'reservada',
    ];

    /**
     * Campos permitidos al actualizar una cría.
     *
     * @var array<int, string>
     */
    private const UPDATABLE_FIELDS = [
        'factor_genetico',
        'reservada',
    ];

    /**
     * Busca una cría por su clave primaria con información de nidada, canario y mutación.
     *
     * @return array<string, mixed>|null
     */
    public function findDetailed(int $id_cria): ?array {
        $sql = $this->detailedSelect()
            . ' WHERE cr.id_cria = :id_cria'
            . ' LIMIT 1';

        return $this->fetch($sql, ['id_cria' => $id_cria]);
    }

    /**
     * Lista las crías pertenecientes al criadero indicado con filtros opcionales.
     *
     * @param array<string, mixed> $filters
     * @return array<int, array<string, mixed>>
     */
    public function findAllForBreeder(int $id_criador, array $filters = []): array {
        $where = ['p.id_criador = :id_criador'];
        $params = ['id_criador' => $id_criador];

        foreach (['id_nidada', 'id_canario', 'factor_genetico'] as $intField) {
            $parsed = $this->positiveInt($filters[$intField] ?? null);
            if ($parsed !== null) {
                $where[] = 'cr.' . $intField . ' = :' . $intField;
                $params[$intField] = $parsed;
            }
        }

        if (array_key_exists('reservada', $filters) && $filters['reservada'] !== null && $filters['reservada'] !== '') {
            $boolVal = $this->parseBool($filters['reservada']);
            if ($boolVal !== null) {
                $where[] = 'cr.reservada = :reservada';
                $params['reservada'] = $boolVal ? 'true' : 'false';
            }
        }

        $sql = $this->detailedSelect()
            . ' WHERE ' . implode(' AND ', $where)
            . ' ORDER BY cr.id_cria DESC';

        return $this->fetchAll($sql, $params);
    }

    /**
     * Lista las crías de una nidada perteneciente al criadero indicado.
     *
     * @return array<int, array<string, mixed>>
     */
    public function findAllForNest(int $id_nidada, int $id_criador): array {
        return $this->findAllForBreeder($id_criador, ['id_nidada' => $id_nidada]);
    }

    /**
     * Verifica si una cría pertenece al criadero indicado.
     */
    public function belongsToBreeder(int $id_cria, int $id_criador): bool {
        $sql = 'SELECT 1
                  FROM ' . $this->quoteIdentifier($this->table) . ' cr
                  INNER JOIN nidada n ON n.id_nidada = cr.id_nidada
                  INNER JOIN cruce c ON c.id_cruce = n.id_cruce
                  INNER JOIN pareja p ON p.id_pareja = c.id_pareja
                 WHERE cr.id_cria = :id_cria
                   AND p.id_criador = :id_criador
                 LIMIT 1';

        return $this->fetch($sql, [
            'id_cria'    => $id_cria,
            'id_criador' => $id_criador,
        ]) !== null;
    }

    /**
     * Crea el ejemplar en "canario" (permitiendo sexo y id_variedad en NULL según RF019/RF020)
     * y su fila asociada en "cria" dentro de una única transacción atómica.
     *
     * Cumple el trigger diferido trg_validar_pendiente_cria de PostgreSQL v7.1.
     *
     * @param array<string, mixed> $canaryData
     * @param array<string, mixed> $chickData
     * @return int|string ID de la cría creada o código de error de dominio.
     */
    public function createWithCanaryForBreeder(
        array $canaryData,
        array $chickData,
        int $idCriador,
        int $userId
    ): int|string {
        $idNidada = $this->positiveInt($chickData['id_nidada'] ?? null);
        if ($idNidada === null) {
            return self::ERROR_INVALID_DATA;
        }

        $anillo = is_scalar($canaryData['anillo'] ?? null) ? trim((string) $canaryData['anillo']) : '';
        $numeroSocio = is_scalar($canaryData['numero_socio'] ?? null) ? trim((string) $canaryData['numero_socio']) : '';
        $idClub = $this->positiveInt($canaryData['id_club'] ?? null);
        $temporada = $this->positiveInt($canaryData['temporada'] ?? null);
        $maxSeason = (int) date('Y');

        if (
            preg_match('/^[0-9]{1,6}$/', $anillo) !== 1
            || preg_match('/^[0-9]{1,5}$/', $numeroSocio) !== 1
            || $idClub === null
            || $temporada === null
            || $temporada < 1000
            || $temporada > $maxSeason
        ) {
            return self::ERROR_INVALID_DATA;
        }

        $sexo = null;
        if (array_key_exists('sexo', $canaryData) && $canaryData['sexo'] !== null && $canaryData['sexo'] !== '') {
            if (!is_string($canaryData['sexo']) || !in_array($canaryData['sexo'], ['M', 'H'], true)) {
                return self::ERROR_INVALID_DATA;
            }
            $sexo = $canaryData['sexo'];
        }

        $idVariedad = null;
        if (array_key_exists('id_variedad', $canaryData) && $canaryData['id_variedad'] !== null && $canaryData['id_variedad'] !== '') {
            $parsedVariedad = $this->positiveInt($canaryData['id_variedad']);
            if ($parsedVariedad === null) {
                return self::ERROR_INVALID_DATA;
            }
            $idVariedad = $parsedVariedad;
        }

        $factorGenetico = null;
        if (array_key_exists('factor_genetico', $chickData) && $chickData['factor_genetico'] !== null && $chickData['factor_genetico'] !== '') {
            $parsedFactor = $this->positiveInt($chickData['factor_genetico']);
            if ($parsedFactor === null) {
                return self::ERROR_INVALID_DATA;
            }
            $factorGenetico = $parsedFactor;
        }

        $reservada = false;
        if (array_key_exists('reservada', $chickData) && $chickData['reservada'] !== null && $chickData['reservada'] !== '') {
            $parsedBool = $this->parseBool($chickData['reservada']);
            if ($parsedBool === null) {
                return self::ERROR_INVALID_DATA;
            }
            $reservada = $parsedBool;
        }

        try {
            $this->beginTransaction();

            $nest = $this->fetch(
                'SELECT n.id_nidada
                   FROM nidada n
                   INNER JOIN cruce c ON c.id_cruce = n.id_cruce
                   INNER JOIN pareja p ON p.id_pareja = c.id_pareja
                  WHERE n.id_nidada = :id_nidada
                    AND p.id_criador = :id_criador
                  LIMIT 1',
                ['id_nidada' => $idNidada, 'id_criador' => $idCriador]
            );

            if ($nest === null) {
                $this->rollBack();

                return self::ERROR_NOT_FOUND;
            }

            $ringConflict = $this->fetch(
                'SELECT 1
                   FROM canario
                  WHERE anillo::INT = :anillo
                    AND id_club = :id_club
                    AND numero_socio::INT = :numero_socio
                    AND temporada = :temporada
                  LIMIT 1',
                [
                    'anillo'       => (int) $anillo,
                    'id_club'      => $idClub,
                    'numero_socio' => (int) $numeroSocio,
                    'temporada'    => $temporada,
                ]
            );

            if ($ringConflict !== null) {
                $this->rollBack();

                return self::ERROR_CONFLICT_ANILLO;
            }

            $canaryPayload = [
                'anillo'       => $anillo,
                'id_club'      => $idClub,
                'numero_socio' => $numeroSocio,
                'temporada'    => $temporada,
                'sexo'         => $sexo,
                'id_variedad'  => $idVariedad,
                'id_criador'   => $idCriador,
            ];

            $newCanaryId = AuditHelper::withoutAutoAudit(
                fn (): ?int => $this->insertInto('canario', $canaryPayload, 'id_canario')
            );

            if ($newCanaryId === null) {
                throw new RuntimeException('No se pudo obtener el ID del ejemplar creado para la cría.');
            }

            $chickPayload = [
                'id_nidada'       => $idNidada,
                'id_canario'      => $newCanaryId,
                'factor_genetico' => $factorGenetico,
                'reservada'       => $reservada,
            ];

            $newChickId = AuditHelper::withoutAutoAudit(
                fn (): ?int => $this->insertInto('cria', $chickPayload, 'id_cria')
            );

            if ($newChickId === null) {
                throw new RuntimeException('No se pudo obtener el ID de la cría creada.');
            }

            $conn = $this->getConnection();

            AuditHelper::log(
                action: 'insert',
                entity: 'canario',
                recordId: $newCanaryId,
                newValue: $canaryPayload,
                reason: 'Registro de ejemplar asociado a nueva cría',
                userId: $userId,
                db: $conn
            );

            AuditHelper::log(
                action: 'insert',
                entity: 'cria',
                recordId: $newChickId,
                newValue: $chickPayload,
                reason: 'Registro de nueva cría en nidada',
                userId: $userId,
                db: $conn
            );

            $this->commit();

            return $newChickId;
        } catch (PDOException $exception) {
            if ($this->getConnection()->inTransaction()) {
                $this->rollBack();
            }

            return $this->mapWriteException($exception, true);
        } catch (Throwable $exception) {
            if ($this->getConnection()->inTransaction()) {
                $this->rollBack();
            }
            throw $exception;
        }
    }

    /**
     * Registra una nueva cría asociada a una nidada y un canario ya existente del criadero.
     *
     * @param array<string, mixed> $data
     * @return int|string ID generado o código de error de dominio.
     */
    public function createForBreeder(array $data, int $id_criador): int|string {
        $payload = array_intersect_key($data, array_flip(self::CREATABLE_FIELDS));

        $id_nidada = $this->positiveInt($payload['id_nidada'] ?? null);
        $id_canario = $this->positiveInt($payload['id_canario'] ?? null);
        if ($id_nidada === null || $id_canario === null) {
            return self::ERROR_INVALID_DATA;
        }

        // Verifica que la nidada pertenezca al criadero autenticado.
        $nest = $this->fetch(
            'SELECT n.id_nidada, p.id_macho, p.id_hembra
               FROM nidada n
               INNER JOIN cruce c ON c.id_cruce = n.id_cruce
               INNER JOIN pareja p ON p.id_pareja = c.id_pareja
              WHERE n.id_nidada = :id_nidada
                AND p.id_criador = :id_criador
              LIMIT 1',
            ['id_nidada' => $id_nidada, 'id_criador' => $id_criador]
        );
        if ($nest === null) {
            return self::ERROR_NOT_FOUND;
        }

        // Verifica que el canario exista y pertenezca al mismo criadero.
        $canary = $this->fetch(
            'SELECT id_canario, id_criador
               FROM canario
              WHERE id_canario = :id_canario
              LIMIT 1',
            ['id_canario' => $id_canario]
        );
        if ($canary === null) {
            return self::ERROR_INVALID_REFERENCE;
        }
        if ((int) $canary['id_criador'] !== $id_criador) {
            return self::ERROR_INVALID_REFERENCE;
        }

        // Evita registrar como cría a uno de los progenitores de la pareja.
        if ($id_canario === (int) $nest['id_macho'] || $id_canario === (int) $nest['id_hembra']) {
            return self::ERROR_INVALID_DATA;
        }

        $factorGenetico = null;
        if (array_key_exists('factor_genetico', $payload) && $payload['factor_genetico'] !== null && $payload['factor_genetico'] !== '') {
            $parsedFactor = $this->positiveInt($payload['factor_genetico']);
            if ($parsedFactor === null) {
                return self::ERROR_INVALID_DATA;
            }
            $factorGenetico = $parsedFactor;
        }

        $reservada = false;
        if (array_key_exists('reservada', $payload) && $payload['reservada'] !== null && $payload['reservada'] !== '') {
            $parsedBool = $this->parseBool($payload['reservada']);
            if ($parsedBool === null) {
                return self::ERROR_INVALID_DATA;
            }
            $reservada = $parsedBool;
        }

        try {
            $id = $this->insertInto('cria', [
                'id_nidada'       => $id_nidada,
                'id_canario'      => $id_canario,
                'factor_genetico' => $factorGenetico,
                'reservada'       => $reservada,
            ], 'id_cria');
        } catch (PDOException $exception) {
            return $this->mapWriteException($exception);
        }

        return $id ?? self::ERROR_INVALID_DATA;
    }

    /**
     * Actualiza campos editables de una cría perteneciente al criadero indicado.
     *
     * @param array<string, mixed> $data
     * @return int|string Filas afectadas o código de error de dominio.
     */
    public function updateForBreeder(int $id_cria, array $data, int $id_criador): int|string {
        $payload = array_intersect_key($data, array_flip(self::UPDATABLE_FIELDS));
        if ($payload === []) {
            return $this->belongsToBreeder($id_cria, $id_criador) ? 0 : self::ERROR_NOT_FOUND;
        }

        if (!$this->belongsToBreeder($id_cria, $id_criador)) {
            return self::ERROR_NOT_FOUND;
        }

        $updates = [];

        if (array_key_exists('factor_genetico', $payload)) {
            if ($payload['factor_genetico'] === null || $payload['factor_genetico'] === '') {
                $updates['factor_genetico'] = null;
            } else {
                $parsedFactor = $this->positiveInt($payload['factor_genetico']);
                if ($parsedFactor === null) {
                    return self::ERROR_INVALID_DATA;
                }
                $updates['factor_genetico'] = $parsedFactor;
            }
        }

        if (array_key_exists('reservada', $payload)) {
            if ($payload['reservada'] === null || $payload['reservada'] === '') {
                return self::ERROR_INVALID_DATA;
            }
            $parsedBool = $this->parseBool($payload['reservada']);
            if ($parsedBool === null) {
                return self::ERROR_INVALID_DATA;
            }
            $updates['reservada'] = $parsedBool;
        }

        if ($updates === []) {
            return 0;
        }

        try {
            $setClauses = [];
            foreach (array_keys($updates) as $column) {
                $setClauses[] = $this->quoteIdentifier($column) . ' = :' . $column;
            }

            $sql = sprintf(
                'UPDATE %s SET %s WHERE id_cria = :id_cria',
                $this->quoteIdentifier($this->table),
                implode(', ', $setClauses)
            );

            $stmt = $this->getConnection()->prepare($sql);
            foreach ($updates as $column => $value) {
                $stmt->bindValue(':' . $column, $value, $this->pdoParamType($value));
            }
            $stmt->bindValue(':id_cria', $id_cria, PDO::PARAM_INT);
            $stmt->execute();

            return $stmt->rowCount();
        } catch (PDOException $exception) {
            return $this->mapWriteException($exception);
        }
    }

    /**
     * Inserta un registro en la tabla indicada devolviendo su clave primaria mediante RETURNING.
     *
     * @param array<string, mixed> $data
     */
    private function insertInto(string $table, array $data, string $returningColumn): ?int {
        $columns = array_keys($data);
        $quotedColumns = array_map(fn (string $col): string => $this->quoteIdentifier($col), $columns);
        $placeholders = array_map(fn (string $col): string => ':' . $col, $columns);

        $sql = sprintf(
            'INSERT INTO %s (%s) VALUES (%s) RETURNING %s',
            $this->quoteIdentifier($table),
            implode(', ', $quotedColumns),
            implode(', ', $placeholders),
            $this->quoteIdentifier($returningColumn)
        );

        $stmt = $this->getConnection()->prepare($sql);
        foreach ($data as $column => $value) {
            $stmt->bindValue(':' . $column, $value, $this->pdoParamType($value));
        }

        $stmt->execute();
        $id = $stmt->fetchColumn();

        return $id !== false ? (int) $id : null;
    }

    private function pdoParamType(mixed $value): int {
        return match (true) {
            is_bool($value) => PDO::PARAM_BOOL,
            is_int($value)  => PDO::PARAM_INT,
            $value === null => PDO::PARAM_NULL,
            default         => PDO::PARAM_STR,
        };
    }

    /**
     * Consulta SELECT base con datos de cría, nidada, canario, progenitores y mutación.
     */
    private function detailedSelect(): string {
        return 'SELECT cr.id_cria, cr.id_nidada, cr.id_canario,
                       cr.factor_genetico, cr.es_portadora, cr.reservada,
                       p.id_criador, p.id_pareja, p.id_macho, p.id_hembra,
                       cm.anillo AS anillo_macho,
                       ch.anillo AS anillo_hembra,
                       n.id_cruce, n.fecha_nacimiento,
                       c.anillo, c.temporada, c.sexo, c.id_variedad,
                       m.nombre AS mutacion_nombre
                  FROM ' . $this->quoteIdentifier($this->table) . ' cr
                  INNER JOIN nidada n ON n.id_nidada = cr.id_nidada
                  INNER JOIN cruce c_cr ON c_cr.id_cruce = n.id_cruce
                  INNER JOIN pareja p ON p.id_pareja = c_cr.id_pareja
                  INNER JOIN canario cm ON cm.id_canario = p.id_macho
                  INNER JOIN canario ch ON ch.id_canario = p.id_hembra
                  INNER JOIN canario c ON c.id_canario = cr.id_canario
                  LEFT JOIN mutacion m ON m.id_mutacion = cr.factor_genetico';
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

    private function parseBool(mixed $value): ?bool {
        if (is_bool($value)) {
            return $value;
        }
        if (is_int($value)) {
            return match ($value) {
                1 => true,
                0 => false,
                default => null,
            };
        }
        if (is_string($value)) {
            $normalized = strtolower(trim($value));
            return match ($normalized) {
                '1', 'true' => true,
                '0', 'false' => false,
                default => null,
            };
        }

        return null;
    }

    /**
     * Traduce códigos SQLSTATE de PostgreSQL a códigos de error de dominio.
     */
    private function mapWriteException(PDOException $exception, bool $creatingCanary = false): string {
        $message = $exception->getMessage();

        if ($creatingCanary && (string) $exception->getCode() === '23505' && str_contains($message, 'uq_anillo')) {
            return self::ERROR_CONFLICT_ANILLO;
        }

        return match ((string) $exception->getCode()) {
            '23505' => self::ERROR_CONFLICT,
            '23503' => self::ERROR_INVALID_REFERENCE,
            '23502', '23514', '22P02', '22007' => self::ERROR_INVALID_DATA,
            'P0001' => self::ERROR_INVALID_DATA,
            default => throw $exception,
        };
    }
}
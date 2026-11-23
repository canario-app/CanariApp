<?php

declare(strict_types=1);

namespace CanariApp\Backend\Models;

use CanariApp\Backend\Helpers\AuditHelper;
use PDOException;
use RuntimeException;
use Throwable;

/**
 * Modelo administrativo para la carga y mantenimiento de catálogos oficiales:
 *  - variedad (nomenclador oficial, SRS-RF010)
 *  - club (siglas de clubes, SRS-RF011)
 *  - mutacion (catálogo genético, SRS-RF027)
 */
class CatalogAdmin extends BaseModel {
    protected string $table = 'variedad';
    protected string $primaryKey = 'id_variedad';

    public const ALLOWED_VARIETY_TYPES = ['CC', 'CP'];
    public const ALLOWED_INHERITANCE_TYPES = [
        'autosómica recesiva',
        'ligada al sexo recesiva',
    ];

    public const ERROR_INVALID_DATA = 'invalid_data';
    public const ERROR_DUPLICATE_CLUB = 'duplicate_club';
    public const ERROR_DUPLICATE_MUTATION = 'duplicate_mutation';

    /**
     * Carga o actualiza variedades del nomenclador oficial en una transacción (SRS-RF010).
     *
     * Si el código ya existe, actualiza nombre, tipo y serie; si el cambio de nombre
     * modifica el sexo derivado en la BD, trg_marcar_revision actualiza requiere_revision
     * en los ejemplares afectados sin modificarlos ni eliminarlos.
     *
     * @param array<int, array{codigo: string, nombre: string, tipo: string, serie: ?string}> $items
     * @return array{
     *     procesadas: int,
     *     insertadas: int,
     *     actualizadas: int,
     *     ejemplares_requieren_revision: int,
     *     items: array<int, array<string, mixed>>
     * }|string
     */
    public function loadNomenclador(array $items, int $adminUserId, string $reason): array|string {
        if ($items === []) {
            return self::ERROR_INVALID_DATA;
        }

        $insertedCount = 0;
        $updatedCount = 0;
        $processedCodes = [];

        try {
            $this->beginTransaction();

            AuditHelper::withoutAutoAudit(function () use (
                $items,
                &$insertedCount,
                &$updatedCount,
                &$processedCodes
            ): void {
                foreach ($items as $item) {
                    $codigo = trim((string) ($item['codigo'] ?? ''));
                    $nombre = trim((string) ($item['nombre'] ?? ''));
                    $tipo = strtoupper(trim((string) ($item['tipo'] ?? '')));
                    $serieRaw = $item['serie'] ?? null;
                    $serie = is_string($serieRaw) && trim($serieRaw) !== '' ? trim($serieRaw) : null;

                    if (
                        $codigo === '' || mb_strlen($codigo) > 10
                        || $nombre === '' || mb_strlen($nombre) > 150
                        || !in_array($tipo, self::ALLOWED_VARIETY_TYPES, true)
                        || ($serie !== null && mb_strlen($serie) > 50)
                    ) {
                        throw new RuntimeException(self::ERROR_INVALID_DATA);
                    }

                    $existing = $this->fetch(
                        'SELECT id_variedad, codigo, nombre, tipo, serie
                           FROM variedad
                          WHERE codigo = :codigo
                          LIMIT 1',
                        ['codigo' => $codigo]
                    );

                    if ($existing === null) {
                        $this->execute(
                            'INSERT INTO variedad (codigo, nombre, tipo, serie)
                             VALUES (:codigo, :nombre, :tipo, :serie)',
                            [
                                'codigo' => $codigo,
                                'nombre' => $nombre,
                                'tipo'   => $tipo,
                                'serie'  => $serie,
                            ]
                        );
                        $insertedCount++;
                    } else {
                        $this->execute(
                            'UPDATE variedad
                                SET nombre = :nombre,
                                    tipo   = :tipo,
                                    serie  = :serie
                              WHERE id_variedad = :id_variedad',
                            [
                                'nombre'      => $nombre,
                                'tipo'        => $tipo,
                                'serie'       => $serie,
                                'id_variedad' => (int) $existing['id_variedad'],
                            ]
                        );
                        $updatedCount++;
                    }

                    $processedCodes[] = $codigo;
                }
            });

            $revisionRow = $this->fetch(
                'SELECT COUNT(*) AS total FROM canario WHERE requiere_revision = TRUE'
            );
            $revisionCount = (int) ($revisionRow['total'] ?? 0);

            $uniqueCodes = array_values(array_unique($processedCodes));
            $placeholders = [];
            $params = [];
            foreach ($uniqueCodes as $idx => $code) {
                $key = 'code_' . $idx;
                $placeholders[] = ':' . $key;
                $params[$key] = $code;
            }

            $savedItems = $this->fetchAll(
                sprintf(
                    'SELECT id_variedad, codigo, nombre, tipo, serie, sexo
                       FROM variedad
                      WHERE codigo IN (%s)
                      ORDER BY codigo ASC',
                    implode(', ', $placeholders)
                ),
                $params
            );

            AuditHelper::log(
                action: 'insert',
                entity: 'variedad',
                recordId: null,
                newValue: [
                    'procesadas'                    => count($items),
                    'insertadas'                    => $insertedCount,
                    'actualizadas'                  => $updatedCount,
                    'ejemplares_requieren_revision' => $revisionCount,
                ],
                reason: $reason,
                userId: $adminUserId,
                db: $this->getConnection()
            );

            $this->commit();
        } catch (RuntimeException $exception) {
            if ($this->getConnection()->inTransaction()) {
                $this->rollBack();
            }

            if ($exception->getMessage() === self::ERROR_INVALID_DATA) {
                return self::ERROR_INVALID_DATA;
            }

            throw $exception;
        } catch (PDOException $exception) {
            if ($this->getConnection()->inTransaction()) {
                $this->rollBack();
            }

            return $this->mapWriteException($exception);
        } catch (Throwable $exception) {
            if ($this->getConnection()->inTransaction()) {
                $this->rollBack();
            }
            throw $exception;
        }

        return [
            'procesadas'                    => count($items),
            'insertadas'                    => $insertedCount,
            'actualizadas'                  => $updatedCount,
            'ejemplares_requieren_revision' => $revisionCount,
            'items'                         => $savedItems,
        ];
    }

    /**
     * Registra uno o varios clubes oficiales (SRS-RF011).
     *
     * @param array<int, string> $siglas
     * @return array<int, array<string, mixed>>|string
     */
    public function registerClubs(array $siglas, int $adminUserId, string $reason): array|string {
        if ($siglas === []) {
            return self::ERROR_INVALID_DATA;
        }

        $created = [];

        try {
            $this->beginTransaction();

            AuditHelper::withoutAutoAudit(function () use (
                $siglas,
                $adminUserId,
                $reason,
                &$created
            ): void {
                foreach ($siglas as $rawSigla) {
                    $sigla = strtoupper(trim($rawSigla));
                    if (preg_match('/^[A-Z]{2,6}$/', $sigla) !== 1) {
                        throw new RuntimeException(self::ERROR_INVALID_DATA);
                    }

                    $row = $this->fetch(
                        'INSERT INTO club (sigla)
                         VALUES (:sigla)
                         RETURNING id_club, sigla',
                        ['sigla' => $sigla]
                    );

                    if ($row === null) {
                        throw new RuntimeException('No se pudo registrar la sigla del club.');
                    }

                    $idClub = (int) $row['id_club'];
                    $created[] = [
                        'id_club' => $idClub,
                        'sigla'   => (string) $row['sigla'],
                    ];

                    AuditHelper::log(
                        action: 'insert',
                        entity: 'club',
                        recordId: $idClub,
                        newValue: ['sigla' => $sigla],
                        reason: $reason,
                        userId: $adminUserId,
                        db: $this->getConnection()
                    );
                }
            });

            $this->commit();
        } catch (RuntimeException $exception) {
            if ($this->getConnection()->inTransaction()) {
                $this->rollBack();
            }

            if ($exception->getMessage() === self::ERROR_INVALID_DATA) {
                return self::ERROR_INVALID_DATA;
            }

            throw $exception;
        } catch (PDOException $exception) {
            if ($this->getConnection()->inTransaction()) {
                $this->rollBack();
            }

            return $this->mapWriteException($exception, 'club');
        } catch (Throwable $exception) {
            if ($this->getConnection()->inTransaction()) {
                $this->rollBack();
            }
            throw $exception;
        }

        return $created;
    }

    /**
     * Registra una o varias mutaciones genéticas en el catálogo (SRS-RF027).
     *
     * @param array<int, array{nombre: string, tipo_herencia: string}> $mutations
     * @return array<int, array<string, mixed>>|string
     */
    public function registerMutations(array $mutations, int $adminUserId, string $reason): array|string {
        if ($mutations === []) {
            return self::ERROR_INVALID_DATA;
        }

        $created = [];

        try {
            $this->beginTransaction();

            AuditHelper::withoutAutoAudit(function () use (
                $mutations,
                $adminUserId,
                $reason,
                &$created
            ): void {
                foreach ($mutations as $item) {
                    $nombre = trim((string) ($item['nombre'] ?? ''));
                    $tipoHerencia = mb_strtolower(trim((string) ($item['tipo_herencia'] ?? '')));

                    if (
                        $nombre === ''
                        || mb_strlen($nombre) > 100
                        || !in_array($tipoHerencia, self::ALLOWED_INHERITANCE_TYPES, true)
                    ) {
                        throw new RuntimeException(self::ERROR_INVALID_DATA);
                    }

                    $row = $this->fetch(
                        'INSERT INTO mutacion (nombre, tipo_herencia)
                         VALUES (:nombre, :tipo_herencia)
                         RETURNING id_mutacion, nombre, tipo_herencia',
                        [
                            'nombre'        => $nombre,
                            'tipo_herencia' => $tipoHerencia,
                        ]
                    );

                    if ($row === null) {
                        throw new RuntimeException('No se pudo registrar la mutación.');
                    }

                    $idMutacion = (int) $row['id_mutacion'];
                    $record = [
                        'id_mutacion'   => $idMutacion,
                        'nombre'        => (string) $row['nombre'],
                        'tipo_herencia' => (string) $row['tipo_herencia'],
                    ];
                    $created[] = $record;

                    AuditHelper::log(
                        action: 'insert',
                        entity: 'mutacion',
                        recordId: $idMutacion,
                        newValue: [
                            'nombre'        => $nombre,
                            'tipo_herencia' => $tipoHerencia,
                        ],
                        reason: $reason,
                        userId: $adminUserId,
                        db: $this->getConnection()
                    );
                }
            });

            $this->commit();
        } catch (RuntimeException $exception) {
            if ($this->getConnection()->inTransaction()) {
                $this->rollBack();
            }

            if ($exception->getMessage() === self::ERROR_INVALID_DATA) {
                return self::ERROR_INVALID_DATA;
            }

            throw $exception;
        } catch (PDOException $exception) {
            if ($this->getConnection()->inTransaction()) {
                $this->rollBack();
            }

            return $this->mapWriteException($exception, 'mutacion');
        } catch (Throwable $exception) {
            if ($this->getConnection()->inTransaction()) {
                $this->rollBack();
            }
            throw $exception;
        }

        return $created;
    }

    /**
     * Traduce errores de PostgreSQL a códigos de dominio.
     */
    private function mapWriteException(PDOException $exception, string $context = ''): string {
        $sqlState = (string) $exception->getCode();

        if ($sqlState === '23505') {
            return match ($context) {
                'club'     => self::ERROR_DUPLICATE_CLUB,
                'mutacion' => self::ERROR_DUPLICATE_MUTATION,
                default    => self::ERROR_INVALID_DATA,
            };
        }

        return match ($sqlState) {
            '23502', '23514', '22P02', '22001' => self::ERROR_INVALID_DATA,
            default => throw $exception,
        };
    }
}
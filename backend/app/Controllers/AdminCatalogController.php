<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers;

use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Middlewares\AuthMiddleware;
use CanariApp\Backend\Models\CatalogAdmin;
use Throwable;

/**
 * Controlador administrativo para la gestión de catálogos oficiales:
 *  - POST /api/v1/admin/nomenclador (SRS-RF010)
 *  - POST /api/v1/admin/clubes      (SRS-RF011)
 *  - POST /api/v1/admin/mutaciones  (SRS-RF027)
 */
class AdminCatalogController {
    private CatalogAdmin $catalogModel;

    public function __construct(?CatalogAdmin $catalogModel = null) {
        $this->catalogModel = $catalogModel ?? new CatalogAdmin();
    }

    /**
     * [Admin] Carga o actualiza el nomenclador oficial de variedades (SRS-RF010).
     *
     * Admite:
     *  - Objeto individual: {"codigo": "01-001", "nombre": "AMARILLO INTENSO", "tipo": "CC", "serie": "..."}
     *  - Lote JSON: {"variedades": [...]} / {"items": [...]} / {"nomenclador": [...]} o arreglo raíz [...]
     *  - Texto plano/CSV: {"contenido": "codigo;nombre;tipo;serie\n..."} o {"csv": "..."}
     */
    public function storeNomenclador(): void {
        $adminUserId = $this->ensureAdminRole();
        $input = $this->readJsonBody();

        $items = $this->extractNomencladorItems($input);
        if ($items === null || $items === []) {
            ResponseHelper::validationError([
                'nomenclador' => 'Debe enviar al menos una variedad con codigo, nombre y tipo ("CC" o "CP").',
            ]);
            return;
        }

        $errors = $this->validateNomencladorItems($items);
        if ($errors !== []) {
            ResponseHelper::validationError($errors);
            return;
        }

        $motivo = is_string($input['motivo'] ?? null) && trim($input['motivo']) !== ''
            ? trim($input['motivo'])
            : 'Carga administrativa de nomenclador oficial (RF010)';

        try {
            $result = $this->catalogModel->loadNomenclador($items, $adminUserId, $motivo);
            if (is_string($result)) {
                ResponseHelper::validationError([
                    'nomenclador' => 'Uno o más registros del nomenclador no cumplen el formato permitido.',
                ]);
                return;
            }

            ResponseHelper::created($result, 'Nomenclador oficial cargado exitosamente.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo cargar el nomenclador.');
        }
    }

    /**
     * [Admin] Registra una o varias siglas oficiales de club (SRS-RF011).
     *
     * Admite {"sigla": "FOCH"} o lotes {"clubes": ["FOCH", "AOB"]} / [{"sigla": "FOCH"}].
     */
    public function storeClub(): void {
        $adminUserId = $this->ensureAdminRole();
        $input = $this->readJsonBody();

        $siglas = $this->extractClubSiglas($input);
        if ($siglas === null || $siglas === []) {
            ResponseHelper::validationError([
                'sigla' => 'Debe indicar una sigla de club válida (entre 2 y 6 letras mayúsculas).',
            ]);
            return;
        }

        $errors = [];
        $seen = [];
        foreach ($siglas as $index => $sigla) {
            $normalized = strtoupper(trim($sigla));
            if (preg_match('/^[A-Z]{2,6}$/', $normalized) !== 1) {
                $errors['sigla'] = 'La sigla debe contener entre 2 y 6 letras mayúsculas (A-Z).';
                break;
            }
            if (isset($seen[$normalized])) {
                $errors['sigla'] = sprintf('La sigla "%s" está repetida en la misma carga.', $normalized);
                break;
            }
            $seen[$normalized] = true;
            $siglas[$index] = $normalized;
        }

        if ($errors !== []) {
            ResponseHelper::validationError($errors);
            return;
        }

        $motivo = is_string($input['motivo'] ?? null) && trim($input['motivo']) !== ''
            ? trim($input['motivo'])
            : 'Registro administrativo de sigla de club (RF011)';

        try {
            $result = $this->catalogModel->registerClubs($siglas, $adminUserId, $motivo);
            if (is_string($result)) {
                match ($result) {
                    CatalogAdmin::ERROR_DUPLICATE_CLUB => ResponseHelper::conflict(
                        'Ya existe un club registrado con esa sigla.'
                    ),
                    default => ResponseHelper::validationError([
                        'sigla' => 'La sigla del club debe tener entre 2 y 6 letras mayúsculas.',
                    ]),
                };
                return;
            }

            $responseData = count($result) === 1 ? $result[0] : ['items' => $result, 'total' => count($result)];
            ResponseHelper::created($responseData, 'Club registrado exitosamente.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo registrar el club.');
        }
    }

    /**
     * [Admin] Registra o carga mutaciones genéticas en el catálogo oficial (SRS-RF027).
     *
     * Admite {"nombre": "Ágata", "tipo_herencia": "ligada al sexo recesiva"}
     * o lotes {"mutaciones": [...]} / {"items": [...]} / [{...}].
     */
    public function storeMutacion(): void {
        $adminUserId = $this->ensureAdminRole();
        $input = $this->readJsonBody();

        $mutations = $this->extractMutationItems($input);
        if ($mutations === null || $mutations === []) {
            ResponseHelper::validationError([
                'mutaciones' => 'Debe indicar al menos una mutación con nombre y tipo_herencia.',
            ]);
            return;
        }

        $errors = [];
        $seenNames = [];
        foreach ($mutations as $idx => $item) {
            $nombre = trim((string) ($item['nombre'] ?? ''));
            $tipo = mb_strtolower(trim((string) ($item['tipo_herencia'] ?? '')));

            if ($nombre === '' || mb_strlen($nombre) > 100) {
                $errors['nombre'] = 'El nombre de la mutación es obligatorio y no puede superar los 100 caracteres.';
                break;
            }

            if (!in_array($tipo, CatalogAdmin::ALLOWED_INHERITANCE_TYPES, true)) {
                $errors['tipo_herencia'] = 'El tipo_herencia debe ser "autosómica recesiva" o "ligada al sexo recesiva".';
                break;
            }

            $lowerKey = mb_strtolower($nombre);
            if (isset($seenNames[$lowerKey])) {
                $errors['nombre'] = sprintf('La mutación "%s" está repetida en la misma carga.', $nombre);
                break;
            }
            $seenNames[$lowerKey] = true;

            $mutations[$idx] = [
                'nombre'        => $nombre,
                'tipo_herencia' => $tipo,
            ];
        }

        if ($errors !== []) {
            ResponseHelper::validationError($errors);
            return;
        }

        $motivo = is_string($input['motivo'] ?? null) && trim($input['motivo']) !== ''
            ? trim($input['motivo'])
            : 'Registro administrativo de mutación genética (RF027)';

        try {
            $result = $this->catalogModel->registerMutations($mutations, $adminUserId, $motivo);
            if (is_string($result)) {
                match ($result) {
                    CatalogAdmin::ERROR_DUPLICATE_MUTATION => ResponseHelper::conflict(
                        'Ya existe una mutación registrada con ese nombre.'
                    ),
                    default => ResponseHelper::validationError([
                        'mutacion' => 'Los datos de la mutación no cumplen las reglas de validación.',
                    ]),
                };
                return;
            }

            $responseData = count($result) === 1 ? $result[0] : ['items' => $result, 'total' => count($result)];
            ResponseHelper::created($responseData, 'Mutación registrada exitosamente.');
        } catch (Throwable) {
            ResponseHelper::internalError('No se pudo registrar la mutación.');
        }
    }

    /**
     * @param array<string, mixed> $input
     * @return array<int, array<string, mixed>>|null
     */
    private function extractNomencladorItems(array $input): ?array {
        if (array_is_list($input) && $input !== []) {
            return $this->normalizeListOfArrays($input);
        }

        foreach (['variedades', 'items', 'nomenclador'] as $wrapperKey) {
            if (isset($input[$wrapperKey]) && is_array($input[$wrapperKey])) {
                return $this->normalizeListOfArrays($input[$wrapperKey]);
            }
        }

        $csvText = $input['contenido'] ?? $input['csv'] ?? null;
        if (is_string($csvText) && trim($csvText) !== '') {
            return $this->parseCsvNomenclador($csvText);
        }

        if (isset($input['codigo']) || isset($input['nombre']) || isset($input['tipo'])) {
            return [$input];
        }

        return null;
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function parseCsvNomenclador(string $rawCsv): array {
        $lines = preg_split('/\r\n|\r|\n/', trim($rawCsv)) ?: [];
        $parsed = [];

        foreach ($lines as $lineIndex => $line) {
            $trimmed = trim($line);
            if ($trimmed === '') {
                continue;
            }

            $delimiter = str_contains($trimmed, ';') ? ';' : ',';
            $cols = str_getcsv($trimmed, $delimiter);
            if (count($cols) < 3) {
                continue;
            }

            $col0 = trim((string) $cols[0]);
            $col1 = trim((string) $cols[1]);
            $col2 = strtoupper(trim((string) $cols[2]));
            $col3 = isset($cols[3]) ? trim((string) $cols[3]) : null;

            // Omitir fila de encabezado si existe
            if ($lineIndex === 0 && mb_strtolower($col0) === 'codigo') {
                continue;
            }

            $parsed[] = [
                'codigo' => $col0,
                'nombre' => $col1,
                'tipo'   => $col2,
                'serie'  => $col3 !== '' ? $col3 : null,
            ];
        }

        return $parsed;
    }

    /**
     * @param array<int, array<string, mixed>> $items
     * @return array<string, string>
     */
    private function validateNomencladorItems(array $items): array {
        $seenCodes = [];

        foreach ($items as $idx => $item) {
            $rowNumber = $idx + 1;
            $codigo = is_scalar($item['codigo'] ?? null) ? trim((string) $item['codigo']) : '';
            $nombre = is_scalar($item['nombre'] ?? null) ? trim((string) $item['nombre']) : '';
            $tipo = is_scalar($item['tipo'] ?? null) ? strtoupper(trim((string) $item['tipo'])) : '';
            $serie = $item['serie'] ?? null;

            if ($codigo === '' || mb_strlen($codigo) > 10) {
                return ['codigo' => sprintf('Fila %d: el código es obligatorio y admite hasta 10 caracteres.', $rowNumber)];
            }

            if ($nombre === '' || mb_strlen($nombre) > 150) {
                return ['nombre' => sprintf('Fila %d: el nombre es obligatorio y admite hasta 150 caracteres.', $rowNumber)];
            }

            if (!in_array($tipo, CatalogAdmin::ALLOWED_VARIETY_TYPES, true)) {
                return ['tipo' => sprintf('Fila %d: el tipo debe ser "CC" o "CP".', $rowNumber)];
            }

            if ($serie !== null && (!is_scalar($serie) || mb_strlen(trim((string) $serie)) > 50)) {
                return ['serie' => sprintf('Fila %d: la serie no puede superar los 50 caracteres.', $rowNumber)];
            }

            if (isset($seenCodes[$codigo])) {
                return ['codigo' => sprintf('El código "%s" está duplicado dentro de la carga.', $codigo)];
            }
            $seenCodes[$codigo] = true;
        }

        return [];
    }

    /**
     * @param array<string, mixed> $input
     * @return array<int, string>|null
     */
    private function extractClubSiglas(array $input): ?array {
        if (array_is_list($input) && $input !== []) {
            $siglas = [];
            foreach ($input as $entry) {
                if (is_string($entry)) {
                    $siglas[] = $entry;
                } elseif (is_array($entry) && is_scalar($entry['sigla'] ?? null)) {
                    $siglas[] = (string) $entry['sigla'];
                } else {
                    return null;
                }
            }

            return $siglas;
        }

        if (isset($input['clubes']) && is_array($input['clubes'])) {
            return $this->extractClubSiglas($input['clubes']);
        }

        if (is_scalar($input['sigla'] ?? null)) {
            return [(string) $input['sigla']];
        }

        return null;
    }

    /**
     * @param array<string, mixed> $input
     * @return array<int, array<string, mixed>>|null
     */
    private function extractMutationItems(array $input): ?array {
        if (array_is_list($input) && $input !== []) {
            return $this->normalizeListOfArrays($input);
        }

        foreach (['mutaciones', 'items'] as $wrapperKey) {
            if (isset($input[$wrapperKey]) && is_array($input[$wrapperKey])) {
                return $this->normalizeListOfArrays($input[$wrapperKey]);
            }
        }

        if (isset($input['nombre']) || isset($input['tipo_herencia'])) {
            return [$input];
        }

        return null;
    }

    /**
     * @param array<mixed> $rawList
     * @return array<int, array<string, mixed>>|null
     */
    private function normalizeListOfArrays(array $rawList): ?array {
        $result = [];
        foreach ($rawList as $entry) {
            if (!is_array($entry)) {
                return null;
            }
            $result[] = $entry;
        }

        return $result;
    }

    private function ensureAdminRole(): int {
        if (AuthMiddleware::userRole() !== 'administrador') {
            ResponseHelper::forbidden('Solo un administrador puede gestionar catálogos oficiales.');
        }

        $userId = AuthMiddleware::userId();
        if ($userId === null || !is_numeric($userId)) {
            ResponseHelper::unauthorized('No hay un usuario autenticado.');
        }

        return (int) $userId;
    }

    /**
     * @return array<string, mixed>
     */
    private function readJsonBody(): array {
        $raw = file_get_contents('php://input');
        if ($raw === false || trim($raw) === '') {
            ResponseHelper::badRequest('El cuerpo de la petición es obligatorio.');
        }

        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            ResponseHelper::badRequest('El cuerpo de la petición debe ser un JSON válido.');
        }

        return $decoded;
    }
}
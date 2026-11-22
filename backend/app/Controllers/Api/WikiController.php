<?php

declare(strict_types=1);

namespace CanariApp\Backend\Controllers\Api;

use CanariApp\Backend\Helpers\ResponseHelper;
use CanariApp\Backend\Helpers\Sanitizer;
use CanariApp\Backend\Models\Catalog;

/**
 * Catálogos oficiales usados por los formularios y el simulador.
 *
 * El SRS excluye una wiki de cuidados o alimentación (sección 1.2): este
 * controlador solo expone club, variedad y mutación, en modo de solo lectura.
 */
class WikiController {
    /** Paquete completo de catálogos para cargar los desplegables. */
    public function index(): void {
        ResponseHelper::success(
            (new Catalog())->todos(),
            'Catálogos obtenidos.'
        );
    }

    /** Siglas de club disponibles para el anillo (SRS-RF002, SRS-RF011). */
    public function clubes(): void {
        ResponseHelper::success(
            (new Catalog())->clubes(),
            'Listado de clubes obtenido.'
        );
    }

    /**
     * Nomenclador de variedades (SRS-RF007, SRS-RF009).
     *
     * Filtros opcionales: buscar, codigo, tipo (CC/CP) y sexo (M/H).
     */
    public function variedades(): void {
        $filters = $this->variedadFilters();
        if ($filters === null) {
            return;
        }

        ResponseHelper::success(
            (new Catalog())->variedades($filters),
            'Listado de variedades obtenido.'
        );
    }

    /** Detalle de una variedad por ID. */
    public function variedad(int|string $id): void {
        $idVariedad = filter_var(trim((string) $id), FILTER_VALIDATE_INT);
        if ($idVariedad === false || $idVariedad <= 0) {
            ResponseHelper::badRequest('El ID de la variedad no es válido.');
        }

        $variedad = (new Catalog())->variedadPorId((int) $idVariedad);
        if ($variedad === null) {
            ResponseHelper::notFound('Variedad no encontrada.');
        }

        ResponseHelper::success($variedad, 'Detalle de la variedad obtenido.');
    }

    /** Selección exacta por código del nomenclador (SRS-RF008). */
    public function variedadPorCodigo(int|string $codigo): void {
        $texto = Sanitizer::string(rawurldecode((string) $codigo), 10);
        if ($texto === null || $texto === '') {
            ResponseHelper::badRequest('El código de variedad no es válido.');
        }

        $variedad = (new Catalog())->variedadPorCodigo($texto);
        if ($variedad === null) {
            ResponseHelper::notFound('Variedad no encontrada.');
        }

        ResponseHelper::success($variedad, 'Detalle de la variedad obtenido.');
    }

    /** Mutaciones disponibles en el simulador (SRS-RF025, SRS-RF027). */
    public function mutaciones(): void {
        ResponseHelper::success(
            (new Catalog())->mutaciones(),
            'Listado de mutaciones obtenido.'
        );
    }

    /**
     * Valida los filtros de /variedades.
     *
     * @return array<string, string>|null `null` cuando ya se envió una respuesta 422.
     */
    private function variedadFilters(): ?array {
        $errors = [];
        $filters = [];

        $tipo = $this->boundedText('tipo', 2, $errors, 'El tipo debe ser "CC" o "CP".');
        if ($tipo !== null) {
            if (in_array($tipo, ['CC', 'CP'], true)) {
                $filters['tipo'] = $tipo;
            } else {
                $errors['tipo'] = 'El tipo debe ser "CC" o "CP".';
            }
        }

        $sexo = $this->boundedText('sexo', 1, $errors, 'El sexo debe ser "M" o "H".');
        if ($sexo !== null) {
            if (in_array($sexo, ['M', 'H'], true)) {
                $filters['sexo'] = $sexo;
            } else {
                $errors['sexo'] = 'El sexo debe ser "M" o "H".';
            }
        }

        $codigo = $this->boundedText('codigo', 10, $errors, 'El código no puede superar 10 caracteres.');
        if ($codigo !== null) {
            $filters['codigo'] = $codigo;
        }

        $buscar = $this->boundedText('buscar', 150, $errors, 'La búsqueda no puede superar 150 caracteres.');
        if ($buscar !== null) {
            $filters['buscar'] = $buscar;
        }

        if ($errors !== []) {
            ResponseHelper::validationError($errors);

            return null;
        }

        return $filters;
    }

    /**
     * Lee un query param opcional, recortado y con límite de longitud.
     * Un valor vacío se trata como "sin filtro".
     *
     * @param array<string, string> $errors
     */
    private function boundedText(string $key, int $maxLength, array &$errors, string $message): ?string {
        if (!array_key_exists($key, $_GET)) {
            return null;
        }

        $value = Sanitizer::string($_GET[$key], $maxLength);
        if ($value === null) {
            $errors[$key] = $message;

            return null;
        }

        return $value === '' ? null : $value;
    }
}

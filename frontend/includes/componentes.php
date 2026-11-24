<?php
// Piezas reutilizables entre páginas

// <datalist> con el nomenclador, para inputs de variedad con autocompletar
function datalist_variedades() {
    $h = '<datalist id="lista-variedades">';
    foreach (VARIEDADES as $cod => $v) $h .= '<option value="' . e($cod . ' · ' . $v['nombre']) . '">';
    return $h . '</datalist>';
}

// Toma "CC033 · Lipocromo..." o "cc033" y devuelve el código si existe
function leer_variedad($txt) {
    $cod = strtoupper(trim(explode('·', $txt)[0]));
    return isset(VARIEDADES[$cod]) ? $cod : null;
}

// Factores que puede portar según el sexo: la hembra no porta mutaciones ligadas al sexo
function factores_para($sexo) {
    return $sexo === 'Macho' ? FACTORES : array_values(array_diff(FACTORES, FACTORES_LIGADOS));
}
// «Portador», «Portadora» o «Portador/a» si el sexo aún está pendiente
function portador_txt($c) {
    return ['Macho' => 'Portador', 'Hembra' => 'Portadora'][$c['sexo']] ?? 'Portador/a';
}

// Valida que la variedad sea compatible con el sexo; devuelve mensaje o null
function error_variedad_sexo($cod, $sexo) {
    $req = VARIEDADES[$cod]['sexo'] ?? null;
    if ($req && $sexo && $req !== $sexo) {
        return 'Esta variedad es de ' . mb_strtoupper($req) . ' y el ejemplar es ' . mb_strtolower($sexo) . '. Elija otra variedad o corrija el sexo.';
    }
    return null;
}

function select_opciones($opciones, $actual, $placeholder = null) {
    $h = $placeholder !== null ? '<option value="">' . e($placeholder) . '</option>' : '';
    if (array_is_list($opciones)) $opciones = array_combine($opciones, $opciones);
    foreach ($opciones as $valor => $texto) {
        $h .= '<option value="' . e($valor) . '"' . ((string)$valor === (string)$actual ? ' selected' : '') . '>' . e($texto) . '</option>';
    }
    return $h;
}

// Badges de estado/marcas de un canario
function badges_canario($c, $conTitulos = true) {
    $h = '';
    if ($c['sexo']) $h .= '<span class="badge">' . e($c['sexo']) . '</span>';
    if ($c['variedad']) $h .= '<span class="badge">' . e(variedad_txt($c['variedad'])) . '</span>';
    if ($c['portadora']) $h .= '<span class="badge badge-borde">' . portador_txt($c) . ' · ' . e($c['portadora']) . '</span>';
    if ($c['reservada']) $h .= '<span class="badge">Reservada</span>';
    $n = count(titulos_de(clave($c)));
    if ($conTitulos && $n) $h .= '<span class="badge badge-oscuro">Con ' . $n . ' título' . ($n > 1 ? 's' : '') . '</span>';
    return $h;
}

function marcas_html($c) {
    $h = [];
    if ($c['portadora']) $h[] = '<span class="badge badge-borde">' . portador_txt($c) . ' · ' . e($c['portadora']) . '</span>';
    if ($c['reservada']) $h[] = '<span class="badge">Reservada</span>';
    return $h ? implode(' ', $h) : '<span class="muted">—</span>';
}

// Modal genérico: abre/cierra con app.js. $abierto = true para mostrarlo al cargar (p. ej. con errores)
function modal_inicio($id, $eyebrow, $titulo, $sub = '', $abierto = false, $ancho = false) {
    return '<div class="modal' . ($abierto ? ' abierto' : '') . '" id="' . e($id) . '"><div class="modal-caja' . ($ancho ? ' ancho' : '') . '">'
        . '<button type="button" class="modal-x" data-cerrar aria-label="Cerrar">' . icono('cerrar', 18) . '</button>'
        . '<div><p class="eyebrow">' . e($eyebrow) . '</p><h2>' . $titulo . '</h2>'
        . ($sub ? '<p class="small muted" style="margin-top:4px">' . $sub . '</p>' : '') . '</div>';
}
function modal_fin() { return '</div></div>'; }

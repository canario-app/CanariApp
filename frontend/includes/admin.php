<?php
/*
 * Piezas de la zona de administración (SRS 4.1.8, RF010, RF011).
 * Varias acciones todavía no tienen endpoint en el backend: el front las deja construidas y,
 * si la API responde «La ruta solicitada no existe.», lo avisa en pantalla en vez de fallar.
 */

// ---------- Llamadas a la API ----------
// Igual que api(), pero marca si el endpoint aún no existe en el backend
function api_admin($metodo, $ruta, $cuerpo = null) {
    $r = api($metodo, $ruta, $cuerpo);
    $r['sin_endpoint'] = $r['status'] === 404 && $r['message'] === 'La ruta solicitada no existe.';
    if ($r['status'] === 401) { unset($_SESSION['usuario'], $_SESSION['token']); header('Location: login.php?expirada=1'); exit; }
    return $r;
}

// Sube un archivo (multipart) en el campo «archivo»
function api_subir($ruta, $tmp, $nombre) {
    $ch = curl_init(API_URL . $ruta);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => ['Accept: application/json', 'Authorization: Bearer ' . ($_SESSION['token'] ?? '')],
        CURLOPT_POSTFIELDS => ['archivo' => new CURLFile($tmp, null, $nombre)],
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 30,
    ]);
    $raw = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($raw === false) return ['status' => 0, 'data' => null, 'message' => 'No hay conexión con la API.', 'errors' => [], 'sin_endpoint' => false];
    $j = json_decode($raw, true) ?: [];
    $msg = $j['message'] ?? '';
    return ['status' => $status, 'data' => $j['data'] ?? null, 'message' => $msg, 'errors' => $j['errors'] ?? [],
            'sin_endpoint' => $status === 404 && $msg === 'La ruta solicitada no existe.'];
}

// ---------- Avisos ----------
function aviso_pendiente_backend($que) {
    return '<div class="aviso aviso-warn">' . icono('alerta') . '<div><strong>Función pendiente en el backend</strong><p>'
        . e($que) . ' Esta pantalla ya está lista: funcionará cuando el equipo de backend publique el endpoint.</p></div></div>';
}
function aviso_error($titulo, $texto) {
    return '<div class="aviso aviso-error">' . icono('alerta') . '<div><strong>' . e($titulo) . '</strong><p>' . e($texto) . '</p></div></div>';
}

// ---------- Validación de archivos CSV (SRS-RF010 y RF027: se rechaza el archivo completo indicando fila y causa) ----------
// Devuelve [filas|null, error|null]. Las filas son arreglos asociativos por nombre de columna en minúsculas.
function leer_csv($ruta, $columnas) {
    $txt = file_get_contents($ruta);
    if ($txt === false || trim($txt) === '') return [null, 'El archivo está vacío.'];
    $txt = preg_replace('/^\xEF\xBB\xBF/', '', $txt);
    if (!mb_check_encoding($txt, 'UTF-8')) $txt = mb_convert_encoding($txt, 'UTF-8', 'ISO-8859-1');
    $lineas = preg_split('/\r\n|\n|\r/', trim($txt));
    $sep = substr_count($lineas[0], ';') > substr_count($lineas[0], ',') ? ';' : ',';
    $norm = fn($s) => mb_strtolower(strtr(trim($s), ['á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u', 'Á' => 'a', 'É' => 'e', 'Í' => 'i', 'Ó' => 'o', 'Ú' => 'u']));
    $cab = array_map($norm, str_getcsv($lineas[0], $sep, '"', ''));
    $idx = [];
    foreach ($columnas as $clave => $alias) {
        foreach ((array)$alias as $a) { $i = array_search($a, $cab, true); if ($i !== false) { $idx[$clave] = $i; break; } }
        if (!isset($idx[$clave])) return [null, 'Falta la columna «' . ((array)$alias)[0] . '». Las columnas son: ' . implode(', ', array_map(fn($a) => ((array)$a)[0], $columnas)) . '.'];
    }
    $filas = [];
    foreach (array_slice($lineas, 1) as $n => $l) {
        if (trim($l) === '') continue;
        $c = str_getcsv($l, $sep, '"', '');
        $f = ['_fila' => $n + 2];
        foreach ($idx as $clave => $i) $f[$clave] = trim($c[$i] ?? '');
        $filas[] = $f;
    }
    if (!$filas) return [null, 'El archivo no tiene filas de datos.'];
    return [$filas, null];
}

// Devuelve lista de [fila, causa]; vacía = válido
function errores_nomenclador($filas) {
    $err = []; $vistos = [];
    foreach ($filas as $f) {
        $cod = mb_strtoupper($f['codigo']);
        if ($cod === '') $err[] = [$f['_fila'], 'El código está vacío.'];
        elseif (mb_strlen($cod) > 10) $err[] = [$f['_fila'], "El código $cod supera los 10 caracteres."];
        elseif (isset($vistos[$cod])) $err[] = [$f['_fila'], "El código $cod está repetido (también en la fila {$vistos[$cod]})."];
        else $vistos[$cod] = $f['_fila'];
        if ($f['nombre'] === '') $err[] = [$f['_fila'], 'El nombre está vacío.'];
        if (!in_array(mb_strtoupper($f['tipo']), ['CC', 'CP'], true)) $err[] = [$f['_fila'], 'El tipo debe ser CC o CP.'];
    }
    return $err;
}
function errores_mutaciones($filas) {
    $err = []; $vistos = [];
    foreach ($filas as $f) {
        $k = mb_strtolower($f['nombre']);
        if ($k === '') $err[] = [$f['_fila'], 'El nombre está vacío.'];
        elseif (isset($vistos[$k])) $err[] = [$f['_fila'], "El nombre {$f['nombre']} está repetido (también en la fila {$vistos[$k]})."];
        else $vistos[$k] = $f['_fila'];
        if (!in_array(mb_strtolower($f['tipo']), ['autosómica recesiva', 'autosomica recesiva', 'ligada al sexo recesiva'], true)) $err[] = [$f['_fila'], 'El tipo de herencia debe ser «autosómica recesiva» o «ligada al sexo recesiva».'];
    }
    return $err;
}

/*
 * Procesa la subida de un archivo de catálogo. Devuelve:
 *   ['ok' => bool, 'titulo' => str, 'texto' => str, 'errores' => [[fila, causa], ...], 'pendiente' => bool]
 * $columnas: columnas esperadas (con alias); $validar: función de errores para CSV; $ruta: endpoint del backend.
 */
function procesar_carga($ruta, $columnas, $validar) {
    $f = $_FILES['archivo'] ?? null;
    if (!$f || $f['error'] === UPLOAD_ERR_NO_FILE) return ['ok' => false, 'titulo' => 'Elija un archivo', 'texto' => 'Seleccione un archivo CSV o XLSX.', 'errores' => []];
    if ($f['error'] !== UPLOAD_ERR_OK) return ['ok' => false, 'titulo' => 'No se pudo leer el archivo', 'texto' => 'Intente nuevamente (código ' . $f['error'] . ').', 'errores' => []];
    $ext = strtolower(pathinfo($f['name'], PATHINFO_EXTENSION));
    if (!in_array($ext, ['csv', 'xlsx'], true)) return ['ok' => false, 'titulo' => 'Formato no admitido', 'texto' => 'Solo se aceptan archivos .csv o .xlsx.', 'errores' => []];
    if ($f['size'] > 5 * 1024 * 1024) return ['ok' => false, 'titulo' => 'Archivo demasiado grande', 'texto' => 'El máximo es 5 MB.', 'errores' => []];

    // El CSV se revisa aquí antes de enviarlo; el XLSX lo valida el backend
    if ($ext === 'csv') {
        [$filas, $e] = leer_csv($f['tmp_name'], $columnas);
        if ($e) return ['ok' => false, 'titulo' => 'Archivo rechazado', 'texto' => $e, 'errores' => []];
        if ($err = $validar($filas)) return ['ok' => false, 'titulo' => 'Archivo rechazado por completo', 'texto' => 'Corrija las filas indicadas y vuelva a cargarlo. No se incorporó ningún dato.', 'errores' => $err];
    }
    $r = api_subir($ruta, $f['tmp_name'], $f['name']);
    if ($r['sin_endpoint']) return ['ok' => false, 'pendiente' => true, 'titulo' => 'Archivo válido, pero no se pudo cargar', 'texto' => 'El archivo pasó la revisión, pero el backend aún no tiene este endpoint.', 'errores' => []];
    if ($r['status'] >= 200 && $r['status'] < 300) return ['ok' => true, 'titulo' => 'Carga completada', 'texto' => $r['message'] ?: 'El catálogo se actualizó.', 'errores' => [], 'datos' => $r['data']];
    $err = [];
    foreach ((array)($r['errors'] ?? []) as $k => $v) $err[] = [is_numeric($k) ? $k : '—', is_array($v) ? implode(' ', $v) : (string)$v];
    return ['ok' => false, 'titulo' => 'Archivo rechazado', 'texto' => $r['message'] ?: 'El backend rechazó el archivo.', 'errores' => $err];
}

// Resultado de una carga (aviso + tabla fila/causa)
function resultado_carga_html($res) {
    if (!$res) return '';
    if ($res['ok']) {
        $x = '';
        if (!empty($res['datos']) && is_array($res['datos'])) foreach ($res['datos'] as $k => $v) if (is_scalar($v)) $x .= ' ' . e(ucfirst(str_replace('_', ' ', $k))) . ': ' . e($v) . '.';
        return '<div class="aviso aviso-ok">' . icono('check') . '<div><strong>' . e($res['titulo']) . '</strong><p>' . e($res['texto']) . $x . '</p></div></div>';
    }
    $h = !empty($res['pendiente']) ? aviso_pendiente_backend($res['texto']) : aviso_error($res['titulo'], $res['texto']);
    if ($res['errores']) {
        $h .= '<table class="tabla" style="max-width:none;margin:0"><thead><tr><th style="width:90px">Fila</th><th>Causa</th></tr></thead><tbody>';
        foreach (array_slice($res['errores'], 0, 50) as [$fila, $causa]) $h .= '<tr><td>' . e($fila) . '</td><td>' . e($causa) . '</td></tr>';
        if (count($res['errores']) > 50) $h .= '<tr><td colspan="2" class="muted">…y ' . (count($res['errores']) - 50) . ' más.</td></tr>';
        $h .= '</tbody></table>';
    }
    return $h;
}

// Estado actual del sistema: ['modo' => normal|mantenimiento|emergencia, 'detalle' => array|null, 'conocido' => bool]
function modo_actual() {
    $r = api_admin('GET', '/api/v1/admin/modo');
    if ($r['status'] === 200 && is_array($r['data'])) {
        $d = $r['data'];
        return ['modo' => $d['modo'] ?? 'normal', 'detalle' => $d, 'conocido' => true];
    }
    return ['modo' => 'normal', 'detalle' => null, 'conocido' => false];
}

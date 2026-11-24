<?php
/*
 * Cliente HTTP de la API de CanariApp (backend PHP + PostgreSQL).
 * El token JWT vive en $_SESSION['token']; las llamadas salen desde el servidor PHP, así que no hace falta CORS.
 */
// En Docker/servidor se define con la variable de entorno API_URL; en XAMPP local queda localhost:8000.
define('API_URL', rtrim(getenv('API_URL') ?: 'http://localhost:8000', '/'));

// SEG-004: la API devuelve un token renovado (cabecera X-Session-Token) en cada petición válida,
// así la sesión vence tras 30 minutos SIN ACTIVIDAD y no 30 minutos después del login.
function api_capturar_token($ch, $linea) {
    if (stripos($linea, 'X-Session-Token:') === 0) {
        $nuevo = trim(substr($linea, strlen('X-Session-Token:')));
        if ($nuevo !== '' && !empty($_SESSION['token'])) $_SESSION['token'] = $nuevo;
    }
    return strlen($linea);
}

// Devuelve ['status' => int, 'data' => mixed, 'message' => string, 'errors' => array]
function api($metodo, $ruta, $cuerpo = null, $conToken = true) {
    $ch = curl_init(API_URL . $ruta);
    $cab = ['Accept: application/json', 'Content-Type: application/json'];
    if ($conToken && !empty($_SESSION['token'])) $cab[] = 'Authorization: Bearer ' . $_SESSION['token'];
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST => $metodo,
        CURLOPT_HTTPHEADER => $cab,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 10,
        CURLOPT_HEADERFUNCTION => 'api_capturar_token',
    ]);
    if ($cuerpo !== null) curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($cuerpo));
    $raw = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($raw === false) return ['status' => 0, 'data' => null, 'message' => 'No hay conexión con el servidor de CanariApp (¿está encendida la API en ' . API_URL . '?).', 'errors' => []];
    $j = json_decode($raw, true) ?: [];
    return ['status' => $status, 'data' => $j['data'] ?? null, 'message' => $j['message'] ?? '', 'errors' => $j['errors'] ?? []];
}

// 503 = mantenimiento o emergencia (SRS-RF028): se cierra la sesión del criador y se avisa en el login
function cortar_si_mantenimiento($r) {
    if ($r['status'] === 503) {
        unset($_SESSION['usuario'], $_SESSION['token']);
        header('Location: login.php?mantenimiento=1');
        exit;
    }
}

// GET que devuelve la lista de datos o corta la página con un aviso si falla
function api_lista($ruta) {
    $r = api('GET', $ruta);
    cortar_si_mantenimiento($r);
    if ($r['status'] === 401) {
        unset($_SESSION['usuario'], $_SESSION['token']);
        header('Location: login.php?expirada=1');
        exit;
    }
    if ($r['status'] !== 200) {
        http_response_code(502);
        exit('<p style="font:16px sans-serif;padding:2rem">No se pudo leer ' . htmlspecialchars($ruta) . ': ' . htmlspecialchars($r['message']) . '</p>');
    }
    return $r['data'] ?? [];
}

// Escritura: si la API rechaza, vuelve a la página anterior mostrando el motivo exacto
function api_escribir($metodo, $ruta, $cuerpo) {
    $r = api($metodo, $ruta, $cuerpo);
    cortar_si_mantenimiento($r);
    if ($r['status'] === 401) {
        unset($_SESSION['usuario'], $_SESSION['token']);
        header('Location: login.php?expirada=1');
        exit;
    }
    if ($r['status'] < 200 || $r['status'] >= 300) {
        $m = $r['message'];
        if ($r['errors']) $m .= ' ' . implode(' ', array_map('strval', $r['errors']));
        $_SESSION['flash_error'] = trim($m) ?: 'La API rechazó la operación.';
        $_SESSION['flash_post'] = $_POST; // para volver a llenar el formulario con lo que escribió el criador
        header('Location: ' . ($_SERVER['REQUEST_URI'] ?? 'inicio.php'));
        exit;
    }
    return $r['data'];
}

<?php
/*
 * Cliente HTTP de la API de CanariApp (backend PHP + PostgreSQL).
 * El token JWT vive en $_SESSION['token']; las llamadas salen desde el servidor PHP, así que no hace falta CORS.
 */
// En Docker/servidor se define con la variable de entorno API_URL; en XAMPP local queda localhost:8000.
define('API_URL', rtrim(getenv('API_URL') ?: 'http://localhost:8000', '/'));

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
    ]);
    if ($cuerpo !== null) curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($cuerpo));
    $raw = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($raw === false) return ['status' => 0, 'data' => null, 'message' => 'No hay conexión con el servidor de CanariApp (¿está encendida la API en ' . API_URL . '?).', 'errors' => []];
    $j = json_decode($raw, true) ?: [];
    return ['status' => $status, 'data' => $j['data'] ?? null, 'message' => $j['message'] ?? '', 'errors' => $j['errors'] ?? []];
}

// GET que devuelve la lista de datos o corta la página con un aviso si falla
function api_lista($ruta) {
    $r = api('GET', $ruta);
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
    if ($r['status'] === 401) {
        unset($_SESSION['usuario'], $_SESSION['token']);
        header('Location: login.php?expirada=1');
        exit;
    }
    if ($r['status'] < 200 || $r['status'] >= 300) {
        $m = $r['message'];
        if ($r['errors']) $m .= ' ' . implode(' ', array_map('strval', $r['errors']));
        $_SESSION['flash_error'] = trim($m) ?: 'La API rechazó la operación.';
        header('Location: ' . ($_SERVER['REQUEST_URI'] ?? 'inicio.php'));
        exit;
    }
    return $r['data'];
}

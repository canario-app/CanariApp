<?php
// Configuración general + helpers
session_start();
date_default_timezone_set('America/Santiago');

const MINUTOS_INACTIVIDAD = 30;   // SEG-004: cierre de sesión por inactividad
const MAX_INTENTOS = 5;           // intentos de login antes del bloqueo
const MINUTOS_BLOQUEO = 15;

require_once __DIR__ . '/datos.php';
require_once __DIR__ . '/componentes.php';

// Escapar texto para imprimir en HTML
function e($texto) {
    return htmlspecialchars((string)$texto, ENT_QUOTES, 'UTF-8');
}

// Protege páginas internas: sin sesión → login; 30 min sin actividad → sesión expirada
function requerir_login() {
    if (empty($_SESSION['usuario'])) {
        header('Location: login.php');
        exit;
    }
    if (isset($_SESSION['ultima_actividad']) && time() - $_SESSION['ultima_actividad'] > MINUTOS_INACTIVIDAD * 60) {
        $correo = $_SESSION['usuario']['correo'];
        unset($_SESSION['usuario'], $_SESSION['token']);
        header('Location: login.php?expirada=1&correo=' . urlencode($correo));
        exit;
    }
    $_SESSION['ultima_actividad'] = time();
    $admin = ($_SESSION['usuario']['rol'] ?? '') === 'administrador';
    $enAdmin = str_starts_with(basename($_SERVER['SCRIPT_NAME']), 'admin_');
    if ($admin && !$enAdmin) { header('Location: admin_criadores.php'); exit; }
    if (!$admin && $enAdmin) { header('Location: inicio.php'); exit; }
}

// Redirige con un mensaje que se muestra una sola vez (patrón POST → redirect → GET)
function redirigir($url, $titulo = null, $texto = '') {
    if ($titulo) $_SESSION['flash'] = ['titulo' => $titulo, 'texto' => $texto];
    header("Location: $url");
    exit;
}

// Lo que el criador había enviado cuando la API rechazó el formulario (una sola vez)
function post_previo() {
    $p = $_SESSION['flash_post'] ?? [];
    unset($_SESSION['flash_post']);
    return $p;
}

function flash() {
    $err = $_SESSION['flash_error'] ?? null;
    unset($_SESSION['flash_error']);
    if ($err) return '<div class="aviso aviso-error">' . icono('alerta') . '<div><strong>No se pudo completar la acción</strong><p>' . e($err) . '</p></div></div>';
    $f = $_SESSION['flash'] ?? null;
    unset($_SESSION['flash']);
    if (!$f) return '';
    return '<div class="aviso aviso-ok">' . icono('check') . '<div><strong>' . e($f['titulo']) . '</strong><p>' . e($f['texto']) . '</p></div></div>';
}

// Fechas: se guardan como AAAA-MM-DD y se muestran como DD/MM/AAAA
function fecha($ymd) {
    return $ymd ? date('d/m/Y', strtotime($ymd)) : '—';
}
function hoy() {
    return date('Y-m-d');
}

// Íconos SVG simples (trazo) para no depender de archivos
function icono($nombre, $t = 16) {
    $p = [
        'atras'    => '<path d="M19 12H5m6-6-6 6 6 6"/>',
        'chevron'  => '<path d="m9 6 6 6-6 6"/>',
        'check'    => '<path d="m5 12 5 5 9-10"/>',
        'info'     => '<circle cx="12" cy="12" r="9"/><path d="M12 11v5m0-8h.01"/>',
        'alerta'   => '<circle cx="12" cy="12" r="9"/><path d="M12 7v6m0 3h.01"/>',
        'candado'  => '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
        'cerrar'   => '<path d="M6 6l12 12M18 6 6 18"/>',
        'llave'    => '<path d="M14 7a3 3 0 1 1 3 3l-7 7-3 1 1-3 6-6"/>',
        'enviar'   => '<path d="m4 12 16-8-6 16-2-6-8-2Z"/>',
        'calendario' => '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 10h16M9 3v4m6-4v4"/>',
        'trofeo'   => '<path d="M8 4h8v5a4 4 0 0 1-8 0V4Zm4 9v4m-3 3h6M8 6H5a3 3 0 0 0 3 4m8-4h3a3 3 0 0 1-3 4"/>',
        'arbol'    => '<circle cx="12" cy="5" r="2"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="19" r="2"/><path d="M12 7v5m-6 5v-3h12v3"/>',
        'cuadrado' => '<rect x="7" y="7" width="10" height="10" rx="1"/>',
        'huevo'    => '<path d="M12 3c3.5 0 6 6 6 10a6 6 0 0 1-12 0c0-4 2.5-10 6-10Z"/>',
        'mas'      => '<path d="M12 5v14M5 12h14"/>',
        'buscar'   => '<circle cx="11" cy="11" r="6"/><path d="m20 20-4.5-4.5"/>',
        'corazon'  => '<path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.5-7 10-7 10Z"/>',
    ][$nombre] ?? '';
    return "<svg class=\"ico\" width=\"$t\" height=\"$t\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\">$p</svg>";
}

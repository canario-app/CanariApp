<?php
/*
 * Capa de datos conectada a la API de CanariApp.
 * Mantiene las mismas funciones y formas de arreglo que usaban las páginas con los datos de prueba
 * (canarios por clave "numero-club-socio-temp", parejas/nidadas/títulos por id) para no tocar las pantallas.
 * Cada lectura se cachea durante la petición; cada escritura va a la API y la página redirige después.
 */
require_once __DIR__ . '/api.php';

const MAX_PAREJAS_MACHO = 6;

// ---------- Catálogos (club, variedad, mutación) ----------
// Se piden una vez por sesión y se definen como constantes, igual que antes.
function cargar_catalogo() {
    if (empty($_SESSION['token'])) return ['clubes' => [], 'variedades' => [], 'mutaciones' => []];
    if (empty($_SESSION['catalogo'])) $_SESSION['catalogo'] = api_lista('/api/v1/wiki');
    return $_SESSION['catalogo'];
}
$_cat = cargar_catalogo();
define('CLUBES', array_column($_cat['clubes'], 'sigla'));
define('FACTORES', array_column($_cat['mutaciones'], 'nombre'));
$_vars = [];
foreach ($_cat['variedades'] as $_v) {
    $_vars[$_v['codigo']] = ['nombre' => $_v['nombre'], 'sexo' => ['M' => 'Macho', 'H' => 'Hembra'][$_v['sexo'] ?? ''] ?? null];
}
define('VARIEDADES', $_vars);
unset($_cat, $_vars, $_v);

function id_club($sigla) { foreach (cargar_catalogo()['clubes'] as $c) if ($c['sigla'] === $sigla) return $c['id_club']; return null; }
function id_variedad($cod) { foreach (cargar_catalogo()['variedades'] as $v) if ($v['codigo'] === $cod) return $v['id_variedad']; return null; }
function id_mutacion($nombre) { foreach (cargar_catalogo()['mutaciones'] as $m) if ($m['nombre'] === $nombre) return $m['id_mutacion']; return null; }
function cod_variedad($id) { foreach (cargar_catalogo()['variedades'] as $v) if ($v['id_variedad'] == $id) return $v['codigo']; return ''; }

function variedad_txt($cod) {
    return $cod && isset(VARIEDADES[$cod]) ? $cod . ' · ' . VARIEDADES[$cod]['nombre'] : '';
}

// ---------- Carga y traducción de la API a las formas que usan las páginas ----------
function &db() {
    static $db = null;
    if ($db !== null) return $db;

    $lc = api_lista('/api/v1/canarios');
    $lp = api_lista('/api/v1/parejas');
    $lx = api_lista('/api/v1/cruces');
    $ln = api_lista('/api/v1/nidadas');
    $lr = api_lista('/api/v1/crias');
    $lt = api_lista('/api/v1/titulos');
    $lj = api_lista('/api/v1/jaulas');

    // La BD compara anillo y socio como enteros (0005 = 5), así que la clave también
    $claveDe = fn($anillo, $club, $socio, $temp) => (int)$anillo . "-$club-" . (int)$socio . "-$temp";
    $clavePorId = [];
    foreach ($lc as $x) $clavePorId[$x['id_canario']] = $claveDe($x['anillo'], $x['club_sigla'], $x['numero_socio'], $x['temporada']);

    $parejas = [];
    foreach ($lp as $x) {
        $parejas[$x['id_pareja']] = [
            'id_jaula' => $x['id_jaula'], 'jaula' => (int)$x['numero_jaula'],
            'macho' => $clavePorId[$x['id_macho']] ?? '', 'hembra' => $clavePorId[$x['id_hembra']] ?? '',
            'estado' => ucfirst($x['estado']), 'desde' => $x['fecha_formacion'], 'fin' => $x['fecha_fin'], 'cruces' => [],
        ];
    }
    foreach ($lx as $x) if (isset($parejas[$x['id_pareja']])) $parejas[$x['id_pareja']]['cruces'][] = $x['fecha_cruce'];
    foreach ($parejas as &$p) sort($p['cruces']);
    unset($p);

    $nidadas = [];
    foreach ($ln as $x) {
        $nidadas[$x['id_nidada']] = ['id_cruce' => $x['id_cruce'], 'pareja' => $x['id_pareja'], 'cruce' => $x['fecha_cruce'], 'nacimiento' => $x['fecha_nacimiento']];
    }

    $criaDe = [];
    foreach ($lr as $x) $criaDe[$x['id_canario']] = $x;

    $pend = $_SESSION['correcciones_pendientes'] ?? [];
    $canarios = [];
    foreach ($lc as $x) {
        $k = $clavePorId[$x['id_canario']];
        $cr = $criaDe[$x['id_canario']] ?? null;
        $n = $cr ? ($nidadas[$cr['id_nidada']] ?? null) : null;
        $p = $n ? ($parejas[$n['pareja']] ?? null) : null;
        $canarios[$k] = [
            'id' => $x['id_canario'], 'id_cria' => $cr['id_cria'] ?? null,
            'numero' => (int)$x['anillo'], 'club' => $x['club_sigla'], 'socio' => (int)$x['numero_socio'], 'temp' => (int)$x['temporada'],
            'sexo' => ['M' => 'Macho', 'H' => 'Hembra'][$x['sexo'] ?? ''] ?? '',
            'variedad' => $x['id_variedad'] ? cod_variedad($x['id_variedad']) : '',
            'portadora' => $cr['mutacion_nombre'] ?? '', 'reservada' => (bool)($cr['reservada'] ?? false),
            'estado' => isset($pend[$k]) ? 'correccion' : ($x['requiere_revision'] ? 'revision' : ''),
            'padre' => $p['macho'] ?? null, 'madre' => $p['hembra'] ?? null,
            'nacimiento' => $n['nacimiento'] ?? null, 'nidada' => $cr['id_nidada'] ?? null,
        ];
    }

    $titulos = [];
    foreach ($lt as $x) $titulos[$x['id_titulo']] = ['canario' => $clavePorId[$x['id_canario']] ?? '', 'nombre' => $x['nombre'], 'fecha' => $x['fecha']];

    $jaulas = [];
    foreach ($lj as $x) $jaulas[(int)$x['numero_jaula']] = $x['id_jaula'];

    $db = ['canarios' => $canarios, 'parejas' => $parejas, 'nidadas' => $nidadas, 'titulos' => $titulos, 'jaulas' => $jaulas];
    return $db;
}

// ---------- Canarios ----------
function clave($c) { return "{$c['numero']}-{$c['club']}-{$c['socio']}-{$c['temp']}"; }
function anillo_txt($c) { return "{$c['numero']} · {$c['club']} · {$c['socio']} · {$c['temp']}"; }
// Anillo con el número en negrita y el resto en gris (como en el Figma)
function anillo_html($c, $simbolo = false) {
    $s = $simbolo && $c['sexo'] ? ($c['sexo'] === 'Macho' ? ' ♂' : ' ♀') : '';
    return '<strong>' . e($c['numero']) . '</strong> <span class="muted">· ' . e("{$c['club']} · {$c['socio']} · {$c['temp']}") . '</span>' . $s;
}

function canarios() { return db()['canarios']; }
function canario($k) { return db()['canarios'][$k] ?? null; }

function guardar_canario($c, $claveAnterior = null) {
    $k = clave($c);
    $sexo = ['Macho' => 'M', 'Hembra' => 'H'][$c['sexo']] ?? null;
    $idVar = $c['variedad'] ? id_variedad($c['variedad']) : null;

    // «Corrección solicitada» no tiene endpoint: se recuerda en la sesión
    if (($c['estado'] ?? '') === 'correccion') $_SESSION['correcciones_pendientes'][$k] = true;
    else unset($_SESSION['correcciones_pendientes'][$k]);

    if (!empty($c['id'])) {
        $cuerpo = ['anillo' => (string)$c['numero'], 'id_club' => id_club($c['club']), 'numero_socio' => (string)$c['socio'], 'temporada' => (int)$c['temp']];
        if ($sexo) $cuerpo['sexo'] = $sexo;
        if ($idVar) $cuerpo['id_variedad'] = $idVar;
        api_escribir('PATCH', '/api/v1/canarios/' . $c['id'], $cuerpo);
        if (!empty($c['id_cria'])) {
            api_escribir('PATCH', '/api/v1/crias/' . $c['id_cria'], [
                'reservada' => (bool)$c['reservada'],
                'factor_genetico' => $c['portadora'] ? id_mutacion($c['portadora']) : null,
            ]);
        }
        return;
    }

    $nuevo = api_escribir('POST', '/api/v1/canarios', [
        'anillo' => (string)$c['numero'], 'id_club' => id_club($c['club']), 'numero_socio' => (string)$c['socio'],
        'temporada' => (int)$c['temp'], 'sexo' => $sexo, 'id_variedad' => $idVar,
    ]);
    if (!empty($c['nidada'])) {
        api_escribir('POST', '/api/v1/crias', [
            'id_nidada' => (int)$c['nidada'], 'id_canario' => $nuevo['id_canario'],
            'factor_genetico' => $c['portadora'] ? id_mutacion($c['portadora']) : null, 'reservada' => (bool)$c['reservada'],
        ]);
    }
}
function por_sexo($sexo) {
    return array_filter(canarios(), fn($c) => $c['sexo'] === $sexo);
}
// La API exige sexo y variedad al registrar, así que solo quedarían pendientes datos sin completar
function es_pendiente($c) { return $c['sexo'] === '' || $c['variedad'] === ''; }

// ---------- Parejas ----------
function parejas() { return db()['parejas']; }
function pareja($id) { return db()['parejas'][$id] ?? null; }

// $id = null crea la pareja y devuelve su id real; con id: finaliza/anula y registra los cruces nuevos
function guardar_pareja($id, $p) {
    $db = db();
    if ($id === null || !isset($db['parejas'][$id])) {
        $idJaula = $db['jaulas'][$p['jaula']] ?? null;
        if (!$idJaula) $idJaula = api_escribir('POST', '/api/v1/jaulas', ['numero_jaula' => (int)$p['jaula']])['id_jaula'];
        $m = canario($p['macho']); $h = canario($p['hembra']);
        return api_escribir('POST', '/api/v1/parejas', ['id_macho' => $m['id'], 'id_hembra' => $h['id'], 'id_jaula' => $idJaula])['id_pareja'];
    }
    $antes = $db['parejas'][$id];
    if ($antes['macho'] !== $p['macho'] || $antes['hembra'] !== $p['hembra']) {
        $_SESSION['flash_error'] = 'La API no permite cambiar el macho o la hembra de una pareja existente. Anule la pareja y cree una nueva.';
        header('Location: ' . ($_SERVER['REQUEST_URI'] ?? 'parejas.php'));
        exit;
    }
    foreach (array_diff($p['cruces'], $antes['cruces']) as $f) {
        api_escribir('POST', '/api/v1/cruces', ['id_pareja' => (int)$id, 'fecha_cruce' => $f]);
    }
    if ($p['estado'] !== $antes['estado']) {
        api_escribir('PATCH', '/api/v1/parejas/' . $id, ['estado' => mb_strtolower($p['estado']), 'fecha_fin' => $p['fin'] ?? hoy()]);
    }
    return $id;
}
function parejas_activas_de($k) {
    return array_filter(parejas(), fn($p) => $p['estado'] === 'Activa' && ($p['macho'] === $k || $p['hembra'] === $k));
}
function parejas_de($k) {
    return array_filter(parejas(), fn($p) => $p['macho'] === $k || $p['hembra'] === $k);
}
function jaulas_ocupadas() {
    $j = array_column(array_filter(parejas(), fn($p) => $p['estado'] === 'Activa'), 'jaula');
    sort($j);
    return $j;
}

// ---------- Nidadas / crías ----------
function nidadas() { return db()['nidadas']; }
function nidada($id) { return db()['nidadas'][$id] ?? null; }
// Crea la nidada sobre el cruce (pareja + fecha) y devuelve su id real
function guardar_nidada($id, $n) {
    $cruce = null;
    foreach (api_lista('/api/v1/cruces/pareja/' . (int)$n['pareja']) as $x) if ($x['fecha_cruce'] === $n['cruce']) $cruce = $x['id_cruce'];
    if (!$cruce) { $_SESSION['flash_error'] = 'No se encontró el cruce de esa pareja.'; header('Location: nidada_registrar.php'); exit; }
    return api_escribir('POST', '/api/v1/nidadas', ['id_cruce' => $cruce, 'fecha_nacimiento' => $n['nacimiento']])['id_nidada'];
}
function crias_de_nidada($id) {
    return array_filter(canarios(), fn($c) => $c['nidada'] === $id);
}
function nidadas_de_pareja($pid) {
    return array_filter(nidadas(), fn($n) => $n['pareja'] === $pid);
}
function crias_de_pareja($pid) {
    $ids = array_keys(nidadas_de_pareja($pid));
    return array_filter(canarios(), fn($c) => in_array($c['nidada'], $ids, true));
}

// ---------- Títulos ----------
function titulos() {
    $t = db()['titulos'];
    uasort($t, fn($a, $b) => strcmp($b['fecha'], $a['fecha']));
    return $t;
}
function titulos_de($k) { return array_filter(titulos(), fn($t) => $t['canario'] === $k); }
function guardar_titulo($t) {
    $c = canario($t['canario']);
    api_escribir('POST', '/api/v1/titulos', ['id_canario' => $c['id'], 'nombre' => $t['nombre'], 'fecha' => $t['fecha']]);
}

// ---------- Validaciones comunes de anillo ----------
// Devuelve [campo => mensaje]
function validar_anillo($numero, $club, $socio, $temp) {
    $err = [];
    if (!preg_match('/^\d{1,6}$/', $numero)) $err['numero'] = 'Use solo dígitos (1 a 6).';
    if (!in_array($club, CLUBES, true)) $err['club'] = 'Elija CON, COV, COR o SOCH.';
    if (!preg_match('/^\d{1,5}$/', $socio)) $err['socio'] = 'Use solo dígitos (1 a 5).';
    if (!preg_match('/^\d{4}$/', $temp)) $err['temp'] = 'Temporada inválida.';
    return $err;
}

// ---------- Usuarios ----------
// Inicia sesión en la API (200 con data.token y data.user)
function iniciar_sesion_api($correo, $clave) {
    return api('POST', '/api/login', ['correo' => $correo, 'password' => $clave], false);
}
// Reconfirma la contraseña del usuario actual (Modo de Corrección)
function verificar_clave($correo, $clave) {
    return iniciar_sesion_api($correo, $clave)['status'] === 200;
}

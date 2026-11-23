<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

$v = ['ejemplar' => $_GET['ejemplar'] ?? '', 'nombre' => '', 'fecha' => ''];
$err = [];

// Lista de ejemplares para el autocompletar: "2901 · SOCH · 123 · 2024"
$opciones = [];
foreach (canarios() as $k => $c) $opciones[anillo_txt($c)] = $k;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    foreach ($v as $k => $_) $v[$k] = trim($_POST[$k] ?? '');
    $clave = $opciones[$v['ejemplar']] ?? null;
    if ($v['ejemplar'] === '') $err['ejemplar'] = 'Elija el ejemplar.';
    elseif (!$clave) $err['ejemplar'] = 'Ese anillo no está registrado en su criadero.';
    if ($v['nombre'] === '') $err['nombre'] = 'Ingrese el nombre del título.';
    elseif (mb_strlen($v['nombre']) > 100) $err['nombre'] = 'Máximo 100 caracteres.';
    if ($v['fecha'] === '') $err['fecha'] = 'Ingrese la fecha del título.';
    elseif ($v['fecha'] > hoy()) $err['fecha'] = 'La fecha no puede ser posterior a hoy.';

    if (!$err) {
        guardar_titulo(['canario' => $clave, 'nombre' => $v['nombre'], 'fecha' => $v['fecha']]);
        redirigir('titulos.php', 'Título guardado', "{$v['nombre']} · {$v['ejemplar']}");
    }
}
if ($v['ejemplar'] !== '' && isset($opciones[$v['ejemplar']]) === false && canario($v['ejemplar'])) {
    $v['ejemplar'] = anillo_txt(canario($v['ejemplar'])); // vino por GET con la clave
}

// títulos por ejemplar para el panel lateral
$porEjemplar = [];
foreach ($opciones as $txt => $k) {
    $c = canario($k);
    $porEjemplar[$txt] = [
        'badge' => trim(($c['sexo'] ?: 'Pendiente') . ($c['variedad'] ? ' · ' . $c['variedad'] : '')),
        'titulos' => array_values(array_map(fn($t) => ['nombre' => $t['nombre'], 'fecha' => fecha($t['fecha'])], titulos_de($k))),
    ];
}

$pagina = 'titulos';
$titulo = 'Registrar título';
include __DIR__ . '/../includes/header.php';
$msg = fn($campo) => isset($err[$campo]) ? '<span class="msg-error">' . e($err[$campo]) . '</span>' : '';
?>

<p class="migas"><a href="titulos.php">Títulos</a> / Registrar título</p>
<div>
  <p class="eyebrow">Títulos de competencia</p>
  <h1 class="titulo-l">Registrar título</h1>
  <p class="bajada">Asocie el título obtenido en un concurso al anillo de uno de sus ejemplares.</p>
</div>

<form method="POST" novalidate>
  <div class="dos-col" style="grid-template-columns:1fr 360px">
    <section class="seccion" style="min-height:460px">
      <?php if ($err): ?>
        <div class="aviso aviso-error"><?= icono('alerta') ?><div><strong>No se pudo guardar el título</strong><p>Revise los campos marcados.</p></div></div>
      <?php endif; ?>
      <div class="campo<?= isset($err['ejemplar']) ? ' error' : '' ?>">
        <label for="ejemplar">Ejemplar (anillo)</label>
        <div style="position:relative">
          <?= str_replace('class="ico"', 'class="ico" style="position:absolute;left:12px;top:12px"', icono('buscar')) ?>
          <input class="input" id="ejemplar" name="ejemplar" list="lista-ejemplares" autocomplete="off" placeholder="Escriba el número de anillo" style="padding-left:36px;padding-right:120px" value="<?= e($v['ejemplar']) ?>">
          <span class="badge" id="badgeEjemplar" style="position:absolute;right:10px;top:9px;display:none"></span>
        </div>
        <datalist id="lista-ejemplares"><?php foreach ($opciones as $txt => $k): ?><option value="<?= e($txt) ?>"><?php endforeach; ?></datalist>
        <?= $msg('ejemplar') ?: '<span class="ayuda-campo">Solo puede elegir ejemplares registrados en su criadero.</span>' ?>
      </div>
      <div class="campo<?= isset($err['nombre']) ? ' error' : '' ?>">
        <label for="nombre" style="display:flex;justify-content:space-between">Nombre del título <span class="small muted" id="cuenta">0 / 100</span></label>
        <input class="input" id="nombre" name="nombre" maxlength="100" data-contador="cuenta" placeholder="Ej.: 1.er lugar, Campeonato Nacional SOCH 2026" value="<?= e($v['nombre']) ?>">
        <?= $msg('nombre') ?>
      </div>
      <div class="campo<?= isset($err['fecha']) ? ' error' : '' ?>" style="width:220px">
        <label for="fecha">Fecha del título</label>
        <input class="input" type="date" id="fecha" name="fecha" max="<?= hoy() ?>" value="<?= e($v['fecha']) ?>">
        <?= $msg('fecha') ?>
      </div>
    </section>

    <aside class="panel-gris" style="min-height:460px">
      <h3><?= icono('trofeo') ?> Títulos de este ejemplar</h3>
      <div id="titulosEjemplar" style="display:flex;flex-direction:column;gap:8px"><p class="muted">Elija un ejemplar para ver sus títulos.</p></div>
      <p class="muted xs" style="margin-top:auto">El título queda asociado al anillo. Después podrá ver todas las crías del ejemplar agrupadas por pareja.</p>
    </aside>
  </div>
  <div class="acciones-form" style="margin-top:20px">
    <a href="titulos.php" class="btn">Cancelar</a>
    <button class="btn btn-primario">Guardar título</button>
  </div>
</form>

<script>
  const datos = <?= json_encode($porEjemplar, JSON_UNESCAPED_UNICODE) ?>;
  const inp = document.getElementById('ejemplar'), cont = document.getElementById('titulosEjemplar'), badge = document.getElementById('badgeEjemplar');
  const esc = s => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  function upd() {
    const d = datos[inp.value.trim()];
    badge.style.display = d ? '' : 'none';
    if (!d) { cont.innerHTML = '<p class="muted">Elija un ejemplar para ver sus títulos.</p>'; return; }
    badge.textContent = d.badge;
    cont.innerHTML = d.titulos.length
      ? d.titulos.map(t => `<div class="nodo" style="background:#fff"><strong>${esc(t.nombre)}</strong><span>${t.fecha}</span></div>`).join('')
      : '<p class="muted">Este ejemplar aún no tiene títulos.</p>';
  }
  inp.addEventListener('input', upd); upd();
</script>

<?php include __DIR__ . '/../includes/footer.php'; ?>

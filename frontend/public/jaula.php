<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

$pid = (int)($_GET['id'] ?? 0);
$p = pareja($pid);
if (!$p) redirigir('parejas.php', 'Pareja no encontrada', '');
$url = "jaula.php?id=$pid";
$m = canario($p['macho']);
$h = canario($p['hembra']);
$activa = $p['estado'] === 'Activa';

$err = [];
$modal_abierto = $activa ? ($_GET['modal'] ?? '') : '';
$fecha_cruce = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && $activa) {
    if (($_POST['accion'] ?? '') === 'cruce') {
        $fecha_cruce = $_POST['fecha'] ?? '';
        if ($fecha_cruce === '') $err['fecha'] = 'Ingrese la fecha del cruce.';
        elseif ($fecha_cruce > hoy()) $err['fecha'] = 'La fecha no puede ser posterior a hoy (' . fecha(hoy()) . ').';
        elseif ($fecha_cruce < $p['desde']) $err['fecha'] = 'La fecha no puede ser anterior a la formación de la pareja (' . fecha($p['desde']) . ').';
        elseif (in_array($fecha_cruce, $p['cruces'], true)) $err['fecha'] = 'Ya hay un cruce registrado en esa fecha.';
        if ($err) { $modal_abierto = 'cruce'; }
        else {
            $p['cruces'][] = $fecha_cruce;
            guardar_pareja($pid, $p);
            redirigir($url, 'Cruce registrado', 'Fecha de cruce: ' . fecha($fecha_cruce) . '. Ahora puede registrar la nidada desde Crías.');
        }
    }
    if (($_POST['accion'] ?? '') === 'finalizar') {
        $p['estado'] = 'Finalizada';
        $p['fin'] = hoy();
        guardar_pareja($pid, $p);
        redirigir('parejas.php', 'Pareja finalizada', "La jaula {$p['jaula']} quedó libre.");
    }
}

$cruces = $p['cruces'];
rsort($cruces);
$nids = nidadas_de_pareja($pid);
$nidadaPorCruce = [];
foreach ($nids as $nid => $n) $nidadaPorCruce[$n['cruce']] = [$nid, $n, count(crias_de_nidada($nid))];

// Historial (se arma a partir de los datos)
$hist = [[$p['desde'], 'Pareja creada en la jaula ' . $p['jaula']]];
foreach ($p['cruces'] as $cf) $hist[] = [$cf, 'Cruce registrado'];
foreach ($nids as $nid => $n) $hist[] = [$n['nacimiento'], 'Nidada registrada (' . ($nc = count(crias_de_nidada($nid))) . ($nc === 1 ? ' cría)' : ' crías)')];
if (!empty($p['fin'])) $hist[] = [$p['fin'], 'Pareja finalizada'];
usort($hist, fn($a, $b) => strcmp($b[0], $a[0]));

$prev = array_map('fecha', $cruces);
$pagina = 'parejas';
$titulo = 'Jaula ' . $p['jaula'];
include __DIR__ . '/../includes/header.php';
$tarjeta = function ($rol, $c) {
    return '<section class="card" style="padding:20px 24px"><div style="display:flex;justify-content:space-between"><span class="small muted">' . $rol . '</span><a class="link" href="canario_ficha.php?id=' . e(urlencode(clave($c))) . '">Ver ficha ' . icono('chevron', 12) . '</a></div>'
        . '<div style="font-size:22px;margin:8px 0">' . anillo_html($c) . '</div><div class="badges">' . ($c['variedad'] ? '<span class="badge">' . e(variedad_txt($c['variedad'])) . '</span>' : '') . '</div></section>';
};
?>

<?= flash() ?>

<a href="parejas.php" class="volver"><?= icono('atras', 14) ?> Volver a Mis parejas</a>
<div class="page-head" style="align-items:flex-start">
  <div>
    <h1 class="titulo-l" style="display:flex;gap:12px;align-items:center">Jaula <?= e($p['jaula']) ?> <span class="badge <?= ['Activa' => 'badge-oscuro', 'Anulada' => 'badge-tenue'][$p['estado']] ?? '' ?>" style="font-size:13px;letter-spacing:0;line-height:1.4;font-weight:400"><?= e($p['estado']) ?></span></h1>
    <p class="muted" style="margin-top:8px">Pareja formada el <?= e(fecha($p['desde'])) ?></p>
  </div>
  <?php if ($activa): ?>
  <div style="display:flex;gap:12px">
    <button class="btn btn-lg" style="min-width:0" data-modal="finalizar"><?= icono('cuadrado', 14) ?> Finalizar pareja</button>
    <button class="btn btn-primario btn-lg" style="min-width:0" data-modal="cruce"><?= icono('corazon', 14) ?> Registrar cruce</button>
  </div>
  <?php endif; ?>
</div>

<div class="dos-col-igual">
  <?= $tarjeta('Macho', $m) ?>
  <?= $tarjeta('Hembra', $h) ?>

  <section class="card" style="min-height:420px;display:flex;flex-direction:column;gap:12px">
    <h2 style="font-size:18px;font-weight:600;display:flex;justify-content:space-between">Cruces <span class="badge"><?= count($cruces) ?></span></h2>
    <?php if ($cruces): ?>
    <table class="tabla" style="max-width:none">
      <thead><tr><th>Fecha de cruce</th><th>Nidada (nacimiento)</th><th></th></tr></thead>
      <tbody>
      <?php foreach ($cruces as $cf): $nd = $nidadaPorCruce[$cf] ?? null; ?>
        <tr>
          <td><?= e(fecha($cf)) ?></td>
          <td><?= $nd ? e(fecha($nd[1]['nacimiento'])) . ' · ' . $nd[2] . ($nd[2] === 1 ? ' cría' : ' crías') : '<span class="muted">Sin nidada</span>' ?></td>
          <td class="acciones"><?= $nd ? '<a class="link" href="crias.php?pareja=' . $pid . '">Ver crías ' . icono('chevron', 12) . '</a>' : ($activa ? '<a class="link" href="nidada_registrar.php?cruce=' . $pid . '_' . e($cf) . '">Registrar nidada ' . icono('chevron', 12) . '</a>' : '') ?></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
    <?php else: ?>
      <p class="small muted">Aún no hay cruces. <?= $activa ? 'Use «Registrar cruce» cuando ocurra.' : '' ?></p>
    <?php endif; ?>
    <p class="small muted" style="margin-top:auto">Una pareja puede tener varios cruces. Cada nidada se registra desde Crías a partir de un cruce.</p>
  </section>

  <section class="card" style="min-height:420px">
    <h2 style="font-size:18px;font-weight:600">Historial</h2>
    <div class="historial">
      <?php foreach ($hist as [$f, $txt]): ?><div><span><?= e(fecha($f)) ?></span><span><?= e($txt) ?></span></div><?php endforeach; ?>
    </div>
  </section>
</div>

<?php if ($activa): ?>
<!-- Modal: Registrar cruce -->
<?= modal_inicio('cruce', 'Registrar cruce', 'Jaula ' . e($p['jaula']) . ' · ' . e($m['numero']) . ' ♂ × ' . e($h['numero']) . ' ♀',
    $prev ? 'Cruces anteriores: ' . e(implode(' y ', array_slice($prev, 0, 3))) : 'Es el primer cruce de esta pareja', $modal_abierto === 'cruce') ?>
<form method="POST" style="display:flex;flex-direction:column;gap:18px" novalidate>
  <input type="hidden" name="accion" value="cruce">
  <hr style="border:0;border-top:1px solid var(--gris-linea)">
  <div class="campo<?= isset($err['fecha']) ? ' error' : '' ?>">
    <label for="fecha">Fecha de cruce</label>
    <input class="input" type="date" id="fecha" name="fecha" max="<?= hoy() ?>" value="<?= e($fecha_cruce ?: hoy()) ?>">
    <?= isset($err['fecha']) ? '<span class="msg-error">' . e($err['fecha']) . '</span>' : '' ?>
  </div>
  <div class="acciones-form"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn btn-primario">Guardar cruce</button></div>
</form>
<?= modal_fin() ?>

<!-- Modal: Finalizar pareja -->
<?= modal_inicio('finalizar', 'Finalizar pareja', '¿Finalizar la pareja de la jaula ' . e($p['jaula']) . '?',
    e($m['numero']) . ' ♂ × ' . e($h['numero']) . ' ♀ · activa desde el ' . e(fecha($p['desde'])), $modal_abierto === 'finalizar') ?>
<form method="POST" style="display:flex;flex-direction:column;gap:18px" novalidate>
  <input type="hidden" name="accion" value="finalizar">
  <ul class="lista-check">
    <li><?= icono('check') ?> <span>La pareja pasa a estado <strong>Finalizada</strong>.</span></li>
    <li><?= icono('check') ?> <span>Se conservan sus <?= count($p['cruces']) ?> cruces y <?= count($nids) ?> nidadas en el historial.</span></li>
    <li><?= icono('check') ?> <span>La <strong>jaula <?= e($p['jaula']) ?> queda libre</strong> para otra pareja.</span></li>
    <li><?= icono('check') ?> <span>La hembra podrá formar una nueva pareja.</span></li>
  </ul>
  <div class="aviso"><?= icono('info') ?><div><strong>No se puede deshacer</strong><p>Para volver a juntarlos, registre una pareja nueva.</p></div></div>
  <div class="acciones-form"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn btn-primario"><?= icono('cuadrado', 14) ?> Finalizar pareja</button></div>
</form>
<?= modal_fin() ?>
<?php endif; ?>

<?php include __DIR__ . '/../includes/footer.php'; ?>

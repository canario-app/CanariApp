<?php
$pagina = 'parejas';
$titulo = 'Parejas y cruces';
include __DIR__ . '/../includes/header.php';

$todas = parejas();
uasort($todas, fn($a, $b) => [$a['estado'] !== 'Activa', $a['jaula']] <=> [$b['estado'] !== 'Activa', $b['jaula']]);
$cuenta = array_count_values(array_column($todas, 'estado'));
$activas = $cuenta['Activa'] ?? 0;
$finalizadas = $cuenta['Finalizada'] ?? 0;
$anuladas = $cuenta['Anulada'] ?? 0;

$tab = $_GET['tab'] ?? 'Todas';
$q = trim($_GET['q'] ?? '');
$f_temp = $_GET['temporada'] ?? '';

$lista = array_filter($todas, function ($p) use ($tab, $q, $f_temp) {
    if ($tab !== 'Todas' && $p['estado'] !== $tab) return false;
    $m = canario($p['macho']); $h = canario($p['hembra']);
    if ($q !== '') {
        $num = preg_replace('/\D/', '', $q);
        $esJaula = stripos($q, 'jaula') !== false;
        $ok = $esJaula ? (string)$p['jaula'] === $num
                       : ($num !== '' && (str_starts_with((string)$m['numero'], $num) || str_starts_with((string)$h['numero'], $num) || (string)$p['jaula'] === $num));
        if (!$ok) return false;
    }
    if ($f_temp !== '' && substr($p['desde'], 0, 4) !== $f_temp) return false;
    return true;
});
$temporadas = array_unique(array_map(fn($p) => substr($p['desde'], 0, 4), $todas));
rsort($temporadas);

$badge = ['Activa' => 'badge-oscuro', 'Finalizada' => '', 'Anulada' => 'badge-tenue'];
$plural = fn($n, $s) => $n . ' ' . $s . ($n == 1 ? '' : 's');
$tabs = ['Todas' => count($todas), 'Activa' => $activas, 'Finalizada' => $finalizadas, 'Anulada' => $anuladas];
$tabTxt = ['Todas' => 'Todas', 'Activa' => 'Activas', 'Finalizada' => 'Finalizadas', 'Anulada' => 'Anuladas'];
?>

<?= flash() ?>

<div class="page-head">
  <div>
    <p class="eyebrow">Parejas y cruces</p>
    <h1 class="titulo-l">Mis parejas</h1>
    <p class="bajada">Forme parejas en una jaula, registre cada cruce y finalícelas cuando terminen para liberar la jaula.</p>
  </div>
  <a href="pareja_registrar.php" class="btn btn-primario"><?= icono('mas') ?> Registrar pareja</a>
</div>

<div class="stats">
  <div class="stat"><span>Parejas activas</span><strong><?= $activas ?></strong></div>
  <div class="stat"><span>Finalizadas</span><strong><?= $finalizadas ?></strong></div>
  <div class="stat"><span>Anuladas</span><strong><?= $anuladas ?></strong></div>
  <div class="stat"><span>Jaulas ocupadas</span><strong><?= count(jaulas_ocupadas()) ?></strong></div>
</div>

<div class="panel">
  <nav class="tabs">
    <?php foreach ($tabs as $t => $n): ?>
      <a href="?<?= e(http_build_query(['tab' => $t, 'q' => $q, 'temporada' => $f_temp])) ?>" class="<?= $tab === $t ? 'activo' : '' ?>"><?= $tabTxt[$t] ?> (<?= $n ?>)</a>
    <?php endforeach; ?>
  </nav>

  <form class="filtros-campos" method="GET">
    <input type="hidden" name="tab" value="<?= e($tab) ?>">
    <div class="campo">
      <label for="q">Buscar por anillo o jaula</label>
      <div class="input-icono izq">
        <?= str_replace('class="ico"', 'class="ico" style="position:absolute;left:12px;top:12px"', icono('buscar')) ?>
        <input class="input" id="q" name="q" placeholder="Ej.: 2901 o jaula 4" style="width:300px;padding-left:36px" value="<?= e($q) ?>">
      </div>
    </div>
    <div class="campo">
      <label for="temporada">Temporada</label>
      <select class="input" id="temporada" name="temporada" style="width:150px" onchange="this.form.submit()">
        <?= select_opciones(array_map('strval', $temporadas), $f_temp, 'Todas') ?>
      </select>
    </div>
  </form>

  <?php if (!$lista): ?>
    <div class="vacio" style="min-height:300px">
      <div class="circulo"><?= icono('corazon', 24) ?></div>
      <h3><?= $todas ? 'No hay parejas con estos filtros' : 'Aún no hay parejas registradas' ?></h3>
      <p><?= $todas ? 'Pruebe con otra búsqueda.' : 'Forme su primera pareja eligiendo un macho, una hembra y una jaula libre.' ?></p>
      <div class="acciones"><a href="pareja_registrar.php" class="btn btn-primario"><?= icono('mas') ?> Registrar pareja</a></div>
    </div>
  <?php else: ?>
  <table class="tabla">
    <thead>
      <tr><th>Jaula</th><th>Macho</th><th>Hembra</th><th>Estado</th><th>Actividad</th><th></th></tr>
    </thead>
    <tbody>
      <?php foreach ($lista as $pid => $p):
        $activa = $p['estado'] === 'Activa';
        $m = canario($p['macho']); $h = canario($p['hembra']);
        $cr = $p['cruces']; $ult = $cr ? max($cr) : null;
        $nn = count(nidadas_de_pareja($pid));
      ?>
      <tr>
        <td><strong><?= $activa ? e($p['jaula']) : '—' ?></strong></td>
        <td><strong><?= e($m['numero']) ?> ♂</strong><span class="sub"><?= e("{$m['club']} · {$m['socio']} · {$m['temp']}") ?></span></td>
        <td><strong><?= e($h['numero']) ?> ♀</strong><span class="sub"><?= e("{$h['club']} · {$h['socio']} · {$h['temp']}") ?></span></td>
        <td><span class="badge <?= $badge[$p['estado']] ?>"><?= e($p['estado']) ?></span></td>
        <td>
          <?= $plural(count($cr), 'cruce') ?> · <?= $plural($nn, 'nidada') ?>
          <span class="sub"><?= $ult ? 'Último cruce: ' . e(fecha($ult)) : 'Aún sin cruces' ?></span>
        </td>
        <td class="acciones">
          <?php if ($activa): ?>
            <a href="jaula.php?id=<?= $pid ?>&modal=cruce" class="btn btn-sm"><?= icono('corazon', 14) ?> Registrar cruce</a>
            <a href="jaula.php?id=<?= $pid ?>&modal=finalizar" class="btn btn-sm" style="background:none;border:0">Finalizar</a>
            <a href="jaula.php?id=<?= $pid ?>" aria-label="Ver jaula"><?= icono('chevron') ?></a>
          <?php else: ?>
            <a href="jaula.php?id=<?= $pid ?>" class="small">Ver detalle</a>
          <?php endif; ?>
        </td>
      </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
  <?php endif; ?>

  <p class="xs muted">Las parejas finalizadas y anuladas se conservan en el historial con sus cruces y nidadas.</p>
</div>

<?php include __DIR__ . '/../includes/footer.php'; ?>

<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

// Se puede llegar con ?id=CLAVE o buscando el anillo en la caja de arriba (?anillo=2901)
$k = $_GET['id'] ?? '';
if (!canario($k) && ($num = trim($_GET['anillo'] ?? '')) !== '') {
    foreach (canarios() as $ck => $c) if ((string)$c['numero'] === preg_replace('/\D.*/', '', $num)) { $k = $ck; break; }
}
$c = canario($k);
if (!$c) redirigir('titulos.php', 'Ejemplar no encontrado', 'Ese anillo no está registrado en su criadero.');

$es_macho = $c['sexo'] !== 'Hembra';
$rol_otro = $es_macho ? 'hembra' : 'macho';
$grupos = [];
foreach (parejas_de($k) as $pid => $p) {
    $crias = crias_de_pareja($pid);
    if ($crias) $grupos[$pid] = [$p, canario($p[$rol_otro]), $crias];
}
$total = array_sum(array_map(fn($g) => count($g[2]), $grupos));

$pagina = 'titulos';
$titulo = 'Crías de un ganador';
include __DIR__ . '/../includes/header.php';
?>

<p class="migas"><a href="titulos.php">Títulos</a> / Crías de un ganador</p>
<div class="page-head" style="align-items:center">
  <div>
    <p class="eyebrow">Títulos de competencia</p>
    <h1 class="titulo-l">Crías de un ganador</h1>
    <p class="bajada">Todas las crías del ejemplar, separadas por <?= $es_macho ? 'la hembra' : 'el macho' ?> con que se cruzó.</p>
  </div>
  <form method="GET" class="input-icono izq" style="width:360px">
    <?= str_replace('class="ico"', 'class="ico" style="position:absolute;left:12px;top:12px"', icono('buscar')) ?>
    <input class="input" name="anillo" placeholder="Buscar otro anillo" style="padding-left:36px" value="<?= e(anillo_txt($c)) ?>" onfocus="this.select()">
  </form>
</div>

<section class="card" style="display:flex;justify-content:space-between;align-items:center;gap:24px">
  <div>
    <div style="font-size:28px"><?= anillo_html($c) ?></div>
    <div class="badges"><?= badges_canario($c, false) ?></div>
  </div>
  <div style="display:flex;flex-direction:column;gap:6px;font-size:14px;text-align:right">
    <?php foreach (titulos_de($k) as $t): ?>
      <div><?= icono('trofeo', 14) ?> <strong><?= e($t['nombre']) ?></strong> <span class="muted">· <?= e(fecha($t['fecha'])) ?></span></div>
    <?php endforeach; ?>
    <?php if (!titulos_de($k)): ?><span class="muted">Sin títulos registrados</span><?php endif; ?>
  </div>
</section>

<?php if (!$grupos): ?>
  <div class="vacio">
    <div class="circulo"><?= icono('huevo', 24) ?></div>
    <h3>Este ejemplar no tiene crías registradas</h3>
    <p>Cuando registre nidadas de sus parejas, sus crías aparecerán aquí agrupadas por <?= $es_macho ? 'la hembra' : 'el macho' ?> con que se cruzó.</p>
    <div class="acciones"><a href="crias.php" class="btn btn-primario">Ir a Crías</a></div>
  </div>
<?php else: ?>
  <h2 style="font-size:18px;font-weight:600"><?= $total ?> crías en <?= count($grupos) ?> pareja<?= count($grupos) > 1 ? 's' : '' ?></h2>
  <div class="dos-col-igual">
    <?php foreach ($grupos as $pid => [$p, $otro, $crias]): ?>
    <section class="nidada-card" style="min-height:300px">
      <div class="grupo-head">
        <div>
          <p class="eyebrow">Cruzado con</p>
          <strong><?= e(anillo_txt($otro)) ?> <?= $es_macho ? '♀' : '♂' ?></strong>
          <div class="xs muted"><?= e(variedad_txt($otro['variedad'])) ?> · Jaula <?= e($p['jaula']) ?><?= $p['estado'] !== 'Activa' ? ' · pareja ' . e(mb_strtolower($p['estado'])) : '' ?></div>
        </div>
        <span class="badge"><?= count($crias) ?> crías</span>
      </div>
      <table class="tabla" style="max-width:none">
        <thead><tr><th>Anillo</th><th>Sexo</th><th>Variedad</th><th>Marcas y títulos</th></tr></thead>
        <tbody>
        <?php foreach ($crias as $ck => $cr): $nt = count(titulos_de($ck)); ?>
          <tr>
            <td><a href="canario_ficha.php?id=<?= e(urlencode($ck)) ?>"><?= anillo_html($cr) ?></a></td>
            <td><?= $cr['sexo'] ? e($cr['sexo']) : '<span class="badge badge-tenue">Pendiente</span>' ?></td>
            <td><?= $cr['variedad'] ? e(variedad_txt($cr['variedad'])) : '<span class="badge badge-tenue">Pendiente</span>' ?></td>
            <td><?= $nt ? '<span class="badge badge-oscuro">Con título</span> ' : '' ?><?= ($cr['portadora'] || $cr['reservada'] || !$nt) ? marcas_html($cr) : '' ?></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </section>
    <?php endforeach; ?>
  </div>
<?php endif; ?>

<?php include __DIR__ . '/../includes/footer.php'; ?>

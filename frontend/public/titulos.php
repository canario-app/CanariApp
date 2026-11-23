<?php
$pagina = 'titulos';
$titulo = 'Títulos';
include __DIR__ . '/../includes/header.php';

$todos = titulos();
$q = trim($_GET['anillo'] ?? '');
$anio = $_GET['anio'] ?? '';
$lista = array_filter($todos, function ($t) use ($q, $anio) {
    $c = canario($t['canario']);
    if ($q !== '' && !str_starts_with((string)$c['numero'], $q)) return false;
    if ($anio !== '' && substr($t['fecha'], 0, 4) !== $anio) return false;
    return true;
});
$anios = array_unique(array_map(fn($t) => substr($t['fecha'], 0, 4), $todos));
rsort($anios);
$premiados = count(array_unique(array_column($todos, 'canario')));
$este_anio = count(array_filter($todos, fn($t) => substr($t['fecha'], 0, 4) === date('Y')));
?>

<?= flash() ?>

<div class="page-head" style="align-items:center">
  <div>
    <p class="eyebrow">Títulos de competencia</p>
    <h1 class="titulo-l">Títulos</h1>
    <p class="bajada">Registre los títulos de sus ejemplares y consulte las crías de un ganador, separadas por el ejemplar con que se cruzó.</p>
  </div>
  <a href="titulo_registrar.php" class="btn btn-primario btn-lg"><?= icono('mas') ?> Registrar título</a>
</div>

<?php if (!$todos): ?>
<div class="vacio">
  <div class="circulo"><img src="img/trofeo.svg" width="26" height="26" alt=""></div>
  <h3>Aún no hay títulos registrados</h3>
  <p>Registre el primer título de uno de sus ejemplares para ver aquí sus premios y consultar sus crías.</p>
  <div class="acciones">
    <a href="titulo_registrar.php" class="btn btn-primario" style="width:200px"><?= icono('mas') ?> Registrar título</a>
  </div>
</div>
<?php else: ?>

<div class="stats" style="grid-template-columns:repeat(3,1fr)">
  <div class="stat"><span>Títulos registrados</span><strong><?= count($todos) ?></strong></div>
  <div class="stat"><span>Ejemplares premiados</span><strong><?= $premiados ?></strong></div>
  <div class="stat"><span>Títulos en <?= date('Y') ?></span><strong><?= $este_anio ?></strong></div>
</div>

<div class="panel" style="padding:0;gap:0;flex:1">
  <form method="GET" class="dos-col-igual" style="padding:16px;gap:16px">
    <div class="campo">
      <label for="anillo">Buscar por anillo</label>
      <div class="input-icono izq">
        <?= str_replace('class="ico"', 'class="ico" style="position:absolute;left:12px;top:12px"', icono('buscar')) ?>
        <input class="input" id="anillo" name="anillo" placeholder="Ej.: 2901" style="padding-left:36px" value="<?= e($q) ?>">
      </div>
    </div>
    <div class="campo">
      <label for="anio">Año</label>
      <select class="input" id="anio" name="anio" onchange="this.form.submit()"><?= select_opciones(array_map('strval', $anios), $anio, 'Todos') ?></select>
    </div>
  </form>
  <table class="tabla" style="max-width:none">
    <thead><tr><th style="padding-left:16px">Anillo</th><th>Sexo</th><th>Variedad</th><th>Título</th><th>Fecha</th><th></th></tr></thead>
    <tbody>
    <?php foreach ($lista as $t): $c = canario($t['canario']); ?>
      <tr>
        <td style="padding-left:16px"><?= anillo_html($c) ?></td>
        <td><?= e($c['sexo']) ?></td>
        <td style="max-width:180px"><?= e(variedad_txt($c['variedad'])) ?></td>
        <td style="max-width:260px"><strong><?= e($t['nombre']) ?></strong></td>
        <td><?= e(fecha($t['fecha'])) ?></td>
        <td class="acciones" style="padding-right:16px"><a class="link" href="titulo_crias.php?id=<?= e(urlencode($t['canario'])) ?>">Ver crías <?= icono('chevron', 12) ?></a></td>
      </tr>
    <?php endforeach; ?>
    <?php if (!$lista): ?><tr><td colspan="6" class="muted" style="padding:24px 16px">No hay títulos con estos filtros.</td></tr><?php endif; ?>
    </tbody>
  </table>
  <p class="xs muted" style="padding:16px;margin-top:auto">Mostrando <?= count($lista) ?> título<?= count($lista) === 1 ? '' : 's' ?> de <?= count(array_unique(array_column($lista, 'canario'))) ?> ejemplar<?= count(array_unique(array_column($lista, 'canario'))) === 1 ? '' : 'es' ?></p>
</div>
<?php endif; ?>

<?php include __DIR__ . '/../includes/footer.php'; ?>

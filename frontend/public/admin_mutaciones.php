<?php
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../includes/admin.php';
requerir_login();

$res = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $res = procesar_carga('/api/v1/admin/mutaciones',
        ['nombre' => ['nombre'], 'tipo' => ['tipo de herencia', 'tipo_herencia', 'tipo']], 'errores_mutaciones');
}
$muts = api_lista('/api/v1/wiki/mutaciones');
$lig = count(array_filter($muts, fn($m) => str_starts_with($m['tipo_herencia'], 'ligada')));

$pagina = 'mutaciones';
$titulo = 'Catálogo de mutaciones';
include __DIR__ . '/../includes/header.php';
?>

<?= flash() ?>

<div>
  <p class="eyebrow">Administración</p>
  <h1 class="titulo-l">Catálogo de mutaciones</h1>
  <p class="bajada">Cargue las mutaciones que los criadores usan para marcar portadores y que el simulador genético usa para calcular los cruces.</p>
</div>

<div class="stats" style="grid-template-columns:repeat(3,1fr)">
  <div class="stat"><span>Mutaciones disponibles</span><strong><?= count($muts) ?></strong></div>
  <div class="stat"><span>Autosómicas recesivas</span><strong><?= count($muts) - $lig ?></strong></div>
  <div class="stat"><span>Ligadas al sexo</span><strong><?= $lig ?></strong></div>
</div>

<section class="seccion">
  <h2>Cargar archivo</h2>
  <p class="small muted">Archivo CSV o XLSX con las columnas <strong style="color:var(--negro)">nombre y tipo de herencia</strong>. El nombre debe ser único y no estar vacío; el tipo es «autosómica recesiva» o «ligada al sexo recesiva». Si una fila es inválida se rechaza el archivo completo y se indica la fila y la causa.</p>
  <?= resultado_carga_html($res) ?>
  <form method="POST" enctype="multipart/form-data" style="display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap">
    <div class="campo" style="flex:1;min-width:260px">
      <label for="archivo">Archivo de mutaciones</label>
      <input class="input" type="file" id="archivo" name="archivo" accept=".csv,.xlsx" style="padding-top:8px">
    </div>
    <button class="btn btn-primario"><?= icono('mas', 14) ?> Cargar mutaciones</button>
  </form>
</section>

<div class="panel" style="padding:0;gap:0">
  <table class="tabla" style="max-width:none">
    <thead><tr><th style="padding-left:16px">Mutación</th><th>Tipo de herencia</th></tr></thead>
    <tbody>
    <?php foreach ($muts as $m): ?>
      <tr><td style="padding-left:16px"><strong><?= e($m['nombre']) ?></strong></td><td><span class="badge"><?= e($m['tipo_herencia']) ?></span></td></tr>
    <?php endforeach; ?>
    <?php if (!$muts): ?><tr><td colspan="2" class="muted" style="padding:24px 16px">Todavía no hay mutaciones cargadas.</td></tr><?php endif; ?>
    </tbody>
  </table>
</div>

<?php include __DIR__ . '/../includes/footer.php'; ?>

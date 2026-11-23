<?php
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../includes/admin.php';
requerir_login();

$res = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $res = procesar_carga('/api/v1/admin/nomenclador',
        ['codigo' => ['codigo'], 'nombre' => ['nombre'], 'tipo' => ['tipo'], 'serie' => ['serie']], 'errores_nomenclador');
}

$q = trim($_GET['buscar'] ?? '');
$vars = api_lista('/api/v1/wiki/variedades' . ($q !== '' ? '?buscar=' . urlencode($q) : ''));
$total = count(api_lista('/api/v1/wiki/variedades'));
$solo_sexo = count(array_filter($vars, fn($v) => $v['sexo']));

$pagina = 'nomenclador';
$titulo = 'Nomenclador de variedades';
include __DIR__ . '/../includes/header.php';
?>

<?= flash() ?>

<div>
  <p class="eyebrow">Administración</p>
  <h1 class="titulo-l">Nomenclador de variedades</h1>
  <p class="bajada">Cargue o actualice el nomenclador oficial. Los criadores eligen de aquí la variedad de cada ejemplar.</p>
</div>

<div class="stats" style="grid-template-columns:repeat(3,1fr)">
  <div class="stat"><span>Variedades cargadas</span><strong><?= $total ?></strong></div>
  <div class="stat"><span>Que indican sexo</span><strong><?= $solo_sexo ?></strong></div>
  <div class="stat"><span>Resultados de la búsqueda</span><strong><?= count($vars) ?></strong></div>
</div>

<section class="seccion">
  <h2>Cargar archivo</h2>
  <p class="small muted">Archivo CSV o XLSX con las columnas <strong style="color:var(--negro)">código, nombre, tipo y serie</strong>. El código debe ser único y no estar vacío; el tipo es CC o CP. Si una fila es inválida se rechaza el archivo completo y se indica la fila y la causa. Las variedades nuevas se agregan y las existentes se actualizan según su código.</p>
  <?= resultado_carga_html($res) ?>
  <form method="POST" enctype="multipart/form-data" style="display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap">
    <div class="campo" style="flex:1;min-width:260px">
      <label for="archivo">Archivo del nomenclador</label>
      <input class="input" type="file" id="archivo" name="archivo" accept=".csv,.xlsx" style="padding-top:8px">
    </div>
    <button class="btn btn-primario"><?= icono('mas', 14) ?> Cargar nomenclador</button>
  </form>
  <div class="aviso"><?= icono('info') ?><p>Si la carga cambia el sexo indicado en el nombre de una variedad ya asignada, los ejemplares que dejen de coincidir no se modifican: quedan marcados «Requiere revisión» para que cada criador los reasigne.</p></div>
</section>

<div class="panel" style="padding:0;gap:0">
  <form method="GET" style="padding:16px">
    <div class="campo">
      <label for="buscar">Buscar en el nomenclador</label>
      <div class="input-icono izq">
        <?= str_replace('class="ico"', 'class="ico" style="position:absolute;left:12px;top:12px"', icono('buscar')) ?>
        <input class="input" id="buscar" name="buscar" placeholder="Código o nombre" style="padding-left:36px" value="<?= e($q) ?>">
      </div>
    </div>
  </form>
  <table class="tabla" style="max-width:none">
    <thead><tr><th style="padding-left:16px">Código</th><th>Nombre</th><th>Tipo</th><th>Serie</th><th>Sexo</th></tr></thead>
    <tbody>
    <?php foreach (array_slice($vars, 0, 100) as $v): ?>
      <tr>
        <td style="padding-left:16px"><strong><?= e($v['codigo']) ?></strong></td>
        <td><?= e($v['nombre']) ?></td>
        <td><span class="badge"><?= e($v['tipo']) ?></span></td>
        <td><?= e($v['serie'] ?? '—') ?></td>
        <td><?= $v['sexo'] ? '<span class="badge badge-borde">' . ($v['sexo'] === 'M' ? 'Macho' : 'Hembra') . '</span>' : '<span class="muted">—</span>' ?></td>
      </tr>
    <?php endforeach; ?>
    <?php if (!$vars): ?><tr><td colspan="5" class="muted" style="padding:24px 16px"><?= $q !== '' ? 'Ninguna variedad coincide con «' . e($q) . '».' : 'Todavía no hay variedades cargadas.' ?></td></tr><?php endif; ?>
    </tbody>
  </table>
  <p class="xs muted" style="padding:16px">Mostrando <?= min(100, count($vars)) ?> de <?= count($vars) ?> variedad<?= count($vars) === 1 ? '' : 'es' ?></p>
</div>

<?php include __DIR__ . '/../includes/footer.php'; ?>

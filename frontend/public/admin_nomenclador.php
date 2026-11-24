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
$f_tipo = in_array($_GET['tipo'] ?? '', ['CC', 'CP'], true) ? $_GET['tipo'] : '';
$f_sexo = in_array($_GET['sexo'] ?? '', ['M', 'H', 'sin'], true) ? $_GET['sexo'] : '';
$todas = api_lista('/api/v1/wiki/variedades');
$total = count($todas);
$solo_sexo = count(array_filter($todas, fn($v) => $v['sexo']));
$vars = $q !== '' ? api_lista('/api/v1/wiki/variedades?buscar=' . urlencode($q)) : $todas;
$vars = array_values(array_filter($vars, fn($v) => ($f_tipo === '' || $v['tipo'] === $f_tipo)
    && ($f_sexo === '' || ($f_sexo === 'sin' ? !$v['sexo'] : $v['sexo'] === $f_sexo))));

// Paginación: 50 por página; se conservan búsqueda y filtros
$por_pagina = 50;
$encontradas = count($vars);
$paginas = max(1, (int)ceil($encontradas / $por_pagina));
$pag = min(max(1, (int)($_GET['p'] ?? 1)), $paginas);
$vars_pag = array_slice($vars, ($pag - 1) * $por_pagina, $por_pagina);
$enlace = fn($cambios) => 'admin_nomenclador.php?' . http_build_query(array_filter(array_merge(['buscar' => $q, 'tipo' => $f_tipo, 'sexo' => $f_sexo, 'p' => $pag], $cambios), fn($x) => $x !== '' && $x !== 1));
// Números visibles: primera, última y dos a cada lado de la actual
$nums = array_values(array_unique(array_filter([1, $pag - 2, $pag - 1, $pag, $pag + 1, $pag + 2, $paginas], fn($n) => $n >= 1 && $n <= $paginas)));
sort($nums);

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
  <div class="stat"><span>Resultados de la búsqueda</span><strong><?= $encontradas ?></strong></div>
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
  <form method="GET" style="padding:16px;display:flex;flex-direction:column;gap:12px">
    <div class="campo">
      <label for="buscar">Buscar en el nomenclador</label>
      <div class="input-icono izq">
        <?= str_replace('class="ico"', 'class="ico" style="position:absolute;left:12px;top:12px"', icono('buscar')) ?>
        <input class="input" id="buscar" name="buscar" placeholder="Código o nombre" style="padding-left:36px" value="<?= e($q) ?>">
      </div>
    </div>
    <?php if ($f_tipo !== ''): ?><input type="hidden" name="tipo" value="<?= e($f_tipo) ?>"><?php endif; ?>
    <?php if ($f_sexo !== ''): ?><input type="hidden" name="sexo" value="<?= e($f_sexo) ?>"><?php endif; ?>
    <div style="display:flex;gap:24px;flex-wrap:wrap;align-items:center">
      <div class="chips"><span class="small muted" style="align-self:center">Tipo</span>
        <?php foreach (['' => 'Todos', 'CC' => 'CC · Color', 'CP' => 'CP · Forma y postura'] as $val => $txt): ?>
          <a href="<?= e($enlace(['tipo' => $val, 'p' => 1])) ?>" class="chip <?= $f_tipo === $val ? 'activo' : '' ?>"><?= e($txt) ?></a>
        <?php endforeach; ?>
      </div>
      <div class="chips"><span class="small muted" style="align-self:center">Sexo</span>
        <?php foreach (['' => 'Todas', 'M' => 'Indica macho', 'H' => 'Indica hembra', 'sin' => 'Sin sexo'] as $val => $txt): ?>
          <a href="<?= e($enlace(['sexo' => $val, 'p' => 1])) ?>" class="chip <?= $f_sexo === $val ? 'activo' : '' ?>"><?= e($txt) ?></a>
        <?php endforeach; ?>
      </div>
    </div>
  </form>
  <table class="tabla" style="max-width:none">
    <thead><tr><th style="padding-left:16px">Código</th><th>Nombre</th><th>Tipo</th><th>Serie</th><th>Sexo</th></tr></thead>
    <tbody>
    <?php foreach ($vars_pag as $v): ?>
      <tr>
        <td style="padding-left:16px"><strong><?= e($v['codigo']) ?></strong></td>
        <td><?= e($v['nombre']) ?></td>
        <td><span class="badge"><?= e($v['tipo']) ?></span></td>
        <td><?= e($v['serie'] ?? '—') ?></td>
        <td><?= $v['sexo'] ? '<span class="badge badge-borde">' . ($v['sexo'] === 'M' ? 'Macho' : 'Hembra') . '</span>' : '<span class="muted">—</span>' ?></td>
      </tr>
    <?php endforeach; ?>
    <?php if (!$vars): ?><tr><td colspan="5" class="muted" style="padding:24px 16px"><?= ($q !== '' || $f_tipo !== '' || $f_sexo !== '') ? 'Ninguna variedad coincide con la búsqueda y los filtros.' : 'Todavía no hay variedades cargadas.' ?></td></tr><?php endif; ?>
    </tbody>
  </table>
  <?php if ($vars): ?>
  <div class="paginacion" style="padding:16px">
    <span>Mostrando <?= ($pag - 1) * $por_pagina + 1 ?>–<?= ($pag - 1) * $por_pagina + count($vars_pag) ?> de <?= $encontradas ?> variedad<?= $encontradas === 1 ? '' : 'es' ?></span>
    <?php if ($paginas > 1): ?>
    <div class="paginas">
      <a href="<?= e($enlace(['p' => max(1, $pag - 1)])) ?>">Anterior</a>
      <?php foreach ($nums as $i => $n): ?>
        <?php if ($i > 0 && $n - $nums[$i - 1] > 1): ?><span class="muted">…</span><?php endif; ?>
        <a href="<?= e($enlace(['p' => $n])) ?>" class="<?= $n === $pag ? 'activo' : '' ?>"><?= $n ?></a>
      <?php endforeach; ?>
      <a href="<?= e($enlace(['p' => min($paginas, $pag + 1)])) ?>">Siguiente</a>
    </div>
    <?php endif; ?>
  </div>
  <?php endif; ?>
</div>

<?php include __DIR__ . '/../includes/footer.php'; ?>

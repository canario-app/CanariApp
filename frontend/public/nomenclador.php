<?php
// Consulta del nomenclador para el criador (solo lectura). La carga la hace el administrador
// en admin_nomenclador.php; aquí el criador busca el código de una variedad antes de registrar.
require_once __DIR__ . '/../includes/config.php';
requerir_login();

$q = trim($_GET['buscar'] ?? '');
$f_tipo = in_array($_GET['tipo'] ?? '', ['CC', 'CP'], true) ? $_GET['tipo'] : '';
$f_sexo = in_array($_GET['sexo'] ?? '', ['M', 'H', 'sin'], true) ? $_GET['sexo'] : '';
$vars = api_lista('/api/v1/wiki/variedades' . ($q !== '' ? '?buscar=' . urlencode($q) : ''));
$vars = array_values(array_filter($vars, fn($v) => ($f_tipo === '' || $v['tipo'] === $f_tipo)
    && ($f_sexo === '' || ($f_sexo === 'sin' ? !$v['sexo'] : $v['sexo'] === $f_sexo))));

// Paginación: 50 por página; se conservan búsqueda y filtros
$por_pagina = 50;
$encontradas = count($vars);
$paginas = max(1, (int)ceil($encontradas / $por_pagina));
$pag = min(max(1, (int)($_GET['p'] ?? 1)), $paginas);
$vars_pag = array_slice($vars, ($pag - 1) * $por_pagina, $por_pagina);
$enlace = fn($cambios) => 'nomenclador.php?' . http_build_query(array_filter(array_merge(['buscar' => $q, 'tipo' => $f_tipo, 'sexo' => $f_sexo, 'p' => $pag], $cambios), fn($x) => $x !== '' && $x !== 1));
$nums = array_values(array_unique(array_filter([1, $pag - 2, $pag - 1, $pag, $pag + 1, $pag + 2, $paginas], fn($n) => $n >= 1 && $n <= $paginas)));
sort($nums);

$pagina = 'canarios';
$titulo = 'Nomenclador de variedades';
include __DIR__ . '/../includes/header.php';
?>

<p class="migas"><a href="canarios.php">Canarios</a> / Nomenclador</p>
<div>
  <p class="eyebrow">Consulta</p>
  <h1 class="titulo-l">Nomenclador de variedades</h1>
  <p class="bajada">Busque por código o nombre la variedad que usará al registrar un ejemplar. La lista oficial la mantiene el administrador.</p>
</div>

<div class="panel" style="padding:0;gap:0">
  <form method="GET" style="padding:16px;display:flex;flex-direction:column;gap:12px">
    <div class="campo">
      <label for="buscar">Buscar en el nomenclador</label>
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <div class="input-icono izq" style="flex:1;min-width:220px">
          <?= str_replace('class="ico"', 'class="ico" style="position:absolute;left:12px;top:12px"', icono('buscar')) ?>
          <input class="input" id="buscar" name="buscar" placeholder="Código o nombre, ej.: D.033 o lutino" style="padding-left:36px" value="<?= e($q) ?>" autofocus>
        </div>
        <button class="btn btn-primario">Buscar</button>
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
    <thead><tr><th style="padding-left:16px">Código</th><th>Nombre</th><th>Tipo</th><th>Serie</th><th>Sexo</th><th></th></tr></thead>
    <tbody>
    <?php foreach ($vars_pag as $v): ?>
      <tr>
        <td style="padding-left:16px"><strong><?= e($v['codigo']) ?></strong></td>
        <td><?= e($v['nombre']) ?></td>
        <td><span class="badge"><?= e($v['tipo']) ?></span></td>
        <td><?= e($v['serie'] ?? '—') ?></td>
        <td><?= $v['sexo'] ? '<span class="badge badge-borde">' . ($v['sexo'] === 'M' ? 'Macho' : 'Hembra') . '</span>' : '<span class="muted">—</span>' ?></td>
        <td style="text-align:right;padding-right:16px"><a class="btn" style="white-space:nowrap" href="canario_registrar.php?variedad=<?= e(urlencode($v['codigo'] . ' · ' . $v['nombre'])) ?>">Usar al registrar</a></td>
      </tr>
    <?php endforeach; ?>
    <?php if (!$vars): ?><tr><td colspan="6" class="muted" style="padding:24px 16px"><?= ($q !== '' || $f_tipo !== '' || $f_sexo !== '') ? 'Ninguna variedad coincide con la búsqueda y los filtros.' : 'Todavía no hay variedades cargadas.' ?></td></tr><?php endif; ?>
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

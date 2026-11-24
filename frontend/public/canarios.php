<?php
$pagina = 'canarios';
$titulo = 'Canarios';
include __DIR__ . '/../includes/header.php';

$todos = canarios();
krsort($todos, SORT_NATURAL);

// Filtros (GET)
$f_anillo = trim($_GET['anillo'] ?? '');
$f_sexo   = $_GET['sexo'] ?? '';
$f_temp   = $_GET['temporada'] ?? '';
$f_marca  = $_GET['filtro'] ?? 'todos';

$lista = array_filter($todos, function ($c) use ($f_anillo, $f_sexo, $f_temp, $f_marca) {
    if ($f_anillo !== '' && strpos((string)$c['numero'], $f_anillo) !== 0) return false;
    if ($f_sexo !== '' && $c['sexo'] !== $f_sexo) return false;
    if ($f_temp !== '' && (string)$c['temp'] !== $f_temp) return false;
    return match ($f_marca) {
        'portadoras' => $c['portadora'] !== '',
        'reservadas' => $c['reservada'],
        'pendientes' => es_pendiente($c),
        'revision'   => $c['estado'] === 'revision',
        default      => true,
    };
});

// Paginación simple
$por_pagina = 8;
$total_filtrado = count($lista);
$paginas = max(1, (int)ceil($total_filtrado / $por_pagina));
$pag = min(max(1, (int)($_GET['p'] ?? 1)), $paginas);
$lista = array_slice($lista, ($pag - 1) * $por_pagina, $por_pagina, true);
$url = fn($cambios) => 'canarios.php?' . http_build_query(array_merge($_GET, $cambios));

$machos = count(por_sexo('Macho'));
$hembras = count(por_sexo('Hembra'));
$pendientes = count(array_filter($todos, 'es_pendiente'));
$en_revision = count(array_filter($todos, fn($c) => $c['estado'] === 'revision'));
$temporadas = array_unique(array_column($todos, 'temp'));
rsort($temporadas);

$chips = ['todos' => 'Todos', 'portadoras' => 'Portadoras', 'reservadas' => 'Reservadas', 'pendientes' => 'Pendientes', 'revision' => 'Requiere revisión'];
$estados = [
    'revision'   => '<span class="badge badge-oscuro">Requiere revisión</span>',
    'correccion' => '<span class="badge badge-borde">Corrección solicitada</span>',
];
?>

<?= flash() ?>

<?php if ($en_revision > 0): ?>
<div class="alerta">
  <img src="img/bandera.svg" width="16" height="16" alt="">
  <div>
    <strong><?= $en_revision ?> ejemplar<?= $en_revision > 1 ? 'es requieren' : ' requiere' ?> revisión</strong>
    <p>Cambió el nomenclador y su variedad ya no coincide con el sexo registrado. Resuélvalo desde la ficha con el Modo de Corrección.</p>
  </div>
</div>
<?php endif; ?>

<div class="page-head">
  <div>
    <p class="eyebrow">Registro del criadero</p>
    <h1 class="titulo-l">Canarios</h1>
    <p class="bajada">Todos los ejemplares de su criadero con su anillo, sexo, variedad y marcas.</p>
  </div>
  <a href="canario_registrar.php" class="btn btn-primario"><?= icono('mas') ?> Registrar ejemplar</a>
</div>

<div class="stats">
  <div class="stat"><span>Ejemplares</span><strong><?= count($todos) ?></strong></div>
  <div class="stat"><span>Machos</span><strong><?= $machos ?></strong></div>
  <div class="stat"><span>Hembras</span><strong><?= $hembras ?></strong></div>
  <div class="stat"><span>Pendientes de datos</span><strong><?= $pendientes ?></strong></div>
</div>

<div class="panel">
  <form class="filtros" method="GET" id="filtros">
    <input type="hidden" name="filtro" value="<?= e($f_marca) ?>">
    <div class="filtros-campos">
      <div class="campo">
        <label for="anillo">Buscar por anillo</label>
        <div class="input-icono izq">
          <?= str_replace('class="ico"', 'class="ico" style="position:absolute;left:12px;top:12px"', icono('buscar')) ?>
          <input class="input" id="anillo" name="anillo" inputmode="numeric" placeholder="N.° de anillo, ej.: 2901" style="width:240px;padding-left:36px" value="<?= e($f_anillo) ?>">
        </div>
      </div>
      <div class="campo">
        <label for="sexo">Sexo</label>
        <select class="input" id="sexo" name="sexo" style="width:150px" onchange="this.form.submit()">
          <?= select_opciones(['Macho', 'Hembra'], $f_sexo, 'Todos') ?>
        </select>
      </div>
      <div class="campo">
        <label for="temporada">Temporada</label>
        <select class="input" id="temporada" name="temporada" style="width:150px" onchange="this.form.submit()">
          <?= select_opciones(array_map('strval', $temporadas), $f_temp, 'Todas') ?>
        </select>
      </div>
    </div>
    <div class="chips">
      <?php foreach ($chips as $k => $txt): ?>
        <a href="<?= e($url(['filtro' => $k, 'p' => 1])) ?>" class="chip <?= $f_marca === $k ? 'activo' : '' ?>"><?= e($txt) ?></a>
      <?php endforeach; ?>
    </div>
  </form>

  <?php if (!$lista): ?>
    <div class="vacio" style="min-height:360px">
      <div class="circulo"><?= icono('buscar', 24) ?></div>
      <?php if ($f_anillo !== ''): ?>
        <h3>No encontramos ese anillo en su criadero</h3>
        <p>El anillo <?= e($f_anillo) ?> no está registrado en su criadero. Revise el número o registre el ejemplar.</p>
      <?php else: ?>
        <h3>No hay ejemplares con estos filtros</h3>
        <p>Pruebe con otros filtros o registre un ejemplar nuevo.</p>
      <?php endif; ?>
      <div class="acciones">
        <a href="canarios.php" class="btn">Limpiar búsqueda</a>
        <a href="canario_registrar.php?numero=<?= e($f_anillo) ?>" class="btn btn-primario"><?= icono('mas') ?> Registrar ejemplar</a>
      </div>
    </div>
  <?php else: ?>
  <table class="tabla">
    <thead>
      <tr><th>Anillo</th><th>Sexo</th><th>Variedad</th><th>Portador/a</th><th>Reservada</th><th>Estado</th><th></th></tr>
    </thead>
    <tbody>
      <?php foreach ($lista as $k => $c): ?>
      <tr>
        <td><?= anillo_html($c) ?></td>
        <td><?= $c['sexo'] ? e($c['sexo']) : '<span class="badge badge-tenue">Pendiente</span>' ?></td>
        <td style="max-width:170px"><?= $c['variedad'] ? e(variedad_txt($c['variedad'])) : '<span class="badge badge-tenue">Pendiente</span>' ?></td>
        <td><?= $c['portadora'] ? '<span class="badge badge-borde">' . portador_txt($c) . ' · ' . e($c['portadora']) . '</span>' : '<span class="muted">—</span>' ?></td>
        <td><?= $c['reservada'] ? '<span class="badge">Reservada</span>' : '<span class="muted">—</span>' ?></td>
        <td><?= $estados[$c['estado']] ?? '' ?></td>
        <td class="acciones">
          <?php if (es_pendiente($c) && $c['nidada']): ?>
            <a href="crias.php?completar=<?= e($k) ?>" class="link">Completar datos <?= icono('chevron', 12) ?></a>
          <?php else: ?>
            <a href="canario_ficha.php?id=<?= e($k) ?>" class="link">Ver ficha <?= icono('chevron', 12) ?></a>
          <?php endif; ?>
        </td>
      </tr>
      <?php endforeach; ?>
    </tbody>
  </table>

  <div class="paginacion">
    <span>Mostrando <?= ($pag - 1) * $por_pagina + 1 ?>–<?= ($pag - 1) * $por_pagina + count($lista) ?> de <?= $total_filtrado ?> ejemplares</span>
    <div class="paginas">
      <a href="<?= e($url(['p' => max(1, $pag - 1)])) ?>">Anterior</a>
      <?php for ($i = 1; $i <= $paginas; $i++): ?>
        <a href="<?= e($url(['p' => $i])) ?>" class="<?= $i === $pag ? 'activo' : '' ?>"><?= $i ?></a>
      <?php endfor; ?>
      <a href="<?= e($url(['p' => min($paginas, $pag + 1)])) ?>">Siguiente</a>
    </div>
  </div>
  <?php endif; ?>
</div>

<?php include __DIR__ . '/../includes/footer.php'; ?>

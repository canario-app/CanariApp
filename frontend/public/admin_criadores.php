<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

$q = trim($_GET['buscar'] ?? '');
$todos = api_lista('/api/v1/admin/criadores');
$lista = $q === '' ? $todos : api_lista('/api/v1/admin/criadores?buscar=' . urlencode($q));
$este_anio = count(array_filter($todos, fn($c) => substr($c['fecha_creacion'], 0, 4) === date('Y')));

$pagina = 'admin';
$titulo = 'Criadores';
include __DIR__ . '/../includes/header.php';
?>

<?= flash() ?>

<div class="page-head" style="align-items:center">
  <div>
    <p class="eyebrow">Administración</p>
    <h1 class="titulo-l">Criadores</h1>
    <p class="bajada">Cree las cuentas de los criadores, consulte sus datos y edítelos. Cada criador entra con su correo y solo ve su propio criadero.</p>
  </div>
  <a href="admin_criador.php" class="btn btn-primario btn-lg"><?= icono('mas') ?> Registrar criador</a>
</div>

<?php if (!$todos): ?>
<div class="vacio">
  <div class="circulo"><?= icono('corazon', 24) ?></div>
  <h3>Aún no hay criadores registrados</h3>
  <p>Registre al primer criador para que pueda iniciar sesión y empezar a cargar sus ejemplares.</p>
  <div class="acciones">
    <a href="admin_criador.php" class="btn btn-primario" style="width:200px"><?= icono('mas') ?> Registrar criador</a>
  </div>
</div>
<?php else: ?>

<div class="stats" style="grid-template-columns:repeat(3,1fr)">
  <div class="stat"><span>Criadores registrados</span><strong><?= count($todos) ?></strong></div>
  <div class="stat"><span>Altas en <?= date('Y') ?></span><strong><?= $este_anio ?></strong></div>
  <div class="stat"><span>Resultados de la búsqueda</span><strong><?= count($lista) ?></strong></div>
</div>

<div class="panel" style="padding:0;gap:0;flex:1">
  <form method="GET" style="padding:16px">
    <div class="campo">
      <label for="buscar">Buscar criador</label>
      <div class="input-icono izq">
        <?= str_replace('class="ico"', 'class="ico" style="position:absolute;left:12px;top:12px"', icono('buscar')) ?>
        <input class="input" id="buscar" name="buscar" placeholder="Nombre, correo o número de socio" style="padding-left:36px" value="<?= e($q) ?>">
      </div>
    </div>
  </form>
  <table class="tabla" style="max-width:none">
    <thead><tr><th style="padding-left:16px">Nombre</th><th>Correo</th><th>N.° de socio</th><th>Alta</th><th></th></tr></thead>
    <tbody>
    <?php foreach ($lista as $c): ?>
      <tr>
        <td style="padding-left:16px"><strong><?= e($c['nombre']) ?></strong></td>
        <td><?= e($c['correo']) ?></td>
        <td><span class="badge"><?= e($c['numero_socio']) ?></span></td>
        <td><?= e(fecha(substr($c['fecha_creacion'], 0, 10))) ?></td>
        <td class="acciones" style="padding-right:16px">
          <a class="link" href="admin_criador.php?id=<?= (int)$c['id_criador'] ?>">Ver y editar <?= icono('chevron', 12) ?></a>
        </td>
      </tr>
    <?php endforeach; ?>
    <?php if (!$lista): ?><tr><td colspan="5" class="muted" style="padding:24px 16px">Ningún criador coincide con «<?= e($q) ?>».</td></tr><?php endif; ?>
    </tbody>
  </table>
  <p class="xs muted" style="padding:16px;margin-top:auto">Mostrando <?= count($lista) ?> criador<?= count($lista) === 1 ? '' : 'es' ?> de <?= count($todos) ?></p>
</div>
<?php endif; ?>

<?php include __DIR__ . '/../includes/footer.php'; ?>

<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

// Las crías de un ganador se ven en su ficha (subtítulo «Ejemplar ganador» y una pestaña por pareja).
// Esta pantalla solo busca el anillo completo y lleva a la ficha.
$k = $_GET['id'] ?? '';
if (canario($k)) redirigir('canario_ficha.php?id=' . urlencode($k) . '#crias');

$opciones = [];
foreach (canarios() as $ck => $c) $opciones[anillo_txt($c)] = $ck;

$buscado = trim($_GET['anillo'] ?? '');
$error = '';
if ($buscado !== '') {
    if (isset($opciones[$buscado])) redirigir('canario_ficha.php?id=' . urlencode($opciones[$buscado]) . '#crias');
    $error = 'Ese anillo no está registrado en su criadero. Elija el anillo completo (número · club · socio · temporada) de la lista.';
}

$ganadores = array_filter(canarios(), fn($c) => titulos_de(clave($c)));

$pagina = 'titulos';
$titulo = 'Crías de un ganador';
include __DIR__ . '/../includes/header.php';
?>

<p class="migas"><a href="titulos.php">Títulos</a> / Crías de un ganador</p>
<div>
  <p class="eyebrow">Títulos de competencia</p>
  <h1 class="titulo-l">Crías de un ganador</h1>
  <p class="bajada">Busque el ejemplar por su anillo completo. Sus crías se muestran en la ficha, separadas por pareja.</p>
</div>

<?php if ($error): ?>
  <div class="aviso aviso-error"><?= icono('alerta') ?><div><strong>Ejemplar no encontrado</strong><p><?= e($error) ?></p></div></div>
<?php endif; ?>

<form method="GET" class="input-icono izq" style="max-width:420px">
  <?= str_replace('class="ico"', 'class="ico" style="position:absolute;left:12px;top:12px"', icono('buscar')) ?>
  <input class="input" name="anillo" list="lista-anillos" autocomplete="off" placeholder="Ej.: 2901 · SOCH · 123 · 2026" style="padding-left:36px" value="<?= e($buscado) ?>" aria-label="Anillo completo">
  <datalist id="lista-anillos"><?php foreach ($opciones as $txt => $_): ?><option value="<?= e($txt) ?>"><?php endforeach; ?></datalist>
</form>

<section class="card">
  <h2 style="font-size:18px;font-weight:600;margin-bottom:12px">Ejemplares con títulos</h2>
  <?php foreach ($ganadores as $gk => $g): ?>
    <div class="fila-lista">
      <span><?= anillo_html($g, true) ?></span>
      <a class="link" href="canario_ficha.php?id=<?= e(urlencode($gk)) ?>#crias">Ver crías <?= icono('chevron', 12) ?></a>
    </div>
  <?php endforeach; ?>
  <?php if (!$ganadores): ?><p class="small muted">Aún no hay ejemplares con títulos registrados.</p><?php endif; ?>
</section>

<?php include __DIR__ . '/../includes/footer.php'; ?>

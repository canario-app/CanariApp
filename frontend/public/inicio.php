<?php
$pagina = 'inicio';
$titulo = 'Inicio';
include __DIR__ . '/../includes/header.php';

$n_canarios = count(canarios());
$n_parejas  = count(array_filter(parejas(), fn($p) => $p['estado'] === 'Activa'));
$n_jaulas   = count(jaulas_ocupadas());
$n_crias    = count(array_filter(canarios(), fn($c) => $c['nidada']));
$n_titulos  = count(array_unique(array_column(titulos(), 'canario')));
$n_revision = count(array_filter(canarios(), fn($c) => $c['estado'] === 'revision'));
$pl = fn($n, $uno, $varios) => $n . ' ' . ($n === 1 ? $uno : $varios);

$tarjetas = [
    ['ic-canarios.svg',   'Tiene ' . $pl($n_canarios, 'canario registrado', 'canarios registrados'), 'Registre cada ave con su número de anillo, club, socio y temporada.', 'canarios.php'],
    ['ic-parejas.svg',    ($n_parejas === 1 ? 'Existe ' : 'Existen ') . $pl($n_parejas, 'pareja', 'parejas') . ' en ' . $pl($n_jaulas, 'jaula', 'jaulas'), 'Forme parejas en su propia jaula, hasta 6 hembras por macho.', 'parejas.php'],
    ['ic-crias.svg',      'Registró ' . $pl($n_crias, 'cría', 'crías'), 'Anote cada nidada y el sexo de las crías cuando nacen.', 'crias.php'],
    ['ic-genealogia.svg', 'Genealogía', 'Se consulta desde la ficha de cada canario: abra un ejemplar para ver sus padres y abuelos.', 'canarios.php'],
    ['ic-titulos.svg',    $pl($n_titulos, 'canario tiene', 'canarios tienen') . ' Títulos de competencia', '', 'titulos.php'],
    ['ic-simulador.svg',  'Simulador genético', 'Calcule la proporción esperada de crías según la Ley de Mendel.', 'simulador.php'],
];
?>

<?= flash() ?>

<?php if ($n_revision): ?>
  <div class="aviso aviso-warn"><?= icono('alerta') ?><div><strong><?= $n_revision === 1 ? '1 ejemplar requiere revisión' : "$n_revision ejemplares requieren revisión" ?></strong><p>Cambió el nomenclador y su variedad ya no coincide con el sexo registrado. <a href="canarios.php?filtro=revision" style="text-decoration:underline">Ver <?= $n_revision === 1 ? 'el ejemplar' : 'los ejemplares' ?></a></p></div></div>
<?php endif; ?>

<section style="margin-bottom:32px">
  <p class="eyebrow">Crianza de canarios de competencia</p>
  <h1 class="titulo-xl" style="margin:16px 0 24px; max-width:620px">Bienvenido, <?= e($criador) ?></h1>
  <a href="canarios.php" class="btn btn-primario">Ir a mis canarios <img src="img/flecha.svg" width="16" height="16" alt=""></a>
</section>

<section style="display:flex; flex-direction:column; gap:24px">
  <div>
    <p class="eyebrow">Qué puede hacer</p>
    <h2 class="titulo-m" style="margin-top:8px">Todo el registro de su crianza</h2>
  </div>
  <div class="grid-3">
    <?php foreach ($tarjetas as [$icono, $titulo_t, $texto, $url]): ?>
      <a href="<?= $url ?>" class="card feature">
        <div class="icono-caja"><img src="img/<?= $icono ?>" width="20" height="20" alt=""></div>
        <h3><?= e($titulo_t) ?></h3>
        <?php if ($texto): ?><p><?= e($texto) ?></p><?php endif; ?>
      </a>
    <?php endforeach; ?>
  </div>
</section>

<section class="ayuda" style="margin-top:32px">
  <div>
    <h3>¿Necesita ayuda?</h3>
    <p>Haga click aquí si tiene dudas sobre el funcionamiento de la página o si quiere contactar al administrador.</p>
  </div>
  <div class="acciones">
    <a href="contacto.php" class="btn">Contactar al administrador</a>
    <a href="#" class="btn btn-primario" data-modal="como-funciona">¿Cómo funciona?</a>
  </div>
</section>

<footer class="pie">
  <span>CanariApp · Registro de crianza de canarios de competencia</span>
  
  <a href="contacto.php">Contactar al administrador</a>
</footer>

<div class="modal" id="como-funciona">
  <div class="modal-caja" style="width:1053px">
    <button type="button" class="modal-x" data-cerrar aria-label="Cerrar"><?= icono('cerrar', 18) ?></button>
    <div>
      <p class="eyebrow">Cómo funciona</p>
      <h2 style="font-size:28px">De la pareja al campeón, paso a paso</h2>
    </div>
    <div class="pasos">
      <div class="paso"><span class="num">1</span><h4>Registre sus ejemplares</h4><p>Anillo, sexo y variedad del nomenclador oficial.</p></div>
      <div class="paso"><span class="num">2</span><h4>Forme parejas</h4><p>Asigne cada pareja a su jaula y registre la fecha de cruce.</p></div>
      <div class="paso"><span class="num">3</span><h4>Anote nidadas y crías</h4><p>Cada cría con su anillo; el sexo, cuando se sepa.</p></div>
      <div class="paso"><span class="num">4</span><h4>Registre títulos</h4><p>Y consulte las crías de sus ganadores por pareja.</p></div>
    </div>
  </div>
</div>

<?php include __DIR__ . '/../includes/footer.php'; ?>

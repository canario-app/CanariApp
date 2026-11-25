<?php
$esAdmin = ($_SESSION['usuario']['rol'] ?? '') === 'administrador';
$secciones = $esAdmin ? [
    'admin'        => ['Criadores', 'admin_criadores.php'],
    'nomenclador'  => ['Nomenclador', 'admin_nomenclador.php'],
    'clubes'       => ['Clubes', 'admin_clubes.php'],
    'mutaciones'   => ['Mutaciones', 'admin_mutaciones.php'],
    'correcciones' => ['Correcciones', 'admin_correcciones.php'],
    'respaldos'    => ['Respaldos', 'admin_respaldos.php'],
    'modo'         => ['Modo de operación', 'admin_modo.php'],
] : [
    'inicio'    => ['Inicio', 'inicio.php'],
    'canarios'  => ['Canarios', 'canarios.php'],
    'parejas'   => ['Libro de cría', 'parejas.php'],
    'crias'     => ['Crías', 'crias.php'],
    'titulos'   => ['Títulos', 'titulos.php'],
    'simulador' => ['Simulador', 'simulador.php'],
];
?>
<aside class="sidebar">
  <nav class="nav">
    <?php foreach ($secciones as $clave => [$texto, $url]): ?>
      <a href="<?= $url ?>" class="<?= ($pagina ?? '') === $clave ? 'activo' : '' ?>"><?= e($texto) ?></a>
    <?php endforeach; ?>
  </nav>
</aside>

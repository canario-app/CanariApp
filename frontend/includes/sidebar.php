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
    // Grupo desplegable: al hacer clic muestra/oculta sus subopciones; abierto si se está en una de ellas
    'libro'     => ['Libro de cría', null, [
        'parejas' => ['Parejas y cruces', 'parejas.php'],
        'crias'   => ['Registro de crías', 'crias.php'],
    ]],
    'titulos'   => ['Títulos', 'titulos.php'],
    'simulador' => ['Simulador', 'simulador.php'],
];
?>
<aside class="sidebar">
  <nav class="nav">
    <?php foreach ($secciones as $clave => $s): [$texto, $url] = $s; ?>
      <?php if (!empty($s[2])): $abierto = isset($s[2][$pagina ?? '']); ?>
        <details class="nav-grupo<?= $abierto ? ' abierto' : '' ?>"<?= $abierto ? ' open' : '' ?>>
          <summary class="nav-titulo"><?= e($texto) ?> <svg class="nav-flecha" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg></summary>
          <div class="nav-subs">
          <?php foreach ($s[2] as $sub => [$t2, $u2]): ?>
            <a href="<?= $u2 ?>" class="nav-sub <?= ($pagina ?? '') === $sub ? 'activo' : '' ?>"><?= e($t2) ?></a>
          <?php endforeach; ?>
          </div>
        </details>
      <?php else: ?>
        <a href="<?= $url ?>" class="<?= ($pagina ?? '') === $clave ? 'activo' : '' ?>"><?= e($texto) ?></a>
      <?php endif; ?>
    <?php endforeach; ?>
  </nav>
</aside>

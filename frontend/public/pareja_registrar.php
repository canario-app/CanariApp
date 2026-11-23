<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

$v = ['macho' => $_GET['macho'] ?? '', 'hembra' => '', 'jaula' => ''];
$err = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    foreach ($v as $k => $_) $v[$k] = trim($_POST[$k] ?? '');
    $m = canario($v['macho']);
    $h = canario($v['hembra']);

    if (!$m || $m['sexo'] !== 'Macho') $err['macho'] = 'Elija un macho de su criadero.';
    elseif (count(parejas_activas_de($v['macho'])) >= MAX_PAREJAS_MACHO) $err['macho'] = 'Este macho ya tiene ' . MAX_PAREJAS_MACHO . ' parejas activas. El máximo es ' . MAX_PAREJAS_MACHO . '.';

    if (!$h || $h['sexo'] !== 'Hembra') $err['hembra'] = 'Elija una hembra de su criadero.';
    elseif ($act = parejas_activas_de($v['hembra'])) $err['hembra'] = 'Esta hembra ya tiene una pareja activa (jaula ' . current($act)['jaula'] . ').';

    if (!preg_match('/^\d{1,3}$/', $v['jaula']) || (int)$v['jaula'] < 1) $err['jaula'] = 'Ingrese un número de jaula válido.';
    elseif (in_array((int)$v['jaula'], jaulas_ocupadas(), true)) $err['jaula'] = "La jaula {$v['jaula']} ya tiene una pareja activa.";

    if (!$err) {
        $id = guardar_pareja(null, ['jaula' => (int)$v['jaula'], 'macho' => $v['macho'], 'hembra' => $v['hembra'], 'estado' => 'Activa', 'desde' => hoy(), 'cruces' => []]);
        redirigir("jaula.php?id=$id", 'Pareja registrada', "Se formó la pareja {$m['numero']} ♂ × {$h['numero']} ♀ en la jaula {$v['jaula']}. Registre la fecha de cruce cuando ocurra.");
    }
}

$opMachos = $opHembras = [];
foreach (por_sexo('Macho') as $k => $c) $opMachos[$k] = anillo_txt($c);
foreach (por_sexo('Hembra') as $k => $c) {
    $act = parejas_activas_de($k);
    $opHembras[$k] = anillo_txt($c) . ($act ? ' (en jaula ' . current($act)['jaula'] . ')' : '');
}
// cuántas parejas activas tiene cada macho (para el texto de ayuda en vivo)
$activasMacho = array_map(fn($k) => count(parejas_activas_de($k)), array_combine(array_keys($opMachos), array_keys($opMachos)));

$pagina = 'parejas';
$titulo = 'Registrar pareja';
include __DIR__ . '/../includes/header.php';
$msg = fn($campo) => isset($err[$campo]) ? '<span class="msg-error">' . e($err[$campo]) . '</span>' : '';
?>

<p class="migas"><a href="parejas.php">Parejas y cruces</a> / Registrar pareja</p>
<div>
  <p class="eyebrow">Parejas y cruces</p>
  <h1 class="titulo-l">Registrar pareja</h1>
  <p class="bajada">Elija un macho y una hembra de su criadero y asígneles una jaula libre.</p>
</div>

<?php if ($err): ?>
  <div class="aviso aviso-error"><?= icono('alerta') ?><div><strong>No se pudo registrar la pareja</strong><p>Revise los campos marcados.</p></div></div>
<?php endif; ?>

<form method="POST" novalidate>
  <div class="dos-col" style="grid-template-columns:1fr 360px">
    <section class="seccion" style="min-height:400px">
      <h2 style="font-size:16px">Datos de la pareja</h2>
      <div class="dos-col-igual" style="gap:16px">
        <div class="campo<?= isset($err['macho']) ? ' error' : '' ?>">
          <label for="macho">Macho</label>
          <select class="input" id="macho" name="macho"><?= select_opciones($opMachos, $v['macho'], 'Elija un macho') ?></select>
          <?= $msg('macho') ?: '<span class="ayuda-campo" id="ayudaMacho"></span>' ?>
        </div>
        <div class="campo<?= isset($err['hembra']) ? ' error' : '' ?>">
          <label for="hembra">Hembra</label>
          <select class="input" id="hembra" name="hembra"><?= select_opciones($opHembras, $v['hembra'], 'Elija una hembra') ?></select>
          <?= $msg('hembra') ?>
        </div>
        <div class="campo<?= isset($err['jaula']) ? ' error' : '' ?>">
          <label for="jaula">Número de jaula</label>
          <input class="input" id="jaula" name="jaula" inputmode="numeric" placeholder="Ej.: 5" value="<?= e($v['jaula']) ?>">
          <?= $msg('jaula') ?>
        </div>
      </div>
      <p class="small muted" style="margin-top:auto;display:flex;gap:8px"><?= icono('info') ?> La fecha de cruce se registra después, desde la pareja.</p>
    </section>

    <aside class="panel-gris" style="min-height:400px">
      <h3>Reglas para formar una pareja</h3>
      <ul class="reglas">
        <li><?= icono('check') ?> Un macho y una hembra, ambos con sexo registrado.</li>
        <li><?= icono('check') ?> Un macho puede tener hasta <?= MAX_PAREJAS_MACHO ?> parejas activas.</li>
        <li><?= icono('check') ?> Una hembra solo puede tener una pareja activa.</li>
        <li><?= icono('check') ?> Cada jaula admite una sola pareja activa.</li>
      </ul>
      <p class="muted" style="margin-top:auto;border-top:1px solid var(--gris-borde);padding-top:12px">Jaulas ocupadas ahora: <strong style="color:var(--negro)"><?= e(implode(', ', jaulas_ocupadas()) ?: 'ninguna') ?></strong></p>
    </aside>
  </div>
  <div class="acciones-form" style="margin-top:20px">
    <a href="parejas.php" class="btn">Cancelar</a>
    <button class="btn btn-primario">Registrar pareja</button>
  </div>
</form>

<script>
  // Muestra cuántas parejas activas tiene el macho elegido
  const activas = <?= json_encode($activasMacho) ?>, max = <?= MAX_PAREJAS_MACHO ?>;
  const sel = document.getElementById('macho'), ayuda = document.getElementById('ayudaMacho');
  const upd = () => { if (!ayuda) return; const n = activas[sel.value]; ayuda.textContent = sel.value ? `${n} de ${max} parejas activas · puede formar ${max - n} más` : ''; };
  sel.addEventListener('change', upd); upd();
</script>

<?php include __DIR__ . '/../includes/footer.php'; ?>

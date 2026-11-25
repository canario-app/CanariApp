<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

$v = ['macho' => $_GET['macho'] ?? '', 'hembra' => '', 'jaula' => '', 'desde' => hoy()];
$v = array_merge($v, array_intersect_key(post_previo(), $v));
$err = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    foreach ($v as $k => $_) $v[$k] = trim($_POST[$k] ?? '');
    $m = canario($v['macho']);
    $h = canario($v['hembra']);

    if (!$m || $m['sexo'] !== 'Macho') $err['macho'] = 'Elija un macho de su criadero.';

    if (!$h || $h['sexo'] !== 'Hembra') $err['hembra'] = 'Elija una hembra de su criadero.';
    elseif ($act = parejas_activas_de($v['hembra'])) $err['hembra'] = 'Esta hembra ya tiene una pareja activa (jaula ' . current($act)['jaula'] . ').';

    // SRS-RF012: cualquier entero de 1 a 2.147.483.647
    if (!preg_match('/^\d{1,10}$/', $v['jaula']) || (int)$v['jaula'] < 1 || (int)$v['jaula'] > 2147483647) $err['jaula'] = 'Ingrese un número de jaula entre 1 y 2.147.483.647.';
    elseif (in_array((int)$v['jaula'], jaulas_ocupadas(), true)) $err['jaula'] = "La jaula {$v['jaula']} ya tiene una pareja activa.";

    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $v['desde'])) $err['desde'] = 'Ingrese la fecha de formación.';
    elseif ($v['desde'] > hoy()) $err['desde'] = 'La fecha no puede ser posterior a hoy.';

    if (!$err) {
        $id = guardar_pareja(null, ['jaula' => (int)$v['jaula'], 'macho' => $v['macho'], 'hembra' => $v['hembra'], 'estado' => 'Activa', 'desde' => $v['desde'], 'cruces' => []]);
        redirigir("jaula.php?id=$id", 'Pareja registrada', "Se formó la pareja {$m['numero']} ♂ × {$h['numero']} ♀ en la jaula {$v['jaula']}. Registre la fecha de cruce cuando ocurra.");
    }
}

// Cada canario se muestra con su nomenclatura (variedad), para poder elegir por tipo
$conVariedad = fn($c) => anillo_txt($c) . ' — ' . ($c['variedad'] ? variedad_txt($c['variedad']) : 'variedad pendiente');
$opMachos = $opHembras = [];
foreach (por_sexo('Macho') as $k => $c) $opMachos[$k] = $conVariedad($c);
foreach (por_sexo('Hembra') as $k => $c) {
    $act = parejas_activas_de($k);
    $opHembras[$k] = $conVariedad($c) . ($act ? ' (en jaula ' . current($act)['jaula'] . ')' : '');
}
// cuántas parejas activas tiene cada macho (para el texto de ayuda en vivo)
$activasMacho = array_map(fn($k) => count(parejas_activas_de($k)), array_combine(array_keys($opMachos), array_keys($opMachos)));

$pagina = 'parejas';
$titulo = 'Registrar pareja';
include __DIR__ . '/../includes/header.php';
$msg = fn($campo) => isset($err[$campo]) ? '<span class="msg-error">' . e($err[$campo]) . '</span>' : '';
?>

<p class="migas"><a href="parejas.php">Libro de cría</a> / Registrar pareja</p>
<div>
  <p class="eyebrow">Libro de cría</p>
  <h1 class="titulo-l">Registrar pareja</h1>
  <p class="bajada">Elija un macho y una hembra de su criadero y asígneles una jaula libre.</p>
</div>

<?= flash() ?>
<?php if ($err): ?>
  <div class="aviso aviso-error"><?= icono('alerta') ?><div><strong>No se pudo registrar la pareja</strong><p>Revise los campos marcados.</p></div></div>
<?php endif; ?>

<form method="POST" novalidate>
  <div class="dos-col" style="grid-template-columns:1fr 360px">
    <section class="seccion" style="min-height:400px">
      <h2 style="font-size:16px">Datos de la pareja</h2>
      <div class="dos-col-igual" style="gap:16px">
        <div class="campo">
          <label for="nom-macho">Nomenclatura del macho</label>
          <input class="input filtro-nom" id="nom-macho" data-variedades data-para="macho" autocomplete="off" placeholder="Código o nombre, ej.: D.017 o lutino">
          <span class="ayuda-campo" id="cuenta-macho">Opcional: filtra sus machos por variedad.</span>
        </div>
        <div class="campo">
          <label for="nom-hembra">Nomenclatura de la hembra</label>
          <input class="input filtro-nom" id="nom-hembra" data-variedades data-para="hembra" autocomplete="off" placeholder="Código o nombre, ej.: D.003 o amarillo">
          <span class="ayuda-campo" id="cuenta-hembra">Opcional: filtra sus hembras por variedad.</span>
        </div>
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
        <?= datalist_variedades() ?>
        <div class="campo<?= isset($err['jaula']) ? ' error' : '' ?>">
          <label for="jaula">Número de jaula</label>
          <input class="input" id="jaula" name="jaula" inputmode="numeric" placeholder="Ej.: 5" value="<?= e($v['jaula']) ?>">
          <?= $msg('jaula') ?>
        </div>
        <div class="campo<?= isset($err['desde']) ? ' error' : '' ?>">
          <label for="desde">Fecha de formación</label>
          <input class="input" type="date" id="desde" name="desde" max="<?= hoy() ?>" value="<?= e($v['desde']) ?>">
          <?= $msg('desde') ?: '<span class="ayuda-campo">Por defecto, hoy. Puede indicar una fecha anterior de la temporada.</span>' ?>
        </div>
      </div>
      <p class="small muted" style="margin-top:auto;display:flex;gap:8px"><?= icono('info') ?> La fecha de cruce se registra después, desde la pareja.</p>
    </section>

    <aside class="panel-gris" style="min-height:400px">
      <h3>Reglas para formar una pareja</h3>
      <ul class="reglas">
        <li><?= icono('check') ?> Un macho y una hembra, ambos con sexo registrado.</li>
        <li><?= icono('check') ?> Puede elegir la nomenclatura para ver solo sus canarios registrados de esa variedad.</li>
        <li><?= icono('check') ?> Un macho puede tener varias parejas activas, sin límite.</li>
        <li><?= icono('check') ?> Una hembra solo puede tener una pareja activa a la vez. Para juntarla con otro macho, primero finalice la pareja anterior.</li>
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
  const activas = <?= json_encode($activasMacho) ?>;
  const sel = document.getElementById('macho'), ayuda = document.getElementById('ayudaMacho');
  const upd = () => { if (!ayuda) return; const n = activas[sel.value]; ayuda.textContent = sel.value ? `${n} pareja${n === 1 ? '' : 's'} activa${n === 1 ? '' : 's'}` : ''; };
  sel.addEventListener('change', upd); upd();

  // Filtro por nomenclatura: reduce la lista de machos/hembras a los de esa variedad.
  // Se reconstruyen las <option> (ocultarlas con CSS no funciona en Safari/iPhone).
  const norm = s => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  document.querySelectorAll('.filtro-nom').forEach(inp => {
    const s = document.getElementById(inp.dataset.para);
    const cuenta = document.getElementById('cuenta-' + inp.dataset.para);
    const textoInicial = cuenta.textContent;
    const todas = [...s.options].map(o => ({ v: o.value, t: o.textContent }));
    const [vacia, ...aves] = todas;
    const nombre = inp.dataset.para === 'macho' ? ['macho', 'machos'] : ['hembra', 'hembras'];
    const filtrar = () => {
      const q = norm(inp.value.trim());
      // si eligió una variedad de la lista («D.017 · LUTINO…»), se filtra por el código exacto
      const cod = /^[a-z]\.\d+ · /.test(q) ? q.split(' · ')[0] + ' · ' : null;
      const palabras = q.split(/\s+/).filter(Boolean);
      const sirve = a => !q || (cod ? norm(a.t).includes('— ' + cod) : palabras.every(p => norm(a.t.split(' — ')[1] || '').includes(p)));
      const elegido = s.value;
      const quedan = aves.filter(sirve);
      s.replaceChildren(...[vacia, ...quedan].map(a => new Option(a.t, a.v)));
      s.value = quedan.some(a => a.v === elegido) ? elegido : (quedan.length === 1 ? quedan[0].v : '');
      s.dispatchEvent(new Event('change'));
      cuenta.textContent = !q ? textoInicial
        : quedan.length ? `${quedan.length} ${nombre[quedan.length === 1 ? 0 : 1]} de esa variedad.`
        : `No tiene ${nombre[1]} de esa variedad. Solo se pueden usar canarios registrados.`;
      cuenta.classList.toggle('msg-error', !!q && !quedan.length);
    };
    inp.addEventListener('input', filtrar);
    inp.addEventListener('change', filtrar);
  });
</script>

<?php include __DIR__ . '/../includes/footer.php'; ?>

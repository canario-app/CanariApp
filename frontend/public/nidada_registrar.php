<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

$anio = (int)date('Y');

// Nidada ya creada cuyas crías no se guardaron todas (la API rechazó algún anillo): al reintentar se usa la misma
$enCurso = $_SESSION['nidada_en_curso'] ?? [];

// Cruces disponibles: cruces registrados de sus parejas que todavía no tienen nidada
$cruces = [];
foreach (parejas() as $pid => $p) {
    $usados = array_column(nidadas_de_pareja($pid), 'cruce');
    foreach ($p['cruces'] as $cf) {
        if (in_array($cf, $usados, true) && !isset($enCurso["{$pid}_{$cf}"])) continue;
        $m = canario($p['macho']); $h = canario($p['hembra']);
        $cruces["{$pid}_{$cf}"] = [
            'pid' => $pid, 'fecha' => $cf, 'p' => $p, 'm' => $m, 'h' => $h,
            'txt' => "{$m['numero']} ♂ × {$h['numero']} ♀ · Jaula {$p['jaula']} · Cruce " . fecha($cf),
        ];
    }
}
uasort($cruces, fn($a, $b) => strcmp($b['fecha'], $a['fecha']));

$v = ['cruce' => $_GET['cruce'] ?? array_key_first($cruces) ?? '', 'nacimiento' => ''];
$filas = [['numero' => '', 'club' => 'SOCH', 'socio' => mi_socio(), 'temp' => (string)$anio, 'sexo' => '', 'variedad' => '']];
$err = [];
$errFila = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $v['cruce'] = $_POST['cruce'] ?? '';
    $v['nacimiento'] = $_POST['nacimiento'] ?? '';
    $filas = [];
    foreach ($_POST['numero'] ?? [] as $i => $num) {
        $filas[] = ['numero' => trim($num), 'club' => $_POST['club'][$i] ?? '', 'socio' => trim($_POST['socio'][$i] ?? ''), 'temp' => $_POST['temp'][$i] ?? '',
            'sexo' => $_POST['sexo'][$i] ?? '', 'variedad' => trim($_POST['variedad'][$i] ?? '')];
    }
    $cr = $cruces[$v['cruce']] ?? null;
    if (!$cr) $err['cruce'] = 'Elija el cruce de una de sus parejas.';
    if ($v['nacimiento'] === '') $err['nacimiento'] = 'Ingrese la fecha de nacimiento.';
    elseif ($cr && $v['nacimiento'] < $cr['fecha']) $err['nacimiento'] = 'No puede ser anterior al cruce (' . fecha($cr['fecha']) . ').';
    elseif ($v['nacimiento'] > hoy()) $err['nacimiento'] = 'No puede ser posterior a hoy.';

    if (!$filas) $err['crias'] = 'Agregue al menos una cría.';
    $vistos = [];
    foreach ($filas as $i => $a) {
        $e = validar_anillo($a['numero'], $a['club'], $a['socio'], $a['temp']);
        $k = "{$a['numero']}-{$a['club']}-{$a['socio']}-{$a['temp']}";
        if (!$e && (canario($k) || isset($vistos[$k]))) $e['numero'] = 'Anillo no disponible.';
        // Sexo y variedad pueden quedar pendientes (SRS-RF020); si se indican, deben ser válidos
        if ($a['sexo'] !== '' && !in_array($a['sexo'], ['Macho', 'Hembra'], true)) $e['sexo'] = 'Elija macho, hembra o déjelo pendiente.';
        if ($a['variedad'] !== '') {
            $cod = leer_variedad($a['variedad']);
            if (!$cod) $e['variedad'] = 'Elija una variedad del nomenclador o déjela vacía.';
            elseif ($m = error_variedad_sexo($cod, $a['sexo'])) $e['variedad'] = $m;
        }
        $vistos[$k] = true;
        if ($e) $errFila[$i] = $e;
    }

    if (!$err && !$errFila) {
        $nid = $enCurso[$v['cruce']] ?? guardar_nidada(null, ['pareja' => $cr['pid'], 'cruce' => $cr['fecha'], 'nacimiento' => $v['nacimiento']]);
        $_SESSION['nidada_en_curso'][$v['cruce']] = $nid;
        $fallidas = [];
        foreach ($filas as $a) {
            $r = api('POST', '/api/v1/crias', cuerpo_cria(['numero' => (int)$a['numero'], 'club' => $a['club'], 'socio' => (int)$a['socio'], 'temp' => (int)$a['temp'],
                'sexo' => $a['sexo'], 'variedad' => leer_variedad($a['variedad']), 'portadora' => '', 'reservada' => false, 'nidada' => $nid]));
            cortar_si_mantenimiento($r);
            if ($r['status'] < 200 || $r['status'] >= 300) $fallidas[] = [$a, motivo_api($r)];
        }
        $n = count($filas) - count($fallidas);
        if (!$fallidas) {
            unset($_SESSION['nidada_en_curso'][$v['cruce']]);
            redirigir('crias.php', 'Nidada guardada', "Se registraron $n cría" . ($n > 1 ? 's' : '') . " de la pareja {$cr['m']['numero']} ♂ × {$cr['h']['numero']} ♀. Puede completar el sexo y la variedad cuando los conozca.");
        }
        // Se conservan solo las filas rechazadas, con el motivo de la API, para corregirlas y reintentar en la misma nidada
        $filas = array_column($fallidas, 0);
        $errFila = array_map(fn($f) => ['numero' => $f[1]], $fallidas);
        $err['api'] = ($n ? "Se guardaron $n cría" . ($n > 1 ? 's' : '') . ' en la nidada. ' : 'La nidada quedó creada, pero sin crías. ')
            . 'La API rechazó ' . (count($fallidas) > 1 ? 'los anillos marcados' : 'el anillo marcado') . '. Corrija y vuelva a guardar: se agregarán a la misma nidada.';
    }
}

$pagina = 'crias';
$titulo = 'Registrar nidada';
include __DIR__ . '/../includes/header.php';
$msg = fn($campo) => isset($err[$campo]) ? '<span class="msg-error">' . e($err[$campo]) . '</span>' : '';
$temps = array_map('strval', range($anio, $anio - 3));
?>

<p class="migas"><a href="crias.php">Crías</a> / Registrar nidada</p>
<div>
  <p class="eyebrow">Crías y descendencia</p>
  <h1 class="titulo-l">Registrar nidada</h1>
  <p class="bajada">Asocie la nidada al cruce de una pareja e ingrese el anillo de cada cría.</p>
</div>

<?php if (!$cruces): ?>
  <div class="vacio" style="min-height:360px">
    <div class="circulo"><?= icono('corazon', 24) ?></div>
    <h3>No hay cruces disponibles</h3>
    <p>Para registrar una nidada, primero registre la fecha de cruce de una pareja en «Parejas y cruces».</p>
    <div class="acciones"><a href="parejas.php" class="btn btn-primario">Ir a Parejas y cruces</a></div>
  </div>
<?php else: ?>

<?= flash() ?>
<?php if ($err || $errFila): ?>
  <div class="aviso aviso-error"><?= icono('alerta') ?><div><strong><?= isset($err['api']) ? 'La nidada no se guardó completa' : 'No se pudo guardar la nidada' ?></strong><p><?= e($err['api'] ?? 'Revise los campos marcados.') ?></p></div></div>
<?php endif; ?>

<form method="POST" id="formNidada" novalidate>
  <div class="dos-col">
    <div style="display:flex;flex-direction:column;gap:20px">
      <section class="seccion">
        <h2>1. Cruce y nacimiento</h2>
        <div style="display:flex;gap:16px;align-items:flex-start">
          <div class="campo<?= isset($err['cruce']) ? ' error' : '' ?>" style="flex:1">
            <label for="cruce">Cruce de la pareja</label>
            <select class="input" id="cruce" name="cruce">
              <?php foreach ($cruces as $key => $cr): ?>
                <option value="<?= e($key) ?>" <?= $key === $v['cruce'] ? 'selected' : '' ?>
                  data-macho="<?= e(anillo_txt($cr['m'])) ?>" data-hembra="<?= e(anillo_txt($cr['h'])) ?>"
                  data-jaula="<?= e($cr['p']['jaula']) ?>" data-cruce="<?= e(fecha($cr['fecha'])) ?>" data-min="<?= e($cr['fecha']) ?>"
                  data-anteriores="<?= count(nidadas_de_pareja($cr['pid'])) ?> (<?= count(crias_de_pareja($cr['pid'])) ?> crías)"><?= e($cr['txt']) ?></option>
              <?php endforeach; ?>
            </select>
            <?= $msg('cruce') ?>
          </div>
          <div class="campo<?= isset($err['nacimiento']) ? ' error' : '' ?>" style="width:180px">
            <label for="nacimiento">Fecha de nacimiento</label>
            <input class="input" type="date" id="nacimiento" name="nacimiento" max="<?= hoy() ?>" value="<?= e($v['nacimiento']) ?>">
            <?= $msg('nacimiento') ?>
          </div>
        </div>
        <p class="small muted" style="display:flex;gap:8px"><?= icono('info') ?> Solo aparecen los cruces registrados de sus parejas. La fecha debe estar entre el cruce y hoy.</p>
      </section>

      <section class="seccion">
        <h2>2. Crías de la nidada <span class="badge" id="nCrias" style="font-weight:400"></span></h2>
        <p class="small muted">Cada cría necesita su anillo. El sexo y la variedad pueden quedar pendientes y completarse después.</p>
        <?= $msg('crias') ?>
        <div class="fila-cria small" style="color:var(--negro)"><span></span><span>Número de anillo</span><span>Sigla del club</span><span>N.° de socio</span><span>Temporada</span><span>Sexo</span><span>Variedad</span><span></span></div>
        <div id="filas" style="display:flex;flex-direction:column;gap:8px">
          <?php foreach (array_values($filas) as $i => $a): $ef = fn($campo) => isset($errFila[$i][$campo]) ? ' error' : ''; ?>
          <div class="fila-cria">
            <span class="n"><?= $i + 1 ?></span>
            <input class="input<?= $ef('numero') ?>" name="numero[]" inputmode="numeric" maxlength="6" value="<?= e($a['numero']) ?>" aria-label="Número de anillo">
            <select class="input<?= $ef('club') ?>" name="club[]" aria-label="Sigla del club"><?= select_opciones(CLUBES, $a['club']) ?></select>
            <input class="input<?= $ef('socio') ?>" name="socio[]" inputmode="numeric" maxlength="5" value="<?= e($a['socio']) ?>" aria-label="N.° de socio">
            <select class="input<?= $ef('temp') ?>" name="temp[]" aria-label="Temporada"><?= select_opciones($temps, $a['temp']) ?></select>
            <select class="input<?= $ef('sexo') ?>" name="sexo[]" aria-label="Sexo"><?= select_opciones(['Macho' => 'Macho', 'Hembra' => 'Hembra'], $a['sexo'], 'Pendiente') ?></select>
            <input class="input<?= $ef('variedad') ?>" name="variedad[]" list="lista-variedades" autocomplete="off" placeholder="Pendiente" value="<?= e($a['variedad']) ?>" aria-label="Variedad">
            <button type="button" class="quitar" aria-label="Quitar cría"><?= icono('cerrar', 14) ?></button>
            <?php if (isset($errFila[$i])): ?><span class="msg-error"><?= e(implode(' ', $errFila[$i])) ?></span><?php endif; ?>
          </div>
          <?php endforeach; ?>
        </div>
        <div><button type="button" class="btn" id="agregarFila"><?= icono('mas', 14) ?> Agregar otra cría</button></div>
      </section>
    </div>

    <aside class="panel-gris" style="min-height:560px">
      <h3><?= icono('huevo') ?> Pareja seleccionada</h3>
      <div style="display:flex;justify-content:space-between"><span class="muted">Macho</span><strong id="pMacho"></strong></div>
      <div style="display:flex;justify-content:space-between"><span class="muted">Hembra</span><strong id="pHembra"></strong></div>
      <div style="display:flex;justify-content:space-between"><span class="muted">Jaula</span><strong id="pJaula"></strong></div>
      <div style="display:flex;justify-content:space-between"><span class="muted">Cruce</span><strong id="pCruce"></strong></div>
      <p class="muted xs" style="margin-top:auto">Nidadas anteriores de esta pareja:<br><strong style="color:var(--negro)" id="pAnteriores"></strong></p>
    </aside>
  </div>
  <div class="acciones-form" style="margin-top:20px">
    <a href="crias.php" class="btn">Cancelar</a>
    <button class="btn btn-primario">Guardar nidada</button>
  </div>
</form>

<?= datalist_variedades() ?>
<template id="tplFila">
  <div class="fila-cria">
    <span class="n"></span>
    <input class="input" name="numero[]" inputmode="numeric" maxlength="6" aria-label="Número de anillo">
    <select class="input" name="club[]" aria-label="Sigla del club"><?= select_opciones(CLUBES, 'SOCH') ?></select>
    <input class="input" name="socio[]" inputmode="numeric" maxlength="5" aria-label="N.° de socio">
    <select class="input" name="temp[]" aria-label="Temporada"><?= select_opciones($temps, (string)$anio) ?></select>
    <select class="input" name="sexo[]" aria-label="Sexo"><?= select_opciones(['Macho' => 'Macho', 'Hembra' => 'Hembra'], '', 'Pendiente') ?></select>
    <input class="input" name="variedad[]" list="lista-variedades" autocomplete="off" placeholder="Pendiente" aria-label="Variedad">
    <button type="button" class="quitar" aria-label="Quitar cría"><?= icono('cerrar', 14) ?></button>
  </div>
</template>

<script>
  const filas = document.getElementById('filas');
  const renumerar = () => {
    filas.querySelectorAll('.fila-cria').forEach((f, i) => f.querySelector('.n').textContent = i + 1);
    const n = filas.children.length;
    document.getElementById('nCrias').textContent = n + (n === 1 ? ' cría' : ' crías');
  };
  document.getElementById('agregarFila').addEventListener('click', () => {
    const nueva = document.getElementById('tplFila').content.firstElementChild.cloneNode(true);
    // copia club/socio/temporada de la fila anterior para escribir menos
    const ult = filas.lastElementChild;
    if (ult) ['club[]', 'socio[]', 'temp[]', 'sexo[]', 'variedad[]'].forEach(n => nueva.querySelector(`[name="${n}"]`).value = ult.querySelector(`[name="${n}"]`).value);
    filas.appendChild(nueva); renumerar(); nueva.querySelector('input').focus();
  });
  filas.addEventListener('click', e => {
    if (e.target.closest('.quitar') && filas.children.length > 1) { e.target.closest('.fila-cria').remove(); renumerar(); }
  });
  const sel = document.getElementById('cruce');
  const panel = () => {
    const o = sel.selectedOptions[0].dataset;
    pMacho.textContent = o.macho; pHembra.textContent = o.hembra; pJaula.textContent = o.jaula;
    pCruce.textContent = o.cruce; pAnteriores.textContent = o.anteriores;
    document.getElementById('nacimiento').min = o.min;
  };
  sel.addEventListener('change', panel); panel(); renumerar();
</script>
<?php endif; ?>

<?php include __DIR__ . '/../includes/footer.php'; ?>

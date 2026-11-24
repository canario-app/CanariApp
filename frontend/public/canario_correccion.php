<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

$k = $_GET['id'] ?? '';
$c = canario($k);
$motivo = $_SESSION['correccion'][$k] ?? null;
if (!$c) redirigir('canarios.php');
if ($motivo === null) redirigir('canario_ficha.php?id=' . urlencode($k)); // hay que activarlo desde la ficha (pide contraseña)

$ficha = 'canario_ficha.php?id=' . urlencode($k);
if (isset($_GET['salir'])) {
    unset($_SESSION['correccion'][$k]);
    redirigir($ficha, 'Modo de Corrección cerrado', 'No se guardaron cambios.');
}

$rol = $c['sexo'] === 'Hembra' ? 'hembra' : 'macho';           // rol actual en sus parejas
$sus_parejas = array_filter(parejas_de($k), fn($p) => $p['estado'] !== 'Anulada' && $p[$rol] === $k);
$el_rol = $rol === 'macho' ? 'el macho' : 'la hembra';
$verdadero = $rol === 'macho' ? 'el verdadero padre' : 'la verdadera madre';
// Candidatos para reasignar cada pareja (SRS-RF012 a RF015): mismo sexo, no crías de esa pareja
// y, si la pareja está activa, sin otra pareja activa (hembra) o con cupo (macho)
$candidatos_de = function ($pid, $p) use ($c, $k, $rol) {
    $crias = crias_de_pareja($pid);
    $ops = [];
    foreach (por_sexo($c['sexo'] ?: 'Macho') as $ck => $x) {
        if ($ck === $k || isset($crias[$ck])) continue;
        if ($p['estado'] === 'Activa') {
            $act = count(parejas_activas_de($ck));
            if ($rol === 'hembra' ? $act > 0 : $act >= MAX_PAREJAS_MACHO) continue;
        }
        $ops[$ck] = 'Reasignar a ' . anillo_txt($x);
    }
    return $ops;
};

$v = ['sexo' => $c['sexo'], 'variedad' => variedad_txt($c['variedad'])];
$decision = [];
$err = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $v['sexo'] = $_POST['sexo'] ?? '';
    $v['variedad'] = trim($_POST['variedad'] ?? '');
    $decision = $_POST['decision'] ?? [];

    if (!in_array($v['sexo'], ['Macho', 'Hembra'], true)) $err['sexo'] = 'Elija el sexo.';
    $cod = leer_variedad($v['variedad']);
    if (!$cod) $err['variedad'] = 'Elija una variedad de la lista del nomenclador.';
    elseif ($m = error_variedad_sexo($cod, $v['sexo'])) $err['variedad'] = $m;
    if (!$err && $v['sexo'] === $c['sexo'] && $cod === $c['variedad']) $err['sexo'] = 'No cambió el sexo ni la variedad.';

    $cambia_sexo = $c['sexo'] && $v['sexo'] !== $c['sexo'];
    if ($cambia_sexo) {
        foreach ($sus_parejas as $pid => $p) {
            $d = $decision[$pid] ?? '';
            $con_crias = count(crias_de_pareja($pid)) > 0;
            if ($d === '' || ($d === 'anular' && $con_crias) || ($d !== 'anular' && !isset($candidatos_de($pid, $p)[$d]))) {
                $err["p$pid"] = $con_crias ? "Con crías: debe reasignarse a $verdadero." : 'Elija qué hacer con esta pareja.';
            }
        }
    }
    // La API pide la contraseña en cada corrección (SRS-RF030); se confirma antes de tocar las parejas
    $clave = $_POST['clave'] ?? '';
    if (!$err && !verificar_clave($_SESSION['usuario']['correo'], $clave)) $err['clave'] = 'Contraseña incorrecta.';

    if (!$err) {
        // Primero las parejas (el ejemplar todavía tiene el sexo anterior) y después el ejemplar
        if ($cambia_sexo) {
            foreach ($sus_parejas as $pid => $p) {
                $r = corregir_pareja($pid, $rol, $decision[$pid], $motivo);
                cortar_si_mantenimiento($r);
                if ($r['status'] < 200 || $r['status'] >= 300) { $err['api'] = 'Pareja de la jaula ' . $p['jaula'] . ': ' . motivo_api($r); break; }
            }
        }
        if (!$err) {
            $r = corregir_canario($c, $v['sexo'], $cod, $motivo, $clave);
            cortar_si_mantenimiento($r);
            if ($r['status'] < 200 || $r['status'] >= 300) $err['api'] = motivo_api($r);
        }
        if (!$err) {
            $antes = trim("{$c['sexo']} · {$c['variedad']}", ' ·');
            unset($_SESSION['correccion'][$k]);
            redirigir($ficha, 'Corrección guardada', "Antes: $antes. Ahora: {$v['sexo']} · $cod. Quedó registrada en la auditoría con el motivo y su usuario.");
        }
    }
}

$pagina = 'canarios';
$titulo = 'Modo de Corrección';
include __DIR__ . '/../includes/header.php';
$msg = fn($campo) => isset($err[$campo]) ? '<span class="msg-error">' . e($err[$campo]) . '</span>' : '';
?>

<div class="aviso aviso-oscuro">
  <?= icono('llave') ?>
  <div><strong>Modo de Corrección activo</strong><p>Motivo: «<?= e($motivo) ?>»</p></div>
  <a href="canario_correccion.php?id=<?= e(urlencode($k)) ?>&salir=1" class="btn">Salir sin guardar</a>
</div>

<a href="<?= e($ficha) ?>" class="volver"><?= icono('atras', 14) ?> Volver a la ficha</a>
<div>
  <div class="anillo-grande"><?= e($c['numero']) ?> <span>· <?= e("{$c['club']} · {$c['socio']} · {$c['temp']}") ?></span></div>
  <div class="badges"><?= badges_canario($c) ?></div>
</div>

<form method="POST" style="display:flex;flex-direction:column;gap:20px" novalidate>
  <?php if ($err): ?>
    <div class="aviso aviso-error"><?= icono('alerta') ?><div><strong>No se pudo guardar la corrección</strong><p><?= e($err['api'] ?? 'Revise los campos marcados.') ?></p></div></div>
  <?php endif; ?>

  <section class="seccion">
    <h2>Datos a corregir <span class="badge badge-borde" style="font-weight:400">Antes: <?= e(trim("{$c['sexo']} · {$c['variedad']}", ' ·') ?: 'Pendiente') ?></span></h2>
    <div style="display:flex;gap:40px;align-items:flex-start">
      <div class="campo">
        <label class="muted small">Sexo</label>
        <div style="display:flex;gap:16px">
          <?php foreach (['Macho', 'Hembra'] as $s): ?>
            <label><input type="radio" name="sexo" value="<?= $s ?>" <?= $v['sexo'] === $s ? 'checked' : '' ?>> <?= mb_strtolower($s) ?></label>
          <?php endforeach; ?>
        </div>
        <?= $msg('sexo') ?>
      </div>
      <div class="campo<?= isset($err['variedad']) ? ' error' : '' ?>" style="width:420px">
        <label for="variedad">Variedad</label>
        <input class="input" id="variedad" name="variedad" list="lista-variedades" autocomplete="off" value="<?= e($v['variedad']) ?>">
        <?= datalist_variedades() ?>
        <?= $msg('variedad') ?>
      </div>
    </div>
  </section>

  <?php if ($sus_parejas): $pend = count($sus_parejas); ?>
  <section class="seccion">
    <h2>Decida qué hacer con sus parejas <span class="badge badge-borde" style="font-weight:400"><?= $pend ?> pendiente<?= $pend > 1 ? 's' : '' ?></span></h2>
    <p class="small muted" style="max-width:640px">Si cambia el sexo, el ejemplar ya no puede ser <?= $el_rol ?> de estas parejas. Las parejas con crías deben pasar a <?= $verdadero ?> para que ninguna cría quede sin progenitor. Si no cambia el sexo, esta sección se ignora.</p>
    <table class="tabla">
      <thead><tr><th>Pareja con</th><th>Jaula</th><th>Estado</th><th>Crías</th><th>Decisión</th></tr></thead>
      <tbody>
      <?php foreach ($sus_parejas as $pid => $p):
        $otro = canario($p[$rol === 'macho' ? 'hembra' : 'macho']);
        $n = count(crias_de_pareja($pid));
        $ops = ($n ? [] : ['anular' => 'Anular pareja']) + $candidatos_de($pid, $p);
      ?>
        <tr>
          <td><strong><?= e($otro['numero']) ?> <?= $rol === 'macho' ? '♀' : '♂' ?></strong><span class="sub"><?= e("{$otro['club']} · {$otro['socio']} · {$otro['temp']}") ?></span></td>
          <td><?= e($p['jaula']) ?></td>
          <td><span class="badge <?= $p['estado'] === 'Activa' ? 'badge-oscuro' : '' ?>"><?= e($p['estado']) ?></span></td>
          <td><?= $n ?></td>
          <td style="width:320px">
            <select class="input<?= isset($err["p$pid"]) ? ' error' : '' ?>" name="decision[<?= $pid ?>]"><?= select_opciones($ops, $decision[$pid] ?? '', 'Elija una opción') ?></select>
            <?= $msg("p$pid") ?: '<span class="ayuda-campo">' . ($n ? "Con crías: debe reasignarse a $verdadero." : ($p['estado'] === 'Activa' ? 'Activa sin crías: puede reasignarse o anularse.' : 'Sin crías: puede reasignarse o anularse.')) . '</span>' ?>
          </td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </section>

  <div class="aviso"><?= icono('info') ?><div><strong>Si <?= $verdadero ?> no está <?= $rol === 'macho' ? 'registrado' : 'registrada' ?></strong><p>Regístrelo primero en <a href="canario_registrar.php" style="text-decoration:underline">«Registrar ejemplar»</a> y vuelva a esta corrección.</p></div></div>
  <?php endif; ?>

  <section class="seccion">
    <div class="campo<?= isset($err['clave']) ? ' error' : '' ?>" style="max-width:320px">
      <label for="clave">Contraseña</label>
      <input class="input" type="password" id="clave" name="clave" autocomplete="current-password">
      <?= $msg('clave') ?: '<span class="ayuda-campo">Confirme su contraseña para guardar la corrección.</span>' ?>
    </div>
  </section>

  <div class="acciones-form">
    <a href="canario_correccion.php?id=<?= e(urlencode($k)) ?>&salir=1" class="btn">Cancelar corrección</a>
    <button class="btn btn-primario">Guardar corrección</button>
  </div>
</form>

<?php include __DIR__ . '/../includes/footer.php'; ?>

<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

$anio = (int)date('Y');
$v = ['numero' => $_GET['numero'] ?? '', 'club' => 'SOCH', 'socio' => mi_socio(), 'temp' => (string)$anio, 'sexo' => '', 'variedad' => ''];
$v = array_merge($v, array_intersect_key(post_previo(), $v));
$err = [];
$duplicado = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    foreach ($v as $k => $_) $v[$k] = trim($_POST[$k] ?? '');
    $err = validar_anillo($v['numero'], $v['club'], $v['socio'], $v['temp']);

    if (!in_array($v['sexo'], ['Macho', 'Hembra'], true)) $err['sexo'] = 'Elija el sexo del ejemplar.';
    $cod = leer_variedad($v['variedad']);
    if (!$cod) {
        $err['variedad'] = 'Elija una variedad de la lista del nomenclador.';
    } elseif ($m = error_variedad_sexo($cod, $v['sexo'])) {
        $err['variedad'] = $m;
    }

    if (!isset($err['numero'], $err['socio']) && canario("{$v['numero']}-{$v['club']}-{$v['socio']}-{$v['temp']}")) {
        $duplicado = true;
        $err['numero'] = 'Ya registrado.';
    }

    if (!$err) {
        guardar_canario([
            'numero' => (int)$v['numero'], 'club' => $v['club'], 'socio' => (int)$v['socio'], 'temp' => (int)$v['temp'],
            'sexo' => $v['sexo'], 'variedad' => $cod, 'portadora' => '', 'reservada' => false, 'estado' => '',
            'padre' => null, 'madre' => null, 'nacimiento' => null, 'nidada' => null,
        ]);
        redirigir('canarios.php', 'Ejemplar registrado', "Se registró el anillo {$v['numero']} · {$v['club']} · {$v['socio']} · {$v['temp']}.");
    }
}

$pagina = 'canarios';
$titulo = 'Registrar ejemplar';
$scripts = ['js/registrar_ejemplar.js'];
include __DIR__ . '/../includes/header.php';
$cls = fn($campo) => isset($err[$campo]) ? ' error' : '';
$msg = fn($campo, $ayuda = '') => isset($err[$campo]) ? '<span class="msg-error">' . e($err[$campo]) . '</span>' : ($ayuda ? '<span class="ayuda-campo">' . e($ayuda) . '</span>' : '');
?>

<p class="migas"><a href="canarios.php">Canarios</a> / Registrar ejemplar</p>
<div>
  <p class="eyebrow">Registro del criadero</p>
  <h1 class="titulo-l">Registrar ejemplar</h1>
  <p class="bajada">Ingrese el anillo completo, el sexo y la variedad del ejemplar.</p>
</div>

<div class="dos-col">
  <form method="POST" style="display:flex;flex-direction:column;gap:20px" id="formEjemplar" novalidate>
    <?= flash() ?>
    <?php if ($duplicado): ?>
      <div class="aviso aviso-error"><?= icono('alerta') ?><div><strong>Anillo no disponible</strong><p>Esa combinación de número de anillo, club, socio y temporada ya está registrada. Revise los datos del anillo.</p></div></div>
    <?php elseif ($err): ?>
      <div class="aviso aviso-error"><?= icono('alerta') ?><div><strong>No se pudo registrar el ejemplar</strong><p>Revise los campos marcados.</p></div></div>
    <?php endif; ?>

    <section class="seccion">
      <h2>1. Anillo</h2>
      <div class="fila-campos">
        <div class="campo<?= $cls('numero') ?>">
          <label for="numero">Número de anillo</label>
          <input class="input" id="numero" name="numero" inputmode="numeric" maxlength="6" value="<?= e($v['numero']) ?>">
          <?= $msg('numero', '1 a 6 dígitos') ?>
        </div>
        <div class="campo<?= $cls('club') ?>">
          <label for="club">Sigla del club</label>
          <select class="input" id="club" name="club"><?= select_opciones(CLUBES, $v['club']) ?></select>
          <?= $msg('club', 'CON, COV, COR o SOCH') ?>
        </div>
        <div class="campo<?= $cls('socio') ?>">
          <label for="socio">N.° de socio</label>
          <input class="input" id="socio" name="socio" inputmode="numeric" maxlength="5" value="<?= e($v['socio']) ?>">
          <?= $msg('socio', '1 a 5 dígitos') ?>
        </div>
        <div class="campo<?= $cls('temp') ?>">
          <label for="temp">Temporada</label>
          <select class="input" id="temp" name="temp"><?= select_opciones(array_map('strval', range($anio, $anio - 6)), $v['temp']) ?></select>
          <?= $msg('temp', 'Por defecto, el año en curso') ?>
        </div>
      </div>
    </section>

    <section class="seccion">
      <h2>2. Sexo y variedad</h2>
      <div class="campo<?= $cls('sexo') ?>">
        <label>Sexo</label>
        <div class="radios-sexo">
          <?php foreach (['Macho', 'Hembra'] as $s): ?>
            <label class="radio"><input type="radio" name="sexo" value="<?= $s ?>" <?= $v['sexo'] === $s ? 'checked' : '' ?>> <?= $s ?></label>
          <?php endforeach; ?>
        </div>
        <?= $msg('sexo') ?>
      </div>
      <div class="campo<?= $cls('variedad') ?>">
        <label for="variedad">Variedad del nomenclador</label>
        <div class="input-icono izq">
          <?= str_replace('class="ico"', 'class="ico" style="position:absolute;left:12px;top:12px"', icono('buscar')) ?>
          <input class="input" id="variedad" name="variedad" list="lista-variedades" autocomplete="off" placeholder="Ej.: CC033" style="padding-left:36px" value="<?= e($v['variedad']) ?>">
        </div>
        <?= datalist_variedades() ?>
        <?= $msg('variedad') ?>
        <span class="ayuda-campo">Escriba el código o el nombre y elija de la lista.</span>
      </div>
    </section>

    <div class="acciones-form">
      <a href="canarios.php" class="btn">Cancelar</a>
      <button type="submit" class="btn btn-primario">Registrar ejemplar</button>
    </div>
  </form>

  <aside class="panel-gris">
    <h3>Vista previa</h3>
    <div style="font-size:18px" id="prevAnillo"><strong>—</strong></div>
    <div class="badges" id="prevBadges"></div>
    <hr style="border:0;border-top:1px solid var(--gris-borde)">
    <p class="muted" style="display:flex;gap:8px"><?= icono('info') ?><span>Las crías se registran desde <strong style="color:var(--negro)">Crías → Registrar nidada</strong>, así quedan unidas a sus padres.</span></p>
  </aside>
</div>

<?php include __DIR__ . '/../includes/footer.php'; ?>

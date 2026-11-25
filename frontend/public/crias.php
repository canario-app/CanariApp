<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

$anio = date('Y');
$f = [
    'anillo'    => trim($_GET['anillo'] ?? ''),
    'pareja'    => $_GET['pareja'] ?? '',
    'temporada' => $_GET['temporada'] ?? '',
    'filtro'    => $_GET['filtro'] ?? 'todas',
];
$qs = fn($extra = []) => 'crias.php?' . http_build_query(array_merge(array_filter($f, fn($x) => $x !== '' && $x !== 'todas'), $extra));

$err = [];
$post = $_POST ?: post_previo();
$completar = $_GET['completar'] ?? '';
$agregar = (int)($_GET['agregar'] ?? 0);

// ---------- Acciones ----------
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $accion = $_POST['accion'] ?? '';

    if ($accion === 'completar' && ($c = canario($completar))) {
        $sexo = $c['sexo'] ?: ($post['sexo'] ?? '');
        if (!in_array($sexo, ['Macho', 'Hembra', ''], true)) $sexo = '';
        $cod = $c['variedad'];
        if (!$cod && trim($post['variedad'] ?? '') !== '') {
            $cod = leer_variedad($post['variedad']);
            if (!$cod) $err['variedad'] = 'Elija una variedad de la lista del nomenclador.';
            elseif ($m = error_variedad_sexo($cod, $sexo)) $err['variedad'] = 'Si la variedad indica sexo, debe coincidir con el de la cría.';
        }
        if (!$err) {
            $c['sexo'] = $sexo;
            $c['variedad'] = $cod ?: '';
            $c['portadora'] = in_array($post['portadora'] ?? '', factores_para($sexo), true) ? $post['portadora'] : '';
            $c['reservada'] = !empty($post['reservada']);
            guardar_canario($c);
            redirigir($qs(), 'Datos guardados', 'Se actualizó la cría ' . anillo_txt($c) . '.');
        }
    }

    if ($accion === 'agregar' && ($n = nidada($agregar))) {
        $a = ['numero' => trim($post['numero'] ?? ''), 'club' => $post['club'] ?? '', 'socio' => trim($post['socio'] ?? ''), 'temp' => $post['temp'] ?? ''];
        $err = validar_anillo($a['numero'], $a['club'], $a['socio'], $a['temp']);
        if (!$err && canario("{$a['numero']}-{$a['club']}-{$a['socio']}-{$a['temp']}")) $err['numero'] = 'Anillo no disponible.';
        // Sexo y variedad pueden quedar pendientes (SRS-RF020)
        $sx = $post['sexo'] ?? '';
        if (!in_array($sx, ['Macho', 'Hembra', ''], true)) $err['sexo'] = 'Elija macho, hembra o déjelo pendiente.';
        $cod = '';
        if (trim($post['variedad'] ?? '') !== '') {
            $cod = leer_variedad($post['variedad']);
            if (!$cod) $err['variedad'] = 'Elija una variedad del nomenclador o déjela vacía.';
            elseif ($m = error_variedad_sexo($cod, $sx)) $err['variedad'] = $m;
        }
        if (!$err) {
            $p = pareja($n['pareja']);
            $nueva = ['numero' => (int)$a['numero'], 'club' => $a['club'], 'socio' => (int)$a['socio'], 'temp' => (int)$a['temp'],
                'sexo' => $sx, 'variedad' => $cod, 'portadora' => '', 'reservada' => false, 'estado' => '',
                'padre' => $p['macho'], 'madre' => $p['hembra'], 'nacimiento' => $n['nacimiento'], 'nidada' => $agregar];
            guardar_canario($nueva);
            redirigir($qs(), 'Cría agregada', 'Se agregó el anillo ' . anillo_txt($nueva) . ' a la nidada.');
        }
    }
}

// ---------- Datos para la vista ----------
$nids = nidadas();
uasort($nids, fn($a, $b) => strcmp($b['nacimiento'], $a['nacimiento']));
$todas_crias = array_filter(canarios(), fn($c) => $c['nidada']);

$grupos = [];
foreach ($nids as $nid => $n) {
    if ($f['pareja'] !== '' && (string)$n['pareja'] !== $f['pareja']) continue;
    if ($f['temporada'] !== '' && substr($n['nacimiento'], 0, 4) !== $f['temporada']) continue;
    $crias = array_filter(crias_de_nidada($nid), function ($c) use ($f) {
        if ($f['anillo'] !== '' && !str_starts_with((string)$c['numero'], $f['anillo'])) return false;
        return match ($f['filtro']) {
            'pendientes' => es_pendiente($c),
            'portadoras' => $c['portadora'] !== '',
            'reservadas' => $c['reservada'],
            default => true,
        };
    });
    if (!$crias && ($f['anillo'] !== '' || $f['filtro'] !== 'todas')) continue;
    $grupos[$nid] = [$n, $crias];
}

$temp_actual = $f['temporada'] ?: $anio;
$nid_temp = array_filter($nids, fn($n) => substr($n['nacimiento'], 0, 4) === (string)$temp_actual);
$opParejas = [];
foreach (parejas() as $pid => $p) {
    if (nidadas_de_pareja($pid)) $opParejas[$pid] = canario($p['macho'])['numero'] . ' ♂ × ' . canario($p['hembra'])['numero'] . ' ♀';
}
$temporadas = array_unique(array_map(fn($n) => substr($n['nacimiento'], 0, 4), $nids));
rsort($temporadas);

$pagina = 'crias';
$titulo = 'Crías';
include __DIR__ . '/../includes/header.php';
$msg = fn($campo) => isset($err[$campo]) ? '<span class="msg-error">' . e($err[$campo]) . '</span>' : '';
?>

<?= flash() ?>

<div class="page-head">
  <div>
    <p class="eyebrow">Registro de crías</p>
    <h1 class="titulo-l">Nidadas y crías</h1>
    <p class="bajada">Registre cada nidada a partir del cruce de una pareja y complete el sexo y la variedad de las crías cuando los conozca.</p>
  </div>
  <a href="nidada_registrar.php" class="btn btn-primario btn-lg"><?= icono('mas') ?> Registrar nidada</a>
</div>

<?php if (!$nids): ?>
<div class="vacio">
  <div class="circulo"><img src="img/huevo.svg" width="26" height="26" alt=""></div>
  <h3>Aún no hay nidadas registradas</h3>
  <p>Para registrar una nidada, primero forme una pareja y registre su fecha de cruce en «Parejas y cruces».</p>
  <div class="acciones">
    <a href="parejas.php" class="btn">Ir a Parejas y cruces <img src="img/flecha-der.svg" width="16" height="16" alt=""></a>
    <a href="nidada_registrar.php" class="btn btn-primario"><?= icono('mas') ?> Registrar nidada</a>
  </div>
</div>
<?php else: ?>

<div class="stats">
  <div class="stat"><span>Nidadas de la temporada</span><strong><?= count($nid_temp) ?></strong></div>
  <div class="stat"><span>Crías registradas</span><strong><?= count($todas_crias) ?></strong></div>
  <div class="stat"><span>Con datos pendientes</span><strong><?= count(array_filter($todas_crias, 'es_pendiente')) ?></strong></div>
  <div class="stat"><span>Reservadas</span><strong><?= count(array_filter($todas_crias, fn($c) => $c['reservada'])) ?></strong></div>
</div>

<form class="panel" method="GET" style="flex-direction:row;align-items:flex-end;justify-content:space-between;flex-wrap:wrap">
  <input type="hidden" name="filtro" value="<?= e($f['filtro']) ?>">
  <div class="filtros-campos" style="flex:1">
    <div class="campo" style="flex:1">
      <label for="anillo">Buscar cría por anillo</label>
      <div class="input-icono izq">
        <?= str_replace('class="ico"', 'class="ico" style="position:absolute;left:12px;top:12px"', icono('buscar')) ?>
        <input class="input" id="anillo" name="anillo" placeholder="Ej.: 4512" style="padding-left:36px" value="<?= e($f['anillo']) ?>">
      </div>
    </div>
    <div class="campo" style="flex:1">
      <label for="pareja">Pareja</label>
      <select class="input" id="pareja" name="pareja" onchange="this.form.submit()"><?= select_opciones($opParejas, $f['pareja'], 'Todas las parejas') ?></select>
    </div>
    <div class="campo" style="flex:1">
      <label for="temporada">Temporada</label>
      <select class="input" id="temporada" name="temporada" onchange="this.form.submit()"><?= select_opciones(array_map('strval', $temporadas), $f['temporada'], 'Todas') ?></select>
    </div>
  </div>
  <div class="chips" style="margin-left:16px;padding-bottom:8px">
    <?php foreach (['todas' => 'Todas', 'pendientes' => 'Pendientes', 'portadoras' => 'Portadoras', 'reservadas' => 'Reservadas'] as $k => $t): ?>
      <a class="chip <?= $f['filtro'] === $k ? 'activo' : '' ?>" href="<?= e($qs(['filtro' => $k])) ?>"><?= $t ?></a>
    <?php endforeach; ?>
  </div>
</form>

<?php if (!$grupos): ?>
  <div class="vacio" style="min-height:240px"><h3>No hay crías con estos filtros</h3><p>Pruebe con otra búsqueda.</p><div class="acciones"><a class="btn" href="crias.php">Limpiar filtros</a></div></div>
<?php endif; ?>

<div class="dos-col-igual">
<?php foreach ($grupos as $nid => [$n, $crias]):
  $p = pareja($n['pareja']);
  $pend = count(array_filter(crias_de_nidada($nid), 'es_pendiente'));
?>
  <section class="nidada-card">
    <div class="nidada-head">
      <span class="circulo"><?= icono('huevo') ?></span>
      <div style="flex:1">
        <strong><?= e(canario($p['macho'])['numero']) ?> ♂ × <?= e(canario($p['hembra'])['numero']) ?> ♀</strong>
        <div class="xs muted">Jaula <?= e($p['jaula']) ?> · Cruce <?= e(fecha($n['cruce'])) ?> · Nacimiento <?= e(fecha($n['nacimiento'])) ?> · <?= count(crias_de_nidada($nid)) ?> crías</div>
      </div>
      <?php if ($pend): ?><span class="badge badge-borde"><?= $pend ?> con datos pendientes</span><?php endif; ?>
      <a href="<?= e($qs(['agregar' => $nid])) ?>" class="btn btn-sm"><?= icono('mas', 14) ?> Agregar cría</a>
    </div>
    <table class="tabla">
      <thead><tr><th>Anillo</th><th>Sexo</th><th>Variedad</th><th>Marcas</th><th></th></tr></thead>
      <tbody>
      <?php foreach ($crias as $k => $c): ?>
        <tr>
          <td><?= anillo_html($c) ?></td>
          <td><?= $c['sexo'] ? e($c['sexo']) : '<span class="badge badge-tenue">Pendiente</span>' ?></td>
          <td><?= $c['variedad'] ? e(variedad_txt($c['variedad'])) : '<span class="badge badge-tenue">Pendiente</span>' ?></td>
          <td><?= marcas_html($c) ?></td>
          <td class="acciones">
            <?php if (es_pendiente($c)): ?>
              <a class="link" href="<?= e($qs(['completar' => $k])) ?>">Completar datos <?= icono('chevron', 12) ?></a>
            <?php else: ?>
              <a class="link" style="font-weight:400;color:var(--gris-texto)" href="canario_ficha.php?id=<?= e(urlencode($k)) ?>">Ver ficha <?= icono('chevron', 12) ?></a>
            <?php endif; ?>
          </td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </section>
<?php endforeach; ?>
</div>
<?php endif; ?>

<?php if ($c = canario($completar)):
  $n = nidada($c['nidada']); $p = $n ? pareja($n['pareja']) : null;
  $sexo_actual = $post['sexo'] ?? $c['sexo'];
?>
<!-- Modal: Completar datos de la cría -->
<div class="modal abierto" id="m-completar"><div class="modal-caja ancho">
  <a href="<?= e($qs()) ?>" class="modal-x" aria-label="Cerrar"><?= icono('cerrar', 18) ?></a>
  <div>
    <p class="eyebrow">Completar datos de la cría</p>
    <div class="anillo-grande" style="font-size:30px"><?= e($c['numero']) ?> <span>· <?= e("{$c['club']} · {$c['socio']} · {$c['temp']}") ?></span></div>
    <?php if ($p): ?><p class="small muted">Nidada del <?= e(fecha($n['nacimiento'])) ?> · Pareja <?= e(canario($p['macho'])['numero']) ?> ♂ × <?= e(canario($p['hembra'])['numero']) ?> ♀</p><?php endif; ?>
  </div>
  <form method="POST" action="<?= e($qs(['completar' => $completar])) ?>" style="display:flex;flex-direction:column;gap:18px">
    <input type="hidden" name="accion" value="completar">
    <div class="campo">
      <label>Sexo</label>
      <div class="radios-sexo">
        <?php foreach (['Macho' => 'Macho', 'Hembra' => 'Hembra', '' => 'Pendiente'] as $val => $txt): ?>
          <label class="radio"><input type="radio" name="sexo" value="<?= $val ?>" <?= $sexo_actual === $val ? 'checked' : '' ?> <?= $c['sexo'] ? 'disabled' : '' ?>> <?= $txt ?></label>
        <?php endforeach; ?>
      </div>
    </div>
    <div class="campo<?= isset($err['variedad']) ? ' error' : '' ?>">
      <label for="variedad">Variedad del nomenclador</label>
      <input class="input" id="variedad" name="variedad" list="lista-variedades" autocomplete="off" placeholder="Código o nombre, ej.: D.033" value="<?= e($post['variedad'] ?? variedad_txt($c['variedad'])) ?>" <?= $c['variedad'] ? 'disabled' : '' ?>>
      <?= datalist_variedades() ?>
      <?= $msg('variedad') ?: '<span class="ayuda-campo">Escriba el código o el nombre. Si la variedad indica sexo, debe coincidir con el de la cría.</span>' ?>
    </div>
    <div class="seccion" style="padding:16px">
      <div class="campo">
        <label for="portadora"><strong>Portador de un factor genético</strong></label>
        <select class="input" id="portadora" name="portadora"><?= select_opciones(factores_para($c['sexo']), $post['portadora'] ?? $c['portadora'], 'No es portador') ?></select>
        <?php if ($c['sexo'] !== 'Macho' && FACTORES_LIGADOS): ?><span class="ayuda-campo">Las hembras no pueden ser portadoras de mutaciones ligadas al sexo (<?= e(implode(', ', FACTORES_LIGADOS)) ?>).</span><?php endif; ?>
      </div>
      <label class="switch"><input type="checkbox" name="reservada" value="1" <?= ($post ? !empty($post['reservada']) : $c['reservada']) ? 'checked' : '' ?>><span><strong>Reservada para mi criadero</strong><br><span class="small muted">Puede quitar las marcas cuando quiera.</span></span></label>
    </div>
    <div class="aviso"><?= icono('candado') ?><div><strong>Después de guardar</strong><p>El sexo y la variedad solo se cambian con el Modo de Corrección.</p></div></div>
    <div class="acciones-form"><a href="<?= e($qs()) ?>" class="btn">Cancelar</a><button class="btn btn-primario">Guardar datos</button></div>
  </form>
</div></div>
<?php endif; ?>

<?php if ($n = nidada($agregar)): $p = pareja($n['pareja']); ?>
<!-- Modal: Agregar cría a la nidada -->
<div class="modal abierto" id="m-agregar"><div class="modal-caja">
  <a href="<?= e($qs()) ?>" class="modal-x" aria-label="Cerrar"><?= icono('cerrar', 18) ?></a>
  <div>
    <p class="eyebrow">Agregar cría</p>
    <h2><?= e(canario($p['macho'])['numero']) ?> ♂ × <?= e(canario($p['hembra'])['numero']) ?> ♀</h2>
    <p class="small muted">Nidada del <?= e(fecha($n['nacimiento'])) ?> · Jaula <?= e($p['jaula']) ?></p>
  </div>
  <form method="POST" action="<?= e($qs(['agregar' => $agregar])) ?>" style="display:flex;flex-direction:column;gap:18px">
    <input type="hidden" name="accion" value="agregar">
    <div class="dos-col-igual" style="gap:12px">
      <div class="campo<?= isset($err['numero']) ? ' error' : '' ?>"><label for="numero">Número de anillo</label><input class="input" id="numero" name="numero" inputmode="numeric" maxlength="6" value="<?= e($post['numero'] ?? '') ?>"><?= $msg('numero') ?></div>
      <div class="campo"><label for="club">Sigla del club</label><select class="input" id="club" name="club"><?= select_opciones(CLUBES, $post['club'] ?? 'SOCH') ?></select></div>
      <div class="campo<?= isset($err['socio']) ? ' error' : '' ?>"><label for="socio">N.° de socio</label><input class="input" id="socio" name="socio" inputmode="numeric" maxlength="5" value="<?= e($post['socio'] ?? canario($p['macho'])['socio']) ?>"><?= $msg('socio') ?></div>
      <div class="campo"><label for="temp">Temporada</label><select class="input" id="temp" name="temp"><?= select_opciones(array_map('strval', range($anio, $anio - 3)), $post['temp'] ?? substr($n['nacimiento'], 0, 4)) ?></select></div>
    </div>
    <div class="campo<?= isset($err['sexo']) ? ' error' : '' ?>"><label>Sexo</label>
      <div class="radios-sexo"><?php foreach (['Macho' => 'Macho', 'Hembra' => 'Hembra', '' => 'Pendiente'] as $s => $txt): ?><label class="radio"><input type="radio" name="sexo" value="<?= $s ?>" <?= ($post['sexo'] ?? '') === $s ? 'checked' : '' ?>> <?= $txt ?></label><?php endforeach; ?></div>
      <?= $msg('sexo') ?></div>
    <div class="campo<?= isset($err['variedad']) ? ' error' : '' ?>"><label for="variedad_n">Variedad del nomenclador</label>
      <input class="input" id="variedad_n" name="variedad" list="lista-variedades" autocomplete="off" placeholder="Código o nombre, ej.: D.033" value="<?= e($post['variedad'] ?? '') ?>">
      <?= datalist_variedades() ?>
      <?= $msg('variedad') ?></div>
    <div class="acciones-form"><a href="<?= e($qs()) ?>" class="btn">Cancelar</a><button class="btn btn-primario">Agregar cría</button></div>
  </form>
</div></div>
<?php endif; ?>

<?php include __DIR__ . '/../includes/footer.php'; ?>

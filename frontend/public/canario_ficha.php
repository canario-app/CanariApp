<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

$k = $_GET['id'] ?? '';
$c = canario($k);
if (!$c) redirigir('canarios.php', 'Ejemplar no encontrado', 'El anillo que buscó no está en su criadero.');
$url = 'canario_ficha.php?id=' . urlencode($k);

$err = [];
$modal_abierto = '';
$post = $_POST;
// Si la API rechazó el formulario, se reabre el modal con lo que había escrito
if (!$post && ($post = post_previo())) $modal_abierto = ['solicitar' => 'm-solicitar', 'titulo' => 'm-titulo', 'marcas' => 'm-marcas'][$post['accion'] ?? ''] ?? '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    switch ($_POST['accion'] ?? '') {
        case 'solicitar':
            if (trim($post['motivo'] ?? '') === '') { $err['motivo'] = 'Explique qué está mal y cuál es el dato correcto.'; $modal_abierto = 'm-solicitar'; break; }
            // Backend (SRS-RF033): POST /api/v1/solicitudes-correccion {id_canario, dato_a_corregir: sexo|variedad, motivo}
            api_escribir('POST', '/api/v1/solicitudes-correccion', [
                'id_canario' => (int)$c['id'],
                'dato_a_corregir' => ($post['dato'] ?? '') === 'Variedad' ? 'variedad' : 'sexo',
                'motivo' => trim($post['motivo']),
            ]);
            redirigir($url, 'Solicitud enviada', 'El administrador revisará la corrección. La ficha mostrará «Corrección solicitada» hasta que se resuelva.');

        case 'cancelar_solicitud':
            foreach (api_lista('/api/v1/solicitudes-correccion?estado=pendiente&id_canario=' . (int)$c['id']) as $s) {
                api_escribir('PATCH', '/api/v1/solicitudes-correccion/' . (int)$s['id_solicitud'] . '/cancelar', ['motivo' => 'Cancelada por el criador']);
            }
            unset($_SESSION['correcciones_pendientes'][$k]);
            redirigir($url, 'Solicitud cancelada', 'Se retiró la solicitud de corrección.');

        case 'modo_correccion':
            if (!verificar_clave($_SESSION['usuario']['correo'], $post['clave'] ?? '')) $err['clave'] = 'Contraseña incorrecta.';
            if (trim($post['motivo_corr'] ?? '') === '') $err['motivo_corr'] = 'Indique el motivo de la corrección.';
            if ($err) { $modal_abierto = 'm-correccion'; break; }
            $_SESSION['correccion'][$k] = trim($post['motivo_corr']);
            redirigir('canario_correccion.php?id=' . urlencode($k));

        case 'titulo':
            $nombre = trim($post['nombre'] ?? '');
            $f = $post['fecha'] ?? '';
            if ($nombre === '') $err['nombre'] = 'Ingrese el nombre del título.';
            elseif (mb_strlen($nombre) > 100) $err['nombre'] = 'Máximo 100 caracteres.';
            if ($f === '') $err['fecha'] = 'Ingrese la fecha (no puede ser posterior a hoy).';
            elseif ($f > hoy()) $err['fecha'] = 'La fecha no puede ser posterior a hoy.';
            if ($err) { $modal_abierto = 'm-titulo'; break; }
            guardar_titulo(['canario' => $k, 'nombre' => $nombre, 'fecha' => $f]);
            redirigir($url, 'Título agregado', $nombre);

        case 'marcas':
            // Las marcas viven en la tabla cría: solo las crías las tienen
            if (empty($c['id_cria'])) redirigir($url);
            $c['portadora'] = in_array($post['portadora'] ?? '', factores_para($c['sexo']), true) ? $post['portadora'] : '';
            $c['reservada'] = !empty($post['reservada']);
            guardar_canario($c);
            redirigir($url, 'Marcas actualizadas', '');
    }
}

$padre = canario($c['padre'] ?? '');
$madre = canario($c['madre'] ?? '');
$abuelos = [
    'Abuelo paterno' => $padre ? canario($padre['padre'] ?? '') : null,
    'Abuela paterna' => $padre ? canario($padre['madre'] ?? '') : null,
    'Abuelo materno' => $madre ? canario($madre['padre'] ?? '') : null,
    'Abuela materna' => $madre ? canario($madre['madre'] ?? '') : null,
];
$sus_parejas = parejas_de($k);
$sus_titulos = titulos_de($k);
$nid = $c['nidada'] ? nidada($c['nidada']) : null;
$jaula_nac = $nid ? (pareja($nid['pareja'])['jaula'] ?? null) : null;
$rol_otro = $c['sexo'] === 'Hembra' ? 'macho' : 'hembra';
// Crías por pareja (SRS-RF024): una pestaña por pareja con crías
$grupos = [];
foreach ($sus_parejas as $pid => $p) if ($cs = crias_de_pareja($pid)) $grupos[$pid] = [$p, canario($p[$rol_otro]), $cs];
$tab = isset($grupos[(int)($_GET['pareja'] ?? 0)]) ? (int)$_GET['pareja'] : array_key_first($grupos);

$pagina = 'canarios';
$titulo = 'Ficha ' . $c['numero'];
include __DIR__ . '/../includes/header.php';

$nodo = function ($etiqueta, $x, $actual = false) {
    if (!$x) return '<div class="nodo vacio-n"><span>' . e($etiqueta) . '</span>No registrado</div>';
    return '<a href="canario_ficha.php?id=' . e(urlencode(clave($x))) . '" class="nodo' . ($actual ? ' actual' : '') . '"><span>' . e($etiqueta) . '</span><strong>' . e($x['numero']) . '</strong><span>' . e("{$x['club']} · {$x['socio']} · {$x['temp']}") . '</span></a>';
};
$msg = fn($campo) => isset($err[$campo]) ? '<span class="msg-error">' . e($err[$campo]) . '</span>' : '';
?>

<?= flash() ?>

<a href="canarios.php" class="volver"><?= icono('atras', 14) ?> Volver al listado</a>
<div class="page-head" style="align-items:flex-start">
  <div>
    <div class="anillo-grande"><?= e($c['numero']) ?> <span>· <?= e("{$c['club']} · {$c['socio']} · {$c['temp']}") ?></span></div>
    <?php if ($sus_titulos): ?>
      <p style="margin:6px 0;display:flex;gap:8px;align-items:center;flex-wrap:wrap"><?= icono('trofeo') ?> <strong>Ejemplar ganador</strong>
        <span class="muted"><?= e(implode(' · ', array_map(fn($t) => $t['nombre'] . ' (' . fecha($t['fecha']) . ')', $sus_titulos))) ?></span></p>
    <?php endif; ?>
    <div class="badges"><?= badges_canario($c) ?></div>
  </div>
  <div style="display:flex;gap:8px">
    <?php if ($c['estado'] === 'correccion'): ?>
      <form method="POST"><input type="hidden" name="accion" value="cancelar_solicitud"><button class="btn"><?= icono('cerrar', 14) ?> Cancelar solicitud</button></form>
    <?php else: ?>
      <button class="btn" data-modal="m-solicitar"><?= icono('enviar', 14) ?> Solicitar corrección</button>
    <?php endif; ?>
    <button class="btn btn-primario" data-modal="m-correccion"><?= icono('llave', 14) ?> Modo de Corrección</button>
  </div>
</div>

<?php if ($c['estado'] === 'revision'): ?>
  <div class="aviso aviso-warn"><?= icono('alerta') ?><div><strong>Este ejemplar requiere revisión</strong><p>Cambió el nomenclador y su variedad ya no coincide con el sexo registrado. Use el Modo de Corrección.</p></div></div>
<?php endif; ?>

<section class="card">
  <div class="kv">
    <div><span>Sexo</span><?= $c['sexo'] ? e($c['sexo']) : 'Pendiente' ?></div>
    <div><span>Variedad</span><?= $c['variedad'] ? e(variedad_txt($c['variedad'])) . (tipo_variedad($c['variedad']) ? ' (' . e(tipo_variedad($c['variedad'])) . ')' : '') : 'Pendiente' ?></div>
    <div><span>Nacimiento</span><?= $c['nacimiento'] ? e(fecha($c['nacimiento'])) . ($jaula_nac ? ' · nidada de la jaula ' . e($jaula_nac) : '') : '—' ?></div>
    <div><span>Padre</span><?= $padre ? anillo_html($padre) : '<span class="muted">No registrado</span>' ?></div>
    <div><span>Madre</span><?= $madre ? anillo_html($madre) : '<span class="muted">No registrada</span>' ?></div>
    <div><span>Estado</span><?= ['revision' => 'Requiere revisión', 'correccion' => 'Corrección solicitada'][$c['estado']] ?? 'Sin solicitudes pendientes' ?></div>
  </div>
  <?php if ($c['id_cria']): ?>
  <hr style="border:0;border-top:1px solid var(--gris-linea);margin:16px 0">
  <div style="display:flex;justify-content:space-between;align-items:flex-end">
    <div class="kv" style="grid-template-columns:auto auto;gap:24px">
      <div><span><?= portador_txt($c) ?></span><?= $c['portadora'] ? 'Sí · ' . e($c['portadora']) : 'No' ?></div>
      <div><span>Reservada</span><?= $c['reservada'] ? 'Sí' : 'No' ?></div>
    </div>
    <button class="btn btn-sm" data-modal="m-marcas">Editar marcas</button>
  </div>
  <?php endif; ?>
</section>

<div class="dos-col-igual">
  <div style="display:flex;flex-direction:column;gap:16px">
    <section class="card">
      <h2 style="font-size:18px;font-weight:600;display:flex;justify-content:space-between;margin-bottom:16px">Genealogía <?= icono('arbol') ?></h2>
      <div class="genealogia">
        <div style="grid-row:2/4"><?= $nodo('Ejemplar', $c, true) ?></div>
        <div style="grid-column:2;grid-row:1/3"><?= $nodo('Padre', $padre) ?></div>
        <div style="grid-column:2;grid-row:3/5"><?= $nodo('Madre', $madre) ?></div>
        <?php $i = 1; foreach ($abuelos as $et => $a): ?>
          <div style="grid-column:3;grid-row:<?= $i++ ?>"><?= $nodo($et, $a) ?></div>
        <?php endforeach; ?>
      </div>
    </section>

    <section class="card" id="crias">
      <h2 style="font-size:18px;font-weight:600;display:flex;justify-content:space-between">Crías por pareja <span class="badge"><?= array_sum(array_map(fn($g) => count($g[2]), $grupos)) ?></span></h2>
      <?php if (!$sus_titulos): ?>
        <p class="small muted" style="margin-top:12px">Este ejemplar no tiene títulos registrados.</p>
      <?php endif; ?>
      <?php if (!$grupos): ?>
        <p class="small muted" style="margin-top:12px">Este ejemplar no tiene crías registradas.</p>
      <?php else: [$p, $otro, $cs] = $grupos[$tab]; ?>
        <nav class="tabs" style="margin:12px 0 0">
          <?php foreach ($grupos as $pid => [$gp, $go, $gc]): ?>
            <a href="canario_ficha.php?id=<?= e(urlencode($k)) ?>&amp;pareja=<?= $pid ?>#crias" class="<?= $pid === $tab ? 'activo' : '' ?>">Con <?= e($go['numero']) ?> <?= $rol_otro === 'hembra' ? '♀' : '♂' ?> · <?= count($gc) ?></a>
          <?php endforeach; ?>
        </nav>
        <p class="xs muted" style="margin-top:8px"><?= e(anillo_txt($otro)) ?><?= $otro['variedad'] ? ' · ' . e(variedad_txt($otro['variedad'])) : '' ?> · Jaula <?= e($p['jaula']) ?><?= $p['estado'] !== 'Activa' ? ' · pareja ' . e(mb_strtolower($p['estado'])) : '' ?></p>
        <table class="tabla" style="max-width:none">
          <thead><tr><th>Anillo</th><th>Sexo</th><th>Variedad</th><th>Marcas y títulos</th></tr></thead>
          <tbody>
          <?php foreach ($cs as $ck => $cr): $nt = count(titulos_de($ck)); ?>
            <tr>
              <td><a href="canario_ficha.php?id=<?= e(urlencode($ck)) ?>"><?= anillo_html($cr) ?></a></td>
              <td><?= $cr['sexo'] ? e($cr['sexo']) : '<span class="badge badge-tenue">Pendiente</span>' ?></td>
              <td><?= $cr['variedad'] ? e($cr['variedad']) : '<span class="badge badge-tenue">Pendiente</span>' ?></td>
              <td><?= $nt ? '<span class="badge badge-oscuro">Con título</span> ' : '' ?><?= ($cr['portadora'] || $cr['reservada'] || !$nt) ? marcas_html($cr) : '' ?></td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      <?php endif; ?>
    </section>
  </div>

  <div style="display:flex;flex-direction:column;gap:16px">
    <section class="card">
      <h2 style="font-size:18px;font-weight:600;display:flex;justify-content:space-between;margin-bottom:12px">Parejas en que participa <span class="badge"><?= count($sus_parejas) ?></span></h2>
      <?php if ($sus_parejas): ?>
      <table class="tabla">
        <thead><tr><th>Con</th><th>Jaula</th><th>Estado</th><th>Crías</th></tr></thead>
        <tbody>
        <?php foreach ($sus_parejas as $pid => $p): $otro = canario($p[$rol_otro]); ?>
          <tr>
            <td><a href="jaula.php?id=<?= $pid ?>"><strong><?= e($otro['numero']) ?> <?= $rol_otro === 'hembra' ? '♀' : '♂' ?></strong><span class="sub"><?= e("{$otro['club']} · {$otro['socio']} · {$otro['temp']}") ?></span></a></td>
            <td><?= e($p['jaula']) ?></td>
            <td><span class="badge <?= ['Activa' => 'badge-oscuro', 'Anulada' => 'badge-tenue'][$p['estado']] ?? '' ?>"><?= e($p['estado']) ?></span></td>
            <td><?= count(crias_de_pareja($pid)) ?></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
      <?php else: ?><p class="small muted">Aún no forma parte de ninguna pareja.</p><?php endif; ?>
    </section>

    <section class="card">
      <h2 style="font-size:18px;font-weight:600;display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">Títulos <button class="btn btn-sm" data-modal="m-titulo"><?= icono('mas', 14) ?> Registrar título</button></h2>
      <?php foreach ($sus_titulos as $t): ?>
        <div class="nodo" style="margin-bottom:8px;display:flex;gap:10px;align-items:flex-start;font-size:14px"><?= icono('trofeo') ?><div><strong><?= e($t['nombre']) ?></strong><span><?= e(fecha($t['fecha'])) ?></span></div></div>
      <?php endforeach; ?>
      <?php if (!$sus_titulos): ?><p class="small muted">Sin títulos registrados.</p><?php endif; ?>
    </section>
  </div>
</div>

<!-- Modal: Solicitar corrección -->
<?= modal_inicio('m-solicitar', 'Solicitar corrección', 'Pedir ayuda al administrador', 'Ejemplar ' . e(anillo_txt($c)), $modal_abierto === 'm-solicitar', true) ?>
<form method="POST" style="display:flex;flex-direction:column;gap:18px" novalidate>
  <input type="hidden" name="accion" value="solicitar">
  <div class="campo">
    <label for="dato">¿Qué dato debe corregirse?</label>
    <select class="input" id="dato" name="dato"><?= select_opciones(['Sexo', 'Variedad'], $post['dato'] ?? 'Sexo') ?></select>
  </div>
  <div class="campo<?= isset($err['motivo']) ? ' error' : '' ?>">
    <label for="motivo">Motivo</label>
    <textarea class="input" id="motivo" name="motivo" placeholder="Explique qué está mal y cuál es el dato correcto."><?= e($post['motivo'] ?? '') ?></textarea>
    <?= $msg('motivo') ?>
  </div>
  <div class="aviso"><?= icono('info') ?><p>La ficha mostrará «Corrección solicitada» hasta que el administrador la resuelva. Puede cancelar la solicitud cuando quiera.</p></div>
  <div class="acciones-form"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn btn-primario"><?= icono('enviar', 14) ?> Enviar solicitud</button></div>
</form>
<?= modal_fin() ?>

<!-- Modal: Activar Modo de Corrección -->
<?= modal_inicio('m-correccion', 'Modo de Corrección', 'Corregir sexo o variedad', 'Ejemplar ' . e(anillo_txt($c)), $modal_abierto === 'm-correccion', true) ?>
<form method="POST" style="display:flex;flex-direction:column;gap:18px" novalidate>
  <input type="hidden" name="accion" value="modo_correccion">
  <div class="aviso"><?= icono('info') ?><div><strong>Úselo solo para errores de ingreso</strong><p>La corrección queda registrada con el valor anterior, el nuevo, el motivo y su usuario.</p></div></div>
  <div class="campo<?= isset($err['clave']) ? ' error' : '' ?>">
    <label for="clave">Contraseña</label>
    <input class="input" type="password" id="clave" name="clave" autocomplete="current-password">
    <?= $msg('clave') ?: '<span class="ayuda-campo">Confirme que es usted.</span>' ?>
  </div>
  <div class="campo<?= isset($err['motivo_corr']) ? ' error' : '' ?>">
    <label for="motivo_corr">Motivo de la corrección</label>
    <textarea class="input" id="motivo_corr" name="motivo_corr" placeholder="Ej.: Se ingresó como macho por error; el ejemplar es hembra."><?= e($post['motivo_corr'] ?? '') ?></textarea>
    <?= $msg('motivo_corr') ?>
  </div>
  <div class="acciones-form"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn btn-primario"><?= icono('llave', 14) ?> Activar Modo de Corrección</button></div>
</form>
<?= modal_fin() ?>

<!-- Modal: Registrar título -->
<?= modal_inicio('m-titulo', 'Registrar título', 'Nuevo título', 'Ejemplar ' . e(anillo_txt($c)), $modal_abierto === 'm-titulo') ?>
<form method="POST" style="display:flex;flex-direction:column;gap:18px" novalidate>
  <input type="hidden" name="accion" value="titulo">
  <div class="campo<?= isset($err['nombre']) ? ' error' : '' ?>">
    <label for="nombre" style="display:flex;justify-content:space-between">Nombre del título <span class="small muted" id="cuenta-titulo">0 / 100</span></label>
    <input class="input" id="nombre" name="nombre" maxlength="100" data-contador="cuenta-titulo" placeholder="Ej.: Campeón Copa de la Liga 2026" value="<?= e($post['nombre'] ?? '') ?>">
    <?= $msg('nombre') ?>
  </div>
  <div class="campo<?= isset($err['fecha']) ? ' error' : '' ?>">
    <label for="fecha">Fecha</label>
    <input class="input" type="date" id="fecha" name="fecha" max="<?= hoy() ?>" value="<?= e($post['fecha'] ?? '') ?>">
    <?= $msg('fecha') ?>
  </div>
  <div class="acciones-form"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn btn-primario">Agregar título</button></div>
</form>
<?= modal_fin() ?>

<!-- Modal: Editar marcas -->
<?php if ($c['id_cria']): ?>
<?= modal_inicio('m-marcas', 'Marcas del ejemplar', 'Editar marcas', 'Ejemplar ' . e(anillo_txt($c)), $modal_abierto === 'm-marcas') ?>
<form method="POST" style="display:flex;flex-direction:column;gap:18px" novalidate>
  <input type="hidden" name="accion" value="marcas">
  <div class="campo">
    <label for="portadora">Portador de un factor genético</label>
    <select class="input" id="portadora" name="portadora"><?= select_opciones(factores_para($c['sexo']), $c['portadora'], 'No es portador') ?></select>
    <?php if ($c['sexo'] !== 'Macho' && FACTORES_LIGADOS): ?><span class="ayuda-campo">Las hembras no pueden ser portadoras de mutaciones ligadas al sexo (<?= e(implode(', ', FACTORES_LIGADOS)) ?>).</span><?php endif; ?>
  </div>
  <label class="switch"><input type="checkbox" name="reservada" value="1" <?= $c['reservada'] ? 'checked' : '' ?>><span><strong>Reservada para mi criadero</strong><br><span class="small muted">Puede quitar las marcas cuando quiera.</span></span></label>
  <div class="acciones-form"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn btn-primario">Guardar marcas</button></div>
</form>
<?= modal_fin() ?>
<?php endif; ?>

<?php include __DIR__ . '/../includes/footer.php'; ?>

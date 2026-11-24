<?php
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../includes/admin.php';
requerir_login();

// SRS-RF030/RF033: el administrador solo corrige ejemplares con una solicitud pendiente del criador
$err = [];
$post = $_POST;
$pendiente = false;
$abierta = 0;

$r = api_admin('GET', '/api/v1/admin/solicitudes-correccion?estado=pendiente');
$lista = $r['status'] === 200 ? ($r['data'] ?? []) : [];
$sin_api = $r['sin_endpoint'];

// PATCH /api/v1/admin/solicitudes-correccion/{id} con {estado, motivo}. Para aprobar, la API exige el valor correcto
// del dato solicitado (sexo M|H o id_variedad) y lo aplica al ejemplar; con parejas, anular_parejas para corregir el sexo.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['accion'] ?? '') === 'resolver') {
    $abierta = (int)($_POST['id'] ?? 0);
    $sol = current(array_filter($lista, fn($s) => (int)$s['id_solicitud'] === $abierta)) ?: null;
    $decision = $_POST['decision'] ?? '';
    if (!$sol) $err['api'] = 'La solicitud ya no está pendiente. Recargue la página.';
    if (!in_array($decision, ['aprobada', 'rechazada'], true)) $err['decision'] = 'Elija aprobar o rechazar.';
    $obs = trim($_POST['observacion'] ?? '');
    if ($decision === 'rechazada' && $obs === '') $err['observacion'] = 'Indique el motivo del rechazo.';
    $cuerpo = ['estado' => $decision, 'motivo' => $obs ?: null];
    if ($sol && $decision === 'aprobada') {
        if ($sol['dato_a_corregir'] === 'sexo') {
            $sx = ['Macho' => 'M', 'Hembra' => 'H'][$_POST['sexo'] ?? ''] ?? null;
            if (!$sx) $err['sexo'] = 'Elija el sexo correcto del ejemplar.';
            else $cuerpo['sexo'] = $sx;
            if (!empty($_POST['anular_parejas'])) $cuerpo['anular_parejas'] = true;
        } else {
            $cod = leer_variedad($_POST['variedad'] ?? '');
            if (!$cod) $err['variedad'] = 'Elija la variedad correcta de la lista del nomenclador.';
            else $cuerpo['id_variedad'] = id_variedad($cod);
        }
    }
    if (!$err) {
        $r = api_admin('PATCH', "/api/v1/admin/solicitudes-correccion/$abierta", $cuerpo);
        if ($r['sin_endpoint']) $pendiente = true;
        elseif ($r['status'] >= 200 && $r['status'] < 300) redirigir('admin_correcciones.php', 'Solicitud ' . $decision,
            $decision === 'aprobada' ? 'La corrección se aplicó al ejemplar y quedó en la auditoría.' : 'La decisión quedó registrada en la auditoría.');
        else $err['api'] = motivo_api($r);
    }
}

$pagina = 'correcciones';
$titulo = 'Correcciones solicitadas';
include __DIR__ . '/../includes/header.php';
$msg = fn($campo) => isset($err[$campo]) ? '<span class="msg-error">' . e($err[$campo]) . '</span>' : '';
?>

<?= flash() ?>

<div>
  <p class="eyebrow">Administración</p>
  <h1 class="titulo-l">Correcciones solicitadas</h1>
  <p class="bajada">Los criadores pueden pedir que se corrija el sexo o la variedad de uno de sus ejemplares. Aquí usted aprueba o rechaza cada solicitud pendiente.</p>
</div>

<?php if ($sin_api) echo aviso_pendiente_backend('No se pueden listar ni resolver las solicitudes de corrección todavía.'); ?>
<?php if ($pendiente) echo aviso_pendiente_backend('La corrección es válida, pero el backend aún no tiene el endpoint.'); ?>
<?php if (!empty($err['api'])) echo aviso_error('No se pudo guardar la corrección', $err['api']); ?>

<div class="stats" style="grid-template-columns:repeat(2,1fr)">
  <div class="stat"><span>Solicitudes pendientes</span><strong><?= count($lista) ?></strong></div>
  <div class="stat"><span>Criadores con solicitudes</span><strong><?= count(array_unique(array_column($lista, 'criador_nombre'))) ?></strong></div>
</div>

<?php if (!$lista && !$sin_api): ?>
<div class="vacio">
  <div class="circulo"><?= icono('check', 24) ?></div>
  <h3>No hay solicitudes pendientes</h3>
  <p>Cuando un criador pida una corrección desde la ficha de un ejemplar, aparecerá aquí.</p>
</div>
<?php else: ?>
<div class="panel" style="padding:0;gap:0">
  <table class="tabla" style="max-width:none">
    <thead><tr><th style="padding-left:16px">Ejemplar</th><th>Criador</th><th>Dato a corregir</th><th>Motivo</th><th>Solicitud</th><th></th></tr></thead>
    <tbody>
    <?php foreach ($lista as $s): ?>
      <tr>
        <td style="padding-left:16px"><strong><?= e($s['anillo']) ?></strong> <span class="muted">· <?= e($s['club_sigla'] ?? '') ?> · <?= e($s['numero_socio'] ?? '') ?> · <?= e($s['temporada'] ?? '') ?></span></td>
        <td><?= e($s['criador_nombre'] ?? '') ?></td>
        <td><span class="badge"><?= e(ucfirst($s['dato_a_corregir'])) ?></span></td>
        <td style="max-width:260px"><?= e($s['motivo']) ?></td>
        <td><?= e(fecha(substr($s['fecha_solicitud'], 0, 10))) ?></td>
        <td class="acciones" style="padding-right:16px">
          <button type="button" class="btn btn-sm btn-primario" data-modal="m-sol-<?= (int)$s['id_solicitud'] ?>"><?= icono('llave', 12) ?> Resolver</button>
        </td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table>
</div>
<?php endif; ?>

<?php if ($lista) echo datalist_variedades(); ?>
<?php foreach ($lista as $s): $id = (int)$s['id_solicitud']; $es_sexo = $s['dato_a_corregir'] === 'sexo'; $p = $abierta === $id ? $post : []; ?>
<?= modal_inicio("m-sol-$id", 'Solicitud de corrección', 'Resolver la solicitud del ejemplar ' . e($s['anillo']),
    'Dato a corregir: <strong>' . e($s['dato_a_corregir']) . '</strong> · Motivo del criador: «' . e($s['motivo']) . '»', $abierta === $id && $err, true) ?>
<form method="POST" style="display:flex;flex-direction:column;gap:18px" novalidate>
  <input type="hidden" name="accion" value="resolver">
  <input type="hidden" name="id" value="<?= $id ?>">
  <div class="campo<?= $abierta === $id && isset($err['decision']) ? ' error' : '' ?>">
    <label>Decisión</label>
    <div class="radios-sexo">
      <?php foreach (['aprobada' => 'Aprobar', 'rechazada' => 'Rechazar'] as $val => $txt): ?>
        <label class="radio"><input type="radio" name="decision" value="<?= $val ?>" <?= ($p['decision'] ?? '') === $val ? 'checked' : '' ?>> <?= $txt ?></label>
      <?php endforeach; ?>
    </div>
    <?= $abierta === $id ? $msg('decision') : '' ?>
  </div>
  <?php if ($es_sexo): ?>
  <div class="campo<?= $abierta === $id && isset($err['sexo']) ? ' error' : '' ?>">
    <label>Sexo correcto <span class="small muted">(solo si aprueba)</span></label>
    <div class="radios-sexo">
      <?php foreach (['Macho', 'Hembra'] as $sx): ?>
        <label class="radio"><input type="radio" name="sexo" value="<?= $sx ?>" <?= ($p['sexo'] ?? '') === $sx ? 'checked' : '' ?>> <?= $sx ?></label>
      <?php endforeach; ?>
    </div>
    <?= $abierta === $id ? $msg('sexo') : '' ?>
  </div>
  <label class="switch"><input type="checkbox" name="anular_parejas" value="1" <?= !empty($p['anular_parejas']) ? 'checked' : '' ?>><span><strong>Anular las parejas del ejemplar</strong><br><span class="small muted">Necesario si el ejemplar está en parejas. Las parejas con cruces no se pueden anular: el criador debe reasignarlas con el Modo de Corrección.</span></span></label>
  <?php else: ?>
  <div class="campo<?= $abierta === $id && isset($err['variedad']) ? ' error' : '' ?>">
    <label for="variedad-<?= $id ?>">Variedad correcta <span class="small muted">(solo si aprueba)</span></label>
    <input class="input" id="variedad-<?= $id ?>" name="variedad" list="lista-variedades" autocomplete="off" placeholder="Ej.: D.001" value="<?= e($p['variedad'] ?? '') ?>">
    <?= $abierta === $id ? $msg('variedad') : '' ?>
  </div>
  <?php endif; ?>
  <div class="campo<?= $abierta === $id && isset($err['observacion']) ? ' error' : '' ?>">
    <label for="observacion-<?= $id ?>">Observación</label>
    <textarea class="input" id="observacion-<?= $id ?>" name="observacion" maxlength="1000" placeholder="Obligatoria si rechaza la solicitud."><?= e($p['observacion'] ?? '') ?></textarea>
    <?= $abierta === $id ? $msg('observacion') : '' ?>
  </div>
  <div class="acciones-form"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn btn-primario">Guardar decisión</button></div>
</form>
<?= modal_fin() ?>
<?php endforeach; ?>

<?php include __DIR__ . '/../includes/footer.php'; ?>

<?php
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../includes/admin.php';
requerir_login();

// SRS-RF030/RF033: el administrador solo corrige ejemplares con una solicitud pendiente del criador
$err = [];
$post = $_POST;
$pendiente = false;
$abierta = 0;

// Backend (rama 31): PATCH /api/v1/admin/solicitudes-correccion/{id} con {estado: aprobada|rechazada, motivo}
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['accion'] ?? '') === 'resolver') {
    $abierta = (int)($_POST['id'] ?? 0);
    $decision = $_POST['decision'] ?? '';
    if (!in_array($decision, ['aprobada', 'rechazada'], true)) $err['decision'] = 'Elija aprobar o rechazar.';
    $obs = trim($_POST['observacion'] ?? '');
    if ($decision === 'rechazada' && $obs === '') $err['observacion'] = 'Indique el motivo del rechazo.';
    if (!$err) {
        $r = api_admin('PATCH', "/api/v1/admin/solicitudes-correccion/$abierta", ['estado' => $decision, 'motivo' => $obs ?: null]);
        if ($r['sin_endpoint']) $pendiente = true;
        elseif ($r['status'] >= 200 && $r['status'] < 300) redirigir('admin_correcciones.php', 'Solicitud ' . $decision, 'La decisión quedó registrada en la auditoría.');
        else $err['api'] = $r['message'] ?: 'La API rechazó la decisión.';
    }
}

$r = api_admin('GET', '/api/v1/admin/solicitudes-correccion?estado=pendiente');
$lista = $r['status'] === 200 ? ($r['data'] ?? []) : [];
$sin_api = $r['sin_endpoint'];

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
          <button type="button" class="btn btn-sm btn-primario" data-modal="m-corregir" data-set-id="<?= (int)$s['id_solicitud'] ?>" data-set-ejemplar="<?= e($s['anillo']) ?>"><?= icono('llave', 12) ?> Resolver</button>
        </td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table>
</div>
<?php endif; ?>

<?= modal_inicio('m-corregir', 'Solicitud de corrección', 'Resolver la solicitud del ejemplar <span data-campo="ejemplar"></span>', 'La decisión queda en la auditoría con su usuario, la fecha y el criador que la solicitó.', $abierta > 0 && $err, true) ?>
<form method="POST" style="display:flex;flex-direction:column;gap:18px" novalidate>
  <input type="hidden" name="accion" value="resolver">
  <input type="hidden" name="id" data-campo="id" value="<?= $abierta ?: '' ?>">
  <div class="campo<?= isset($err['decision']) ? ' error' : '' ?>">
    <label>Decisión</label>
    <div class="radios-sexo">
      <?php foreach (['aprobada' => 'Aprobar', 'rechazada' => 'Rechazar'] as $val => $txt): ?>
        <label class="radio"><input type="radio" name="decision" value="<?= $val ?>" <?= ($post['decision'] ?? '') === $val ? 'checked' : '' ?>> <?= $txt ?></label>
      <?php endforeach; ?>
    </div>
    <?= $msg('decision') ?>
  </div>
  <div class="campo<?= isset($err['observacion']) ? ' error' : '' ?>">
    <label for="observacion">Observación</label>
    <textarea class="input" id="observacion" name="observacion" maxlength="1000" placeholder="Obligatoria si rechaza la solicitud."><?= e($post['observacion'] ?? '') ?></textarea>
    <?= $msg('observacion') ?>
  </div>
  <div class="acciones-form"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn btn-primario">Guardar decisión</button></div>
</form>
<?= modal_fin() ?>

<?php include __DIR__ . '/../includes/footer.php'; ?>

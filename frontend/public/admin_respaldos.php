<?php
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../includes/admin.php';
requerir_login();

$estado = modo_actual();
$puede_restaurar = $estado['modo'] !== 'normal';
$err = '';
$pendiente = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['accion'] ?? '') === 'restaurar') {
    $id = (int)($_POST['id'] ?? 0);
    // SRS-RF029: solo en mantenimiento o emergencia, y con confirmación
    if (!$puede_restaurar) $err = 'La restauración solo se permite en modo de mantenimiento o de emergencia. Active uno de esos modos primero.';
    elseif (empty($_POST['confirmar'])) $err = 'Confirme que desea restaurar este respaldo.';
    else {
        $r = api_admin('POST', "/api/v1/admin/respaldos/$id/restaurar", ['confirmar' => true]);
        if ($r['sin_endpoint']) $pendiente = true;
        elseif ($r['status'] >= 200 && $r['status'] < 300) redirigir('admin_respaldos.php', 'Respaldo restaurado', 'Verifique la integridad de los datos antes de volver al modo normal.');
        else $err = $r['message'] ?: 'La API rechazó la restauración.';
    }
}

$r = api_admin('GET', '/api/v1/admin/respaldos');
$lista = $r['status'] === 200 ? ($r['data'] ?? []) : [];
$sin_api = $r['sin_endpoint'];

$pagina = 'respaldos';
$titulo = 'Respaldos';
include __DIR__ . '/../includes/header.php';
?>

<?= flash() ?>

<div>
  <p class="eyebrow">Administración</p>
  <h1 class="titulo-l">Respaldos</h1>
  <p class="bajada">El sistema respalda la base de datos al menos cada 2 días y conserva los 7 más recientes. Aquí puede consultarlos y restaurar uno.</p>
</div>

<?php if ($sin_api) echo aviso_pendiente_backend('No se puede listar ni restaurar respaldos todavía.'); ?>
<?php if ($pendiente) echo aviso_pendiente_backend('La restauración está confirmada, pero el backend aún no tiene el endpoint.'); ?>
<?php if ($err) echo aviso_error('No se pudo restaurar', $err); ?>

<?php if (!$puede_restaurar): ?>
<div class="aviso"><?= icono('info') ?><div><strong>Restauración deshabilitada en modo normal</strong><p>Para restaurar un respaldo active primero el <a class="link" href="admin_modo.php">modo de mantenimiento o de emergencia</a>.</p></div></div>
<?php endif; ?>

<div class="stats" style="grid-template-columns:repeat(3,1fr)">
  <div class="stat"><span>Respaldos conservados</span><strong><?= count($lista) ?> / 7</strong></div>
  <div class="stat"><span>Último respaldo</span><strong style="font-size:22px"><?= $lista ? e(date('d/m/Y H:i', strtotime($lista[0]['fecha_hora']))) : '—' ?></strong></div>
  <div class="stat"><span>Modo actual</span><strong style="font-size:22px"><?= e(ucfirst($estado['modo'])) ?></strong></div>
</div>

<div class="panel" style="padding:0;gap:0">
  <table class="tabla" style="max-width:none">
    <thead><tr><th style="padding-left:16px">Fecha y hora</th><th>Archivo</th><th>Origen</th><th></th></tr></thead>
    <tbody>
    <?php foreach ($lista as $b): ?>
      <tr>
        <td style="padding-left:16px"><strong><?= e(date('d/m/Y H:i', strtotime($b['fecha_hora']))) ?></strong></td>
        <td><?= e($b['archivo']) ?></td>
        <td><span class="badge"><?= empty($b['id_usuario']) ? 'Automático' : 'Manual' ?></span></td>
        <td class="acciones" style="padding-right:16px">
          <button type="button" class="btn btn-sm" data-modal="m-restaurar" data-set-id="<?= (int)$b['id_respaldo'] ?>" data-set-fecha="<?= e(date('d/m/Y H:i', strtotime($b['fecha_hora']))) ?>" <?= $puede_restaurar ? '' : 'disabled title="Solo en modo de mantenimiento o de emergencia"' ?>>Restaurar</button>
        </td>
      </tr>
    <?php endforeach; ?>
    <?php if (!$lista): ?><tr><td colspan="4" class="muted" style="padding:24px 16px"><?= $sin_api ? 'No se pudo consultar la lista de respaldos.' : 'Todavía no hay respaldos.' ?></td></tr><?php endif; ?>
    </tbody>
  </table>
</div>

<?= modal_inicio('m-restaurar', 'Restaurar respaldo', 'Respaldo del <span data-campo="fecha"></span>') ?>
<form method="POST" style="display:flex;flex-direction:column;gap:18px">
  <input type="hidden" name="accion" value="restaurar">
  <input type="hidden" name="id" data-campo="id">
  <div class="aviso aviso-warn"><?= icono('alerta') ?><div><strong>Se reemplazarán los datos actuales</strong><p>La base volverá al estado de ese respaldo; lo registrado después se perderá.</p></div></div>
  <label class="switch"><input type="checkbox" name="confirmar" value="1"><span><strong>Confirmo que quiero restaurar este respaldo</strong></span></label>
  <div class="acciones-form"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn btn-primario">Restaurar respaldo</button></div>
</form>
<?= modal_fin() ?>

<?php include __DIR__ . '/../includes/footer.php'; ?>

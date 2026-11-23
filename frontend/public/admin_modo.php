<?php
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../includes/admin.php';
requerir_login();

$err = [];
$post = $_POST;
$pendiente = false;
$modal_abierto = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $accion = $_POST['accion'] ?? '';
    if ($accion === 'activar') {
        $modo = $_POST['modo'] ?? '';
        if (!in_array($modo, ['mantenimiento', 'emergencia'], true)) { $err['modo'] = 'Elija un modo.'; }
        else {
            $r = api_admin('POST', '/api/v1/admin/modo', ['modo' => $modo]);
            if ($r['sin_endpoint']) $pendiente = true;
            elseif ($r['status'] >= 200 && $r['status'] < 300) redirigir('admin_modo.php', 'Modo ' . $modo . ' activado', 'Se cerraron las sesiones de los criadores y no podrán iniciar sesión hasta volver al modo normal.');
            else $err['api'] = $r['message'] ?: 'La API rechazó el cambio de modo.';
        }
    }
    if ($accion === 'diagnostico') {
        $d = trim($_POST['diagnostico'] ?? '');
        if ($d === '') $err['diagnostico'] = 'Escriba el diagnóstico del incidente.';
        else {
            $r = api_admin('PATCH', '/api/v1/admin/modo', ['diagnostico' => $d, 'acciones_recuperacion' => trim($_POST['acciones'] ?? '') ?: null]);
            if ($r['sin_endpoint']) $pendiente = true;
            elseif ($r['status'] >= 200 && $r['status'] < 300) redirigir('admin_modo.php', 'Evaluación registrada', 'Quedó guardada con su fecha y hora.');
            else $err['api'] = $r['message'] ?: 'La API rechazó la evaluación.';
        }
    }
    if ($accion === 'desactivar') {
        $r = api_admin('POST', '/api/v1/admin/modo/desactivar', []);
        if ($r['sin_endpoint']) $pendiente = true;
        elseif ($r['status'] >= 200 && $r['status'] < 300) redirigir('admin_modo.php', 'Modo normal restablecido', 'Los criadores pueden volver a iniciar sesión.');
        else $err['api'] = $r['message'] ?: 'La API rechazó la desactivación (una emergencia exige diagnóstico y acciones de recuperación).';
    }
    if ($err || $pendiente) $modal_abierto = '';
}

$estado = modo_actual();
$modo = $estado['modo'];
$d = $estado['detalle'] ?? [];
$desde = !empty($d['fecha_activacion']) ? strtotime($d['fecha_activacion']) : null;
$rotulos = ['normal' => 'Modo normal', 'mantenimiento' => 'Modo mantenimiento', 'emergencia' => 'Modo de emergencia'];

// SRS 2.5 / DAT-003: evaluación en 4 h y retorno a normal en 24 h desde la activación
$plazo = fn($horas) => $desde ? date('d/m/Y H:i', $desde + $horas * 3600) : '—';

$pagina = 'modo';
$titulo = 'Modo de operación';
include __DIR__ . '/../includes/header.php';
$msg = fn($campo) => isset($err[$campo]) ? '<span class="msg-error">' . e($err[$campo]) . '</span>' : '';
?>

<?= flash() ?>

<div>
  <p class="eyebrow">Administración</p>
  <h1 class="titulo-l">Modo de operación</h1>
  <p class="bajada">Suspenda el acceso de los criadores para hacer mantenimiento o atender una emergencia. Usted conserva el acceso mientras tanto.</p>
</div>

<?php if (!$estado['conocido']) echo aviso_pendiente_backend('No se puede leer ni cambiar el modo del sistema todavía; se muestra «Modo normal» solo como referencia.'); ?>
<?php if ($pendiente) echo aviso_pendiente_backend('La acción es válida, pero el backend aún no tiene el endpoint.'); ?>
<?php if (!empty($err['api'])) echo aviso_error('No se pudo completar la acción', $err['api']); ?>

<div class="stats" style="grid-template-columns:repeat(3,1fr)">
  <div class="stat"><span>Estado actual</span><strong style="font-size:22px"><?= e($rotulos[$modo]) ?></strong></div>
  <div class="stat"><span>Activado desde</span><strong style="font-size:22px"><?= $desde ? e(date('d/m/Y H:i', $desde)) : '—' ?></strong></div>
  <div class="stat"><span>Acceso de criadores</span><strong style="font-size:22px"><?= $modo === 'normal' ? 'Permitido' : 'Suspendido' ?></strong></div>
</div>

<?php if ($modo === 'normal'): ?>
<div class="dos-col-igual">
  <section class="seccion">
    <h2>Mantenimiento</h2>
    <p class="small muted">Suspensión temporal para respaldos o para cargar o actualizar el nomenclador. Los criadores no pueden registrar ni consultar mientras dure.</p>
    <div><button class="btn btn-primario" data-modal="m-mant"><?= icono('llave', 14) ?> Activar mantenimiento</button></div>
  </section>
  <section class="seccion">
    <h2>Emergencia</h2>
    <p class="small muted">Para incidentes que ponen en riesgo la información. Debe evaluar el incidente en un máximo de 4 horas y volver al modo normal en un máximo de 24 horas.</p>
    <div><button class="btn btn-primario" data-modal="m-emerg"><?= icono('alerta', 14) ?> Activar emergencia</button></div>
  </section>
</div>

<?php else: ?>
<div class="aviso aviso-warn"><?= icono('alerta') ?><div><strong><?= e($rotulos[$modo]) ?> activo</strong><p>Los criadores no pueden iniciar sesión y sus sesiones abiertas se cerraron. Vuelva al modo normal cuando termine.</p></div></div>

<?php if ($modo === 'emergencia'): ?>
<section class="seccion">
  <h2>Evaluación del incidente</h2>
  <div class="stats" style="grid-template-columns:repeat(2,1fr)">
    <div class="stat"><span>Plazo para registrar la evaluación (4 h)</span><strong style="font-size:20px"><?= e($plazo(4)) ?></strong></div>
    <div class="stat"><span>Plazo para volver al modo normal (24 h)</span><strong style="font-size:20px"><?= e($plazo(24)) ?></strong></div>
  </div>
  <form method="POST" style="display:flex;flex-direction:column;gap:16px" novalidate>
    <input type="hidden" name="accion" value="diagnostico">
    <div class="campo<?= isset($err['diagnostico']) ? ' error' : '' ?>">
      <label for="diagnostico">Diagnóstico</label>
      <textarea class="input" id="diagnostico" name="diagnostico" placeholder="Qué ocurrió y qué alcance tuvo."><?= e($post['diagnostico'] ?? $d['diagnostico'] ?? '') ?></textarea>
      <?= $msg('diagnostico') ?>
    </div>
    <div class="campo">
      <label for="acciones">Acciones de recuperación</label>
      <textarea class="input" id="acciones" name="acciones" placeholder="Qué se hizo o se hará para recuperar el servicio."><?= e($post['acciones'] ?? $d['acciones_recuperacion'] ?? '') ?></textarea>
      <span class="ayuda-campo">Sin diagnóstico ni acciones registrados no se puede volver al modo normal.</span>
    </div>
    <div class="acciones-form"><button class="btn btn-primario">Guardar evaluación</button></div>
  </form>
</section>
<?php endif; ?>

<form method="POST">
  <input type="hidden" name="accion" value="desactivar">
  <button class="btn btn-primario btn-lg"><?= icono('check', 14) ?> Volver al modo normal</button>
</form>
<?php endif; ?>

<?php foreach (['mantenimiento' => ['m-mant', 'Activar mantenimiento'], 'emergencia' => ['m-emerg', 'Activar emergencia']] as $m => [$id, $tit]): ?>
<?= modal_inicio($id, 'Modo de operación', $tit) ?>
<form method="POST" style="display:flex;flex-direction:column;gap:18px">
  <input type="hidden" name="accion" value="activar">
  <input type="hidden" name="modo" value="<?= $m ?>">
  <div class="aviso aviso-warn"><?= icono('alerta') ?><div><strong>Se cerrarán todas las sesiones de criadores</strong><p>Ningún criador podrá iniciar sesión hasta que vuelva al modo normal. Su acceso como administrador se mantiene.</p></div></div>
  <div class="acciones-form"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn btn-primario"><?= e($tit) ?></button></div>
</form>
<?= modal_fin() ?>
<?php endforeach; ?>

<?php include __DIR__ . '/../includes/footer.php'; ?>

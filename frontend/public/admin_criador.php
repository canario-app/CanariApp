<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

// Sin ?id = registrar un criador nuevo; con ?id = ver y editar
$id = (int)($_GET['id'] ?? 0);
$criador = null;
if ($id) {
    $r = api('GET', '/api/v1/admin/criadores/' . $id);
    if ($r['status'] !== 200) redirigir('admin_criadores.php', 'Criador no encontrado', 'Esa cuenta ya no existe.');
    $criador = $r['data'];
}

$v = ['nombre' => $criador['nombre'] ?? '', 'correo' => $criador['correo'] ?? '', 'numero_socio' => $criador['numero_socio'] ?? '', 'password' => ''];
$err = [];
$aviso_api = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['accion'] ?? '') === 'guardar') {
    foreach ($v as $k => $_) $v[$k] = trim($_POST[$k] ?? '');

    if ($v['nombre'] === '') $err['nombre'] = 'Ingrese el nombre del criador.';
    elseif (mb_strlen($v['nombre']) > 100) $err['nombre'] = 'Máximo 100 caracteres.';
    if (!filter_var($v['correo'], FILTER_VALIDATE_EMAIL)) $err['correo'] = 'Ingrese un correo válido.';
    elseif (mb_strlen($v['correo']) > 100) $err['correo'] = 'Máximo 100 caracteres.';
    if (!preg_match('/^\d{1,5}$/', $v['numero_socio'])) $err['numero_socio'] = 'Use solo dígitos (1 a 5).';
    if ($v['password'] === '' && !$id) $err['password'] = 'Ingrese una contraseña inicial.';
    elseif ($v['password'] !== '' && mb_strlen($v['password']) < 8) $err['password'] = 'Mínimo 8 caracteres.';

    if (!$err) {
        $cuerpo = ['nombre' => $v['nombre'], 'correo' => $v['correo'], 'numero_socio' => $v['numero_socio']];
        if ($v['password'] !== '') $cuerpo['password'] = $v['password'];
        $r = $id ? api('PUT', '/api/v1/admin/criadores/' . $id, $cuerpo) : api('POST', '/api/v1/admin/criadores', $cuerpo);

        if ($r['status'] >= 200 && $r['status'] < 300) {
            redirigir('admin_criadores.php', $id ? 'Criador actualizado' : 'Criador registrado', $v['nombre'] . ' · socio ' . $v['numero_socio']);
        }
        if ($r['status'] === 401) { header('Location: login.php?expirada=1'); exit; }
        // La API devuelve el motivo exacto (correo o socio repetido, formato, etc.)
        foreach ($r['errors'] as $campo => $m) if (isset($v[$campo])) $err[$campo] = $m;
        if (!$err) $aviso_api = $r['message'] ?: 'La API rechazó la operación.';
        elseif (stripos($r['message'], 'correo') !== false && !isset($err['correo'])) $err['correo'] = $r['message'];
    }
}
// 409: la API explica cuál de los dos datos está repetido
if ($aviso_api && stripos($aviso_api, 'correo') !== false) { $err['correo'] = $aviso_api; $aviso_api = ''; }
elseif ($aviso_api && stripos($aviso_api, 'socio') !== false) { $err['numero_socio'] = $aviso_api; $aviso_api = ''; }

$pagina = 'admin';
$titulo = $id ? 'Editar criador' : 'Registrar criador';
include __DIR__ . '/../includes/header.php';
$cls = fn($campo) => isset($err[$campo]) ? ' error' : '';
$msg = fn($campo, $ayuda = '') => isset($err[$campo]) ? '<span class="msg-error">' . e($err[$campo]) . '</span>' : ($ayuda ? '<span class="ayuda-campo">' . e($ayuda) . '</span>' : '');
?>

<p class="migas"><a href="admin_criadores.php">Criadores</a> / <?= $id ? e($criador['nombre']) : 'Registrar criador' ?></p>
<div>
  <p class="eyebrow">Administración</p>
  <h1 class="titulo-l"><?= $id ? e($criador['nombre']) : 'Registrar criador' ?></h1>
  <p class="bajada"><?= $id ? 'Consulte y edite los datos de la cuenta. La contraseña solo se cambia si escribe una nueva.' : 'Cree la cuenta con la que el criador entrará a CanariApp.' ?></p>
</div>

<div class="dos-col">
  <form method="POST" style="display:flex;flex-direction:column;gap:20px" novalidate>
    <input type="hidden" name="accion" value="guardar">
    <?php if ($aviso_api): ?>
      <div class="aviso aviso-error"><?= icono('alerta') ?><div><strong>No se pudo guardar</strong><p><?= e($aviso_api) ?></p></div></div>
    <?php elseif ($err): ?>
      <div class="aviso aviso-error"><?= icono('alerta') ?><div><strong>No se pudo guardar el criador</strong><p>Revise los campos marcados.</p></div></div>
    <?php endif; ?>

    <section class="seccion">
      <h2>1. Datos del criador</h2>
      <div class="campo<?= $cls('nombre') ?>">
        <label for="nombre">Nombre completo</label>
        <input class="input" id="nombre" name="nombre" maxlength="100" value="<?= e($v['nombre']) ?>">
        <?= $msg('nombre') ?>
      </div>
      <div class="fila-campos">
        <div class="campo<?= $cls('numero_socio') ?>" style="width:160px">
          <label for="numero_socio">N.° de socio</label>
          <input class="input" id="numero_socio" name="numero_socio" inputmode="numeric" maxlength="5" value="<?= e($v['numero_socio']) ?>">
          <?= $msg('numero_socio', '1 a 5 dígitos, único') ?>
        </div>
        <div class="campo<?= $cls('correo') ?>" style="flex:1;min-width:240px">
          <label for="correo">Correo</label>
          <input class="input" type="email" id="correo" name="correo" maxlength="100" autocomplete="off" value="<?= e($v['correo']) ?>">
          <?= $msg('correo', 'Con este correo inicia sesión') ?>
        </div>
      </div>
    </section>

    <section class="seccion">
      <h2>2. Acceso</h2>
      <div class="campo<?= $cls('password') ?>" style="max-width:360px">
        <label for="password"><?= $id ? 'Nueva contraseña (opcional)' : 'Contraseña inicial' ?></label>
        <input class="input" type="password" id="password" name="password" autocomplete="new-password">
        <?= $msg('password', $id ? 'Déjela en blanco para no cambiarla. Mínimo 8 caracteres.' : 'Mínimo 8 caracteres. El criador podrá cambiarla después.') ?>
      </div>
    </section>

    <div class="acciones-form">
      <a href="admin_criadores.php" class="btn">Cancelar</a>
      <button type="submit" class="btn btn-primario"><?= $id ? 'Guardar cambios' : 'Registrar criador' ?></button>
    </div>
  </form>

  <aside class="panel-gris">
    <?php if ($id): ?>
      <h3>Ficha de la cuenta</h3>
      <div style="display:flex;justify-content:space-between"><span class="muted">N.° de socio</span><strong><?= e($criador['numero_socio']) ?></strong></div>
      <div style="display:flex;justify-content:space-between"><span class="muted">Rol</span><strong>Criador</strong></div>
      <div style="display:flex;justify-content:space-between"><span class="muted">Alta</span><strong><?= e(fecha(substr($criador['fecha_creacion'], 0, 10))) ?></strong></div>
      <hr style="border:0;border-top:1px solid var(--gris-borde)">
      <p class="muted" style="display:flex;gap:8px"><?= icono('info') ?><span>Si cambia el correo o la contraseña, el criador deberá usar los nuevos datos la próxima vez que inicie sesión.</span></p>
    <?php else: ?>
      <h3>Antes de registrar</h3>
      <p class="muted" style="display:flex;gap:8px"><?= icono('info') ?><span>El correo y el número de socio no pueden repetirse entre criadores.</span></p>
      <p class="muted" style="display:flex;gap:8px"><?= icono('candado') ?><span>Entregue la contraseña inicial al criador por un canal seguro.</span></p>
    <?php endif; ?>
  </aside>
</div>

<?php include __DIR__ . '/../includes/footer.php'; ?>

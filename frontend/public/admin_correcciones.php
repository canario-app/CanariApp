<?php
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../includes/admin.php';
requerir_login();

// SRS-RF030/RF033: el administrador solo corrige ejemplares con una solicitud pendiente del criador
$err = [];
$post = $_POST;
$pendiente = false;
$abierta = 0;

if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['accion'] ?? '') === 'corregir') {
    $abierta = (int)($_POST['id'] ?? 0);
    $sexo = $_POST['sexo'] ?? '';
    if (!in_array($sexo, ['Macho', 'Hembra'], true)) $err['sexo'] = 'Elija el sexo.';
    $cod = leer_variedad($_POST['variedad'] ?? '');
    if (!$cod) $err['variedad'] = 'Elija una variedad de la lista del nomenclador.';
    elseif ($m = error_variedad_sexo($cod, $sexo)) $err['variedad'] = $m;
    if (!$err) {
        $r = api_admin('POST', "/api/v1/admin/correcciones/$abierta/resolver", ['sexo' => $sexo === 'Macho' ? 'M' : 'H', 'id_variedad' => id_variedad($cod)]);
        if ($r['sin_endpoint']) $pendiente = true;
        elseif ($r['status'] >= 200 && $r['status'] < 300) redirigir('admin_correcciones.php', 'Corrección guardada', 'La solicitud se cerró y quedó registrada en la auditoría.');
        else $err['api'] = $r['message'] ?: 'La API rechazó la corrección.';
    }
}

$r = api_admin('GET', '/api/v1/admin/correcciones?estado=pendiente');
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
  <p class="bajada">Los criadores pueden pedirle que corrija el sexo o la variedad de uno de sus ejemplares. Usted solo puede corregir ejemplares con una solicitud pendiente.</p>
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
          <button type="button" class="btn btn-sm btn-primario" data-modal="m-corregir" data-set-id="<?= (int)$s['id_solicitud'] ?>" data-set-ejemplar="<?= e($s['anillo']) ?>"><?= icono('llave', 12) ?> Corregir</button>
        </td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table>
</div>
<?php endif; ?>

<?= modal_inicio('m-corregir', 'Modo de Corrección', 'Corregir el ejemplar <span data-campo="ejemplar"></span>', 'Cada corrección queda en la auditoría con el valor anterior, el nuevo, el motivo, su usuario y el criador que la solicitó.', $abierta > 0 && $err, true) ?>
<form method="POST" style="display:flex;flex-direction:column;gap:18px" novalidate>
  <input type="hidden" name="accion" value="corregir">
  <input type="hidden" name="id" data-campo="id" value="<?= $abierta ?: '' ?>">
  <div class="campo<?= isset($err['sexo']) ? ' error' : '' ?>">
    <label>Sexo</label>
    <div class="radios-sexo">
      <?php foreach (['Macho', 'Hembra'] as $s): ?>
        <label class="radio"><input type="radio" name="sexo" value="<?= $s ?>" <?= ($post['sexo'] ?? '') === $s ? 'checked' : '' ?>> <?= $s ?></label>
      <?php endforeach; ?>
    </div>
    <?= $msg('sexo') ?>
  </div>
  <div class="campo<?= isset($err['variedad']) ? ' error' : '' ?>">
    <label for="variedad">Variedad del nomenclador</label>
    <input class="input" id="variedad" name="variedad" list="lista-variedades" autocomplete="off" placeholder="Ej.: CC033" value="<?= e($post['variedad'] ?? '') ?>">
    <?= datalist_variedades() ?>
    <?= $msg('variedad') ?: '<span class="ayuda-campo">Si la variedad indica sexo, debe coincidir con el del ejemplar.</span>' ?>
  </div>
  <div class="acciones-form"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn btn-primario">Guardar corrección</button></div>
</form>
<?= modal_fin() ?>

<?php include __DIR__ . '/../includes/footer.php'; ?>

<?php
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../includes/admin.php';
requerir_login();

$clubes = api_lista('/api/v1/wiki/clubes');
$siglas = array_column($clubes, 'sigla');
$sigla = '';
$err = '';
$pendiente = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $sigla = trim($_POST['sigla'] ?? '');
    // SRS-RF011: 2 a 6 letras mayúsculas, sin duplicados
    if (!preg_match('/^[A-Z]{2,6}$/', $sigla)) $err = 'Use entre 2 y 6 letras mayúsculas, sin números ni espacios.';
    elseif (in_array($sigla, $siglas, true)) $err = "La sigla $sigla ya existe.";
    else {
        $r = api_admin('POST', '/api/v1/admin/clubes', ['sigla' => $sigla]);
        if ($r['sin_endpoint']) $pendiente = true;
        elseif ($r['status'] >= 200 && $r['status'] < 300) redirigir('admin_clubes.php', 'Club registrado', "La sigla $sigla ya está disponible para los anillos.");
        else $err = $r['errors']['sigla'] ?? ($r['message'] ?: 'La API rechazó la sigla.');
    }
}

$pagina = 'clubes';
$titulo = 'Siglas de club';
include __DIR__ . '/../includes/header.php';
?>

<?= flash() ?>

<div>
  <p class="eyebrow">Administración</p>
  <h1 class="titulo-l">Siglas de club</h1>
  <p class="bajada">Las siglas disponibles aparecen en el anillo de cada ejemplar. Registre una nueva cuando un club se incorpore.</p>
</div>

<div class="dos-col">
  <div class="panel" style="padding:0;gap:0">
    <table class="tabla" style="max-width:none">
      <thead><tr><th style="padding-left:16px">Sigla</th><th>Estado</th></tr></thead>
      <tbody>
      <?php foreach ($clubes as $c): ?>
        <tr><td style="padding-left:16px"><strong><?= e($c['sigla']) ?></strong></td><td><span class="badge">Disponible</span></td></tr>
      <?php endforeach; ?>
      <?php if (!$clubes): ?><tr><td colspan="2" class="muted" style="padding:24px 16px">Todavía no hay siglas registradas.</td></tr><?php endif; ?>
      </tbody>
    </table>
    <p class="xs muted" style="padding:16px"><?= count($clubes) ?> sigla<?= count($clubes) === 1 ? '' : 's' ?> disponible<?= count($clubes) === 1 ? '' : 's' ?></p>
  </div>

  <form method="POST" class="panel-gris" novalidate>
    <h3>Registrar sigla</h3>
    <?php if ($pendiente) echo aviso_pendiente_backend('La sigla es válida, pero el backend aún no tiene el endpoint para registrarla.'); ?>
    <div class="campo<?= $err ? ' error' : '' ?>">
      <label for="sigla">Sigla del club</label>
      <input class="input" id="sigla" name="sigla" maxlength="6" autocomplete="off" placeholder="Ej.: SOCH" value="<?= e($sigla) ?>">
      <?= $err ? '<span class="msg-error">' . e($err) . '</span>' : '<span class="ayuda-campo">2 a 6 letras mayúsculas. No puede repetirse.</span>' ?>
    </div>
    <button class="btn btn-primario"><?= icono('mas', 14) ?> Registrar sigla</button>
  </form>
</div>

<?php include __DIR__ . '/../includes/footer.php'; ?>

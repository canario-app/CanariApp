<?php
require_once __DIR__ . '/../includes/config.php';

if (!empty($_SESSION['usuario'])) {
    header('Location: ' . (($_SESSION['usuario']['rol'] ?? '') === 'administrador' ? 'admin_criadores.php' : 'inicio.php'));
    exit;
}

// Estado de intentos (en producción conviene guardarlo en la BD por correo/IP, no en la sesión)
$intentos = $_SESSION['intentos'] ?? 0;
$bloqueo_hasta = $_SESSION['bloqueo_hasta'] ?? 0;
if ($bloqueo_hasta && time() >= $bloqueo_hasta) {
    $intentos = 0; $bloqueo_hasta = 0;
    unset($_SESSION['intentos'], $_SESSION['bloqueo_hasta']);
}
$bloqueado = $bloqueo_hasta > time();

$correo = $_GET['correo'] ?? '';
$aviso = null;          // [tipo, titulo, texto]
$err_correo = $err_clave = '';

if (isset($_GET['mantenimiento'])) {
    $aviso = ['aviso-warn', 'Sistema en mantenimiento', 'El administrador suspendió temporalmente el acceso de los criadores. Intente nuevamente más tarde.'];
}
if (isset($_GET['expirada'])) {
    $aviso = ['', 'Su sesión se cerró', 'Por seguridad, cerramos su sesión tras ' . MINUTOS_INACTIVIDAD . ' minutos sin actividad. Inicie sesión nuevamente para continuar.'];
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && !$bloqueado) {
    $correo = trim($_POST['correo'] ?? '');
    $clave  = $_POST['clave'] ?? '';
    $r = iniciar_sesion_api($correo, $clave);
    $u = $r['status'] === 200 ? $r['data']['user'] : null;
    // SRS-RF028: en mantenimiento o emergencia el criador no puede ingresar (la API de crianza responde 503)
    if ($u && $u['rol'] === 'criador') {
        $_SESSION['token'] = $r['data']['token'];
        $modo = api('GET', '/api/v1/criador/perfil');
        unset($_SESSION['token']);
        if ($modo['status'] === 503) {
            header('Location: login.php?mantenimiento=1');
            exit;
        }
    }

    if ($u && in_array($u['rol'], ['criador', 'administrador'], true)) {
        session_regenerate_id(true);
        unset($_SESSION['intentos'], $_SESSION['bloqueo_hasta'], $_SESSION['catalogo']);
        $_SESSION['token'] = $r['data']['token'];
        $_SESSION['usuario'] = ['id' => $u['id_usuario'], 'nombre' => $u['nombre'], 'correo' => mb_strtolower($u['correo']), 'rol' => $u['rol']];
        $_SESSION['ultima_actividad'] = time();
        header('Location: ' . ($u['rol'] === 'administrador' ? 'admin_criadores.php' : 'inicio.php'));
        exit;
    }

    $intentos = $_SESSION['intentos'] = $intentos + 1;
    if ($intentos >= MAX_INTENTOS) {
        $bloqueo_hasta = $_SESSION['bloqueo_hasta'] = time() + MINUTOS_BLOQUEO * 60;
        $bloqueado = true;
    } elseif ($r['status'] === 0) {
        $aviso = ['aviso-error', 'Sin conexión con el servidor', $r['message']];
    } else {
        $quedan = MAX_INTENTOS - $intentos;
        $aviso = ['aviso-error', 'Credenciales incorrectas', 'Revise su correo y su contraseña e intente nuevamente.'];
        $err_clave = "Correo o contraseña incorrectos. Le quedan $quedan intento" . ($quedan > 1 ? 's' : '') . '.';
    }
}

if ($bloqueado) {
    $aviso = ['aviso-warn', 'Cuenta bloqueada temporalmente', 'Superó los ' . MAX_INTENTOS . ' intentos permitidos. Podrá intentarlo de nuevo en:'];
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Iniciar sesión · CanariApp</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="css/styles.css">
  <link rel="stylesheet" href="css/responsive.css">
</head>
<body>
  <div class="login-bg">
    <form class="login" method="POST" action="login.php" novalidate>
      <div>
        <h1>Iniciar sesión</h1>
        <p class="desc">Ingrese con la cuenta que le entregó el administrador.</p>
      </div>

      <?php if ($aviso): ?>
        <div class="aviso <?= $aviso[0] ?>">
          <?= icono($bloqueado ? 'candado' : ($aviso[0] ? 'alerta' : 'info')) ?>
          <div>
            <strong><?= e($aviso[1]) ?></strong>
            <p><?= e($aviso[2]) ?></p>
            <?php if ($bloqueado): ?><div class="contador" id="contador" data-fin="<?= $bloqueo_hasta ?>"></div><?php endif; ?>
          </div>
        </div>
      <?php endif; ?>

      <div class="campo<?= $err_correo ? ' error' : '' ?>">
        <label for="correo">Correo electrónico</label>
        <input class="input" type="email" id="correo" name="correo" placeholder="nombre@correo.cl" value="<?= e($correo) ?>" required <?= $bloqueado ? 'disabled' : '' ?>>
        <?php if ($err_correo): ?><span class="msg-error"><?= e($err_correo) ?></span><?php endif; ?>
      </div>

      <div class="campo<?= $err_clave ? ' error' : '' ?>">
        <label for="clave">Contraseña</label>
        <div class="input-icono der">
          <input class="input" type="password" id="clave" name="clave" placeholder="Mínimo 8 caracteres" minlength="8" required <?= $bloqueado ? 'disabled' : '' ?>>
          <img src="img/ojo.svg" alt="Mostrar contraseña" id="verClave">
        </div>
        <?php if ($err_clave): ?><span class="msg-error"><?= e($err_clave) ?></span><?php endif; ?>
      </div>

      <button type="submit" class="btn btn-primario" id="btnIngresar" disabled>Ingresar</button>

      <hr>

      <p class="ayuda-login">¿Problemas para ingresar?<br><a href="contacto.php">Contacte al administrador</a></p>
    </form>
  </div>

  <script>
    // Habilita "Ingresar" solo con correo válido y contraseña de 8+ caracteres (igual que el Figma)
    const correo = document.getElementById('correo');
    const clave = document.getElementById('clave');
    const btn = document.getElementById('btnIngresar');
    const validar = () => btn.disabled = correo.disabled || !(correo.checkValidity() && clave.value.length >= 8);
    correo.addEventListener('input', validar);
    clave.addEventListener('input', validar);
    validar();

    document.getElementById('verClave').addEventListener('click', () => {
      clave.type = clave.type === 'password' ? 'text' : 'password';
    });

    // Cuenta regresiva del bloqueo de 15 minutos
    const cont = document.getElementById('contador');
    if (cont) {
      const fin = cont.dataset.fin * 1000;
      const tick = () => {
        const s = Math.max(0, Math.round((fin - Date.now()) / 1000));
        cont.textContent = String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0');
        if (s === 0) location.href = 'login.php';
      };
      tick(); setInterval(tick, 1000);
    }
  </script>
</body>
</html>

<?php
require_once __DIR__ . '/../includes/config.php';
// Datos de contacto configurables por variables de entorno (Docker/Vercel): CONTACTO_NOMBRE, CONTACTO_CORREO, CONTACTO_TELEFONO
$admin = [
    'nombre'   => getenv('CONTACTO_NOMBRE') ?: 'Administrador de CanariApp',
    'correo'   => getenv('CONTACTO_CORREO') ?: 'admin@canariapp.cl',
    'telefono' => getenv('CONTACTO_TELEFONO') ?: '',
];
$volver = empty($_SESSION['usuario']) ? ['login.php', 'Volver a iniciar sesión'] : ['inicio.php', 'Volver al inicio'];
?>
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Contactar al administrador · CanariApp</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="css/styles.css">
  <link rel="stylesheet" href="css/responsive.css">
</head>
<body>
  <div class="login-bg">
    <div class="login">
      <div>
        <h1>Contacte al administrador</h1>
        <p class="desc">Las cuentas de CanariApp las crea el administrador. Escríbale para pedir una cuenta o si tiene problemas para ingresar.</p>
      </div>
      <div class="aviso datos-contacto" style="flex-direction:column;gap:14px">
        <div><span>Administrador</span><?= e($admin['nombre']) ?></div>
        <div><span>Correo</span><?= e($admin['correo']) ?></div>
        <?php if ($admin['telefono'] !== ''): ?><div><span>Teléfono</span><?= e($admin['telefono']) ?></div><?php endif; ?>
      </div>
      <p class="small muted" style="display:flex;gap:8px"><?= icono('info') ?> Indique su nombre y su número de socio para que pueda ubicarlo.</p>
      <a href="<?= $volver[0] ?>" class="btn"><?= icono('atras', 14) ?> <?= $volver[1] ?></a>
    </div>
  </div>
</body>
</html>

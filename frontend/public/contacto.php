<?php
require_once __DIR__ . '/../includes/config.php';
// TODO: reemplazar por los datos reales del administrador (o leerlos de la BD)
$admin = ['nombre' => '[Nombre del administrador]', 'correo' => '[correo del administrador]', 'telefono' => '[teléfono del administrador]'];
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
        <div><span>Teléfono</span><?= e($admin['telefono']) ?></div>
      </div>
      <p class="small muted" style="display:flex;gap:8px"><?= icono('info') ?> Indique su nombre y su número de socio para que pueda ubicarlo.</p>
      <a href="<?= $volver[0] ?>" class="btn"><?= icono('atras', 14) ?> <?= $volver[1] ?></a>
    </div>
  </div>
</body>
</html>

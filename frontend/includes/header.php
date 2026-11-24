<?php
// Uso: definir $pagina (inicio|canarios|parejas|crias|titulos|simulador) y $titulo antes del include
require_once __DIR__ . '/config.php';
requerir_login();
$criador = $_SESSION['usuario']['nombre'] ?? '[Nombre del criador]';
$inicial = mb_strtoupper(mb_substr($criador, 0, 1));
$esAdmin = ($_SESSION['usuario']['rol'] ?? '') === 'administrador';
?>
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><?= e($titulo ?? 'CanariApp') ?> · CanariApp</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="css/styles.css">
  <link rel="stylesheet" href="css/responsive.css">
  <link rel="stylesheet" href="css/tema.css">
  <meta name="theme-color" content="#386641">
  <?php include __DIR__ . '/tema_inicial.php'; ?>
</head>
<body>
  <header class="topbar">
    <button type="button" class="menu-btn" aria-label="Menú" aria-expanded="false"
      onclick="this.setAttribute('aria-expanded', document.body.classList.toggle('menu-abierto'))">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16"/></svg>
    </button>
    <div class="marca">
      <div class="marca-logo"><img src="img/logo.svg" width="24" height="24" alt=""></div>
      <div>
        <div class="marca-nombre">CanariApp</div>
        <div class="marca-criador"><?= e($criador) ?><?php if ($esAdmin): ?><span class="marca-rol"> · Administrador</span><?php endif; ?></div>
      </div>
    </div>
    <div class="usuario">
      <?php include __DIR__ . '/tema_selector.php'; ?>
      <div class="avatar"><?= e($inicial) ?></div>
      <a href="logout.php" class="btn">Cerrar sesión</a>
    </div>
  </header>

  <div class="app">
    <?php include __DIR__ . '/sidebar.php'; ?>
    <main class="contenido">

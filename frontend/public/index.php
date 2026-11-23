<?php
require_once __DIR__ . '/../includes/config.php';
header('Location: ' . (empty($_SESSION['usuario']) ? 'login.php' : (($_SESSION['usuario']['rol'] ?? '') === 'administrador' ? 'admin_criadores.php' : 'inicio.php')));
exit;

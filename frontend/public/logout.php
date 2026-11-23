<?php
require_once __DIR__ . '/../includes/config.php';
if (!empty($_SESSION['token'])) api('POST', '/api/v1/logout'); // revoca el token en la API
session_destroy();
header('Location: login.php');
exit;

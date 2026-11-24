<?php // Aplica el tema guardado antes de pintar la página, para que no parpadee en claro al navegar ?>
<script>try { document.documentElement.dataset.tema = localStorage.getItem('tema') === 'oscuro' ? 'oscuro' : 'claro'; } catch (e) {}</script>

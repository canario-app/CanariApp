    </main>
  </div>
  <script src="js/app.js"></script>
  <?php if (!empty($scripts)) foreach ($scripts as $s): ?>
    <script src="<?= e($s) ?>"></script>
  <?php endforeach; ?>
</body>
</html>

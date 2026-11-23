<?php
require_once __DIR__ . '/../includes/config.php';
requerir_login();

// Catálogo de mutaciones y ejemplares del criadero, desde la API
$mutaciones = api_lista('/api/v1/wiki/mutaciones');
$machos = array_filter(canarios(), fn($c) => $c['sexo'] === 'Macho');
$hembras = array_filter(canarios(), fn($c) => $c['sexo'] === 'Hembra');
const GENOTIPOS_API = ['visual' => 'visual', 'portador' => 'portador', 'sin' => 'sin factor'];

$v = ['mutacion' => '', 'macho' => '', 'hembra' => '', 'gen_macho' => '', 'gen_hembra' => ''];
$err = [];
$sim = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    foreach ($v as $k => $_) $v[$k] = trim($_POST[$k] ?? '');
    $mut = null;
    foreach ($mutaciones as $m) if ((string)$m['id_mutacion'] === $v['mutacion']) $mut = $m;
    if (!$mut) $err['mutacion'] = 'Elija una mutación del catálogo.';
    if (!isset($machos[$v['macho']])) $err['macho'] = 'Elija un macho de su criadero.';
    if (!isset($hembras[$v['hembra']])) $err['hembra'] = 'Elija una hembra de su criadero.';
    if (!isset(GENOTIPOS_API[$v['gen_macho']])) $err['gen_macho'] = 'Seleccione el genotipo del macho.';
    if (!isset(GENOTIPOS_API[$v['gen_hembra']])) $err['gen_hembra'] = 'Seleccione el genotipo de la hembra.';
    if ($mut && str_starts_with($mut['tipo_herencia'], 'ligada') && $v['gen_hembra'] === 'portador') $err['gen_hembra'] = 'En herencia ligada al sexo la hembra no puede ser portadora.';

    if (!$err) {
        // Guarda la simulación en el historial del criadero y devuelve las probabilidades calculadas por el servidor
        $r = api('POST', '/api/v1/simulaciones', [
            'id_macho' => $machos[$v['macho']]['id'], 'id_hembra' => $hembras[$v['hembra']]['id'], 'id_mutacion' => (int)$v['mutacion'],
            'genotipo_macho' => GENOTIPOS_API[$v['gen_macho']], 'genotipo_hembra' => GENOTIPOS_API[$v['gen_hembra']],
        ]);
        if ($r['status'] === 201) $sim = $r['data'];
        else $err['api'] = trim(($r['message'] ?: 'La API rechazó la simulación.') . ' ' . implode(' ', array_map('strval', $r['errors'])));
    }
}

$hist = api('GET', '/api/v1/simulaciones');
$historial = $hist['status'] === 200 ? array_slice($hist['data'] ?? [], 0, 5) : [];

$pagina = 'simulador';
$titulo = 'Simulador';
$scripts = ['js/simulador.js'];
include __DIR__ . '/../includes/header.php';
$cls = fn($c) => isset($err[$c]) ? ' error' : '';
$msg = fn($c) => isset($err[$c]) ? '<span class="msg-error">' . e($err[$c]) . '</span>' : '';
$rot = ['visual' => 'Visual', 'portador' => 'Portador', 'sin factor' => 'Sin factor'];

// Probabilidades del resultado agrupadas por sexo de la cría (null = autosómica, igual para ambos sexos)
$grupos = [];
if ($sim) foreach ($sim['resultados'] as $x) $grupos[$x['sexo_cria'] ?? '-'][$x['genotipo_resultado']] = (float)$x['probabilidad'];
$ligada = $sim && str_starts_with($sim['tipo_herencia'], 'ligada');
?>

<div>
  <p class="eyebrow">Simulador genético</p>
  <h1 class="titulo-l">Simulador de cruce</h1>
  <p class="bajada">Calcule la proporción esperada de crías de una pareja para una mutación, según la Ley de Mendel. Se simula una mutación a la vez y cada simulación queda en su historial.</p>
</div>

<?php if (!empty($err['api'])): ?><div class="aviso aviso-error"><?= icono('alerta') ?><div><strong>No se pudo ejecutar la simulación</strong><p><?= e($err['api']) ?></p></div></div><?php endif; ?>

<form class="card" id="formSim" method="POST" style="padding:0" novalidate>
  <div class="sim-form">
    <div>
      <h2 style="font-size:20px;font-weight:600">Datos del cruce</h2>
      <span class="chip" id="herencia" style="display:inline-block;margin-top:16px">Elija una mutación</span>
    </div>
    <div class="campo<?= $cls('mutacion') ?>">
      <label for="mutacion">Mutación del catálogo</label>
      <select class="input" id="mutacion" name="mutacion" required>
        <option value="" disabled <?= $v['mutacion'] === '' ? 'selected' : '' ?>>Elegir</option>
        <?php foreach ($mutaciones as $m): ?>
          <option value="<?= (int)$m['id_mutacion'] ?>" data-herencia="<?= e(ucfirst($m['tipo_herencia'])) ?>" data-ligada="<?= str_starts_with($m['tipo_herencia'], 'ligada') ? 1 : 0 ?>" <?= (string)$m['id_mutacion'] === $v['mutacion'] ? 'selected' : '' ?>><?= e($m['nombre']) ?></option>
        <?php endforeach; ?>
      </select>
      <?= $msg('mutacion') ?>
    </div>

    <div class="sep"></div>

    <div>
      <div class="campo<?= $cls('macho') ?>">
        <label for="macho">Macho</label>
        <select class="input" id="macho" name="macho" required>
          <option value="" disabled <?= $v['macho'] === '' ? 'selected' : '' ?>>Elegir</option>
          <?php foreach ($machos as $k => $c): ?><option value="<?= e($k) ?>" <?= $k === $v['macho'] ? 'selected' : '' ?>><?= e(anillo_txt($c)) ?></option><?php endforeach; ?>
        </select>
        <?= $msg('macho') ?>
      </div>
      <p class="small muted" style="margin-top:16px">Genotipo del macho</p>
      <div class="radios">
        <?php foreach (['visual' => 'Visual', 'portador' => 'Portador', 'sin' => 'Sin factor'] as $val => $txt): ?>
          <label class="radio"><input type="radio" name="gen_macho" value="<?= $val ?>" <?= $v['gen_macho'] === $val ? 'checked' : '' ?>> <?= $txt ?></label>
        <?php endforeach; ?>
      </div>
      <?= $msg('gen_macho') ?>
    </div>
    <div>
      <div class="campo<?= $cls('hembra') ?>">
        <label for="hembra">Hembra</label>
        <select class="input" id="hembra" name="hembra" required>
          <option value="" disabled <?= $v['hembra'] === '' ? 'selected' : '' ?>>Elegir</option>
          <?php foreach ($hembras as $k => $c): ?><option value="<?= e($k) ?>" <?= $k === $v['hembra'] ? 'selected' : '' ?>><?= e(anillo_txt($c)) ?></option><?php endforeach; ?>
        </select>
        <?= $msg('hembra') ?>
      </div>
      <p class="small muted" style="margin-top:16px">Genotipo de la hembra</p>
      <div class="radios">
        <?php foreach (['visual' => 'Visual', 'portador' => 'Portador', 'sin' => 'Sin factor'] as $val => $txt): ?>
          <label class="radio"><input type="radio" name="gen_hembra" value="<?= $val ?>" <?= $v['gen_hembra'] === $val ? 'checked' : '' ?>> <?= $txt ?></label>
        <?php endforeach; ?>
      </div>
      <?= $msg('gen_hembra') ?>
    </div>

    <div class="sep"></div>
  </div>
  <div class="sim-botones">
    <a href="simulador.php" class="btn">Limpiar</a>
    <button type="submit" class="btn btn-primario">Simular cruce</button>
  </div>
</form>

<div class="resultados">
  <div class="card" style="display:flex;flex-direction:column;gap:18px">
    <div>
      <p class="eyebrow">Resultado esperado</p>
      <h3 style="font-size:20px;font-weight:600;margin-top:4px" id="resTitulo"><?= $sim ? e($sim['mutacion_nombre']) . ': macho ' . e($sim['genotipo_macho']) . ' × hembra ' . e($sim['genotipo_hembra']) : 'macho × hembra' ?></h3>
      <p class="small muted"><?= $ligada ? 'Herencia ligada al sexo: el resultado es distinto en machos y hembras' : 'Igual para machos y hembras' ?></p>
    </div>
    <?php
    $bloques = $ligada ? ['M' => 'Machos', 'H' => 'Hembras'] : ['-' => null];
    foreach ($bloques as $sx => $titBloque):
      if ($titBloque) echo '<p class="small" style="font-weight:600">' . e($titBloque) . '</p>';
      foreach ($rot as $g => $txt):
        $p = isset($grupos[$sx][$g]) ? round($grupos[$sx][$g] * 100) : 0; ?>
    <div class="barra"><div class="fila-barra"><span><?= $txt ?></span><span><?= $p ?> %</span></div><div class="track"><div class="fill" style="width:<?= $p ?>%"></div></div></div>
    <?php endforeach; endforeach; ?>
    <hr style="border:0;border-top:1px solid var(--gris-linea)">
    <div style="display:flex;justify-content:space-between" class="small"><span class="muted">Total</span><strong><?= $sim ? '100 %' : '0 %' ?></strong></div>
    <p class="muted" style="font-size:13px">Es una proporción esperada, no garantizada: cada nidada puede variar.<?= $sim ? ' Simulación guardada en su historial.' : '' ?></p>
  </div>

  <div class="card" style="display:flex;flex-direction:column;justify-content:space-between;gap:16px;padding:24px">
    <h3 style="font-size:16px;font-weight:600">Cuadro de Punnett</h3>
    <div class="punnett" id="punnett"></div>
    <p class="muted" style="font-size:13px;line-height:19.5px" id="notaPunnett">Columnas: lo que aporta el macho. Filas: lo que aporta la hembra. «o» es la copia con la mutación y «+» la copia normal.</p>
  </div>
</div>

<?php if ($historial): ?>
<div class="panel" style="padding:0;gap:0">
  <p class="eyebrow" style="padding:16px 16px 0">Últimas simulaciones</p>
  <table class="tabla" style="max-width:none">
    <thead><tr><th style="padding-left:16px">Fecha</th><th>Mutación</th><th>Macho</th><th>Hembra</th></tr></thead>
    <tbody>
    <?php foreach ($historial as $h): ?>
      <tr>
        <td style="padding-left:16px"><?= e(fecha(substr($h['fecha'], 0, 10))) ?></td>
        <td><strong><?= e($h['mutacion_nombre']) ?></strong></td>
        <td><?= e($h['anillo_macho']) ?> <span class="muted">· <?= e($h['genotipo_macho']) ?></span></td>
        <td><?= e($h['anillo_hembra']) ?> <span class="muted">· <?= e($h['genotipo_hembra']) ?></span></td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table>
</div>
<?php endif; ?>

<script>window.SIM = <?= json_encode($sim ? ['macho' => $v['gen_macho'], 'hembra' => $v['gen_hembra'], 'ligada' => $ligada] : null) ?>;</script>
<?php include __DIR__ . '/../includes/footer.php'; ?>

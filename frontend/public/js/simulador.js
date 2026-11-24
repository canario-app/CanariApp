// Simulador de cruce — el servidor calcula y guarda la simulación; aquí solo se dibuja el cuadro de Punnett
// "o" = copia con la mutación, "+" = copia normal
const GENOTIPOS = { visual: ['o', 'o'], portador: ['+', 'o'], sin: ['+', '+'] };
const $ = id => document.getElementById(id);

function fenotipo(a, b) {
  if (a === 'o' && b === 'o') return 'Visual';
  if (a === 'o' || b === 'o') return 'Portador';
  return 'Sin factor';
}

function dibujar(macho, hembra) {
  const m = macho ? GENOTIPOS[macho] : ['o', '+'];
  const h = hembra ? GENOTIPOS[hembra] : ['o', 'o'];
  let html = '<div></div>' + m.map(x => `<div class="cab">${x}</div>`).join('');
  h.forEach(fila => {
    html += `<div class="cab">${fila}</div>`;
    m.forEach(col => {
      const f = fenotipo(col, fila);
      html += `<div class="celda ${f === 'Visual' ? 'visual' : ''}">${[col, fila].sort().join('/')}<small>${f}</small></div>`;
    });
  });
  $('punnett').innerHTML = html;
}

const actualizarHerencia = () => {
  const o = $('mutacion').selectedOptions[0];
  if (!o || !o.dataset.herencia) return;
  $('herencia').textContent = o.dataset.herencia;
  // En herencia ligada al sexo la hembra no puede ser portadora (DAT-006)
  const hp = document.querySelector('input[name="gen_hembra"][value="portador"]');
  // se quita la opción (no solo se desactiva); vuelve a aparecer con las mutaciones autosómicas
  hp.disabled = o.dataset.ligada === '1';
  hp.closest('label').style.display = hp.disabled ? 'none' : ''; // .radio define display, así que [hidden] no basta
  if (hp.disabled && hp.checked) hp.checked = false;
};
$('mutacion').addEventListener('change', actualizarHerencia);
actualizarHerencia();

// El cuadro de Punnett solo aplica a la herencia autosómica
if (window.SIM && !window.SIM.ligada) dibujar(window.SIM.macho, window.SIM.hembra);
else if (window.SIM && window.SIM.ligada) {
  $('punnett').innerHTML = '';
  $('notaPunnett').textContent = 'El cuadro de Punnett se muestra solo para herencia autosómica. En herencia ligada al sexo, consulte las proporciones por sexo de la cría.';
} else dibujar();

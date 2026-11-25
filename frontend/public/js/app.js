// Comportamiento común: modales y contadores de caracteres
document.addEventListener('click', e => {
  const abrir = e.target.closest('[data-modal]');
  if (abrir) {
    e.preventDefault();
    const m = document.getElementById(abrir.dataset.modal);
    if (!m) return;
    // pasa datos del botón a los campos del modal: data-set-campo="valor"
    Object.entries(abrir.dataset).forEach(([k, v]) => {
      if (!k.startsWith('set')) return;
      const nombre = k.slice(3).toLowerCase();
      m.querySelectorAll(`[data-campo="${nombre}"]`).forEach(el => {
        if ('value' in el && el.tagName !== 'DIV' && el.tagName !== 'SPAN') el.value = v; else el.textContent = v;
      });
    });
    m.classList.add('abierto');
    m.querySelector('input:not([type=hidden]),textarea,select')?.focus();
  }
  if (e.target.closest('[data-cerrar]') || e.target.classList.contains('modal')) {
    e.target.closest('.modal')?.classList.remove('abierto');
  }
});
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') document.querySelectorAll('.modal.abierto').forEach(m => m.classList.remove('abierto'));
});
document.querySelectorAll('[data-contador]').forEach(input => {
  const out = document.getElementById(input.dataset.contador);
  const upd = () => out.textContent = `${input.value.length} / ${input.maxLength}`;
  input.addEventListener('input', upd); upd();
});

// Selector de tema (Sol / Luna): cambia al instante y guarda la preferencia en localStorage
const aplicarTema = tema => {
  document.documentElement.dataset.tema = tema;
  try { localStorage.setItem('tema', tema); } catch (e) {}
  document.querySelectorAll('[data-tema-btn]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.temaBtn === tema)));
};
const temaMovil = window.matchMedia('(max-width: 760px)');
document.querySelectorAll('[data-tema-btn]').forEach(b => {
  b.addEventListener('click', () => {
    const tema = b.dataset.temaBtn;
    const apagarOscuro = temaMovil.matches && tema === 'oscuro' && document.documentElement.dataset.tema === 'oscuro';
    aplicarTema(apagarOscuro ? 'claro' : tema);
  });
});
aplicarTema(document.documentElement.dataset.tema === 'oscuro' ? 'oscuro' : 'claro');

// Buscador de variedades del nomenclador: reemplaza la lista nativa (<datalist>), que en
// celulares y algunos navegadores casi no se ve. Muestra la lista filtrada al escribir el
// código o parte del nombre (sin importar tildes ni mayúsculas) y se maneja con flechas y Enter.
(() => {
  const dl = document.getElementById('lista-variedades');
  if (!dl) return;
  const norm = s => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const opciones = [...dl.options].map(o => ({ txt: o.value, n: norm(o.value) }));
  const MAX = 60;
  const caja = document.createElement('div');
  caja.className = 'buscador-variedades';
  caja.setAttribute('role', 'listbox');
  caja.hidden = true;
  document.body.appendChild(caja);
  let input = null, marcada = -1;

  const esc = s => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const ubicar = () => {
    const r = input.getBoundingClientRect();
    caja.style.left = r.left + 'px';
    // si no cabe abajo y hay más espacio arriba, se abre hacia arriba
    const abajo = window.innerHeight - r.bottom, arriba = r.top;
    const alto = Math.min(280, Math.max(abajo, arriba) - 12);
    caja.style.maxHeight = alto + 'px';
    caja.style.top = (abajo < 200 && arriba > abajo ? r.top - 4 - Math.min(alto, caja.scrollHeight) : r.bottom + 4) + 'px';
    caja.style.width = Math.max(r.width, 280) + 'px';
  };
  const mostrar = () => {
    const q = norm(input.value.trim());
    const palabras = q.split(/\s+/).filter(Boolean);
    const hallados = opciones.filter(o => palabras.every(p => o.n.includes(p)));
    // primero las que empiezan con lo escrito (código)
    hallados.sort((a, b) => (b.n.startsWith(q) - a.n.startsWith(q)));
    marcada = -1;
    caja.innerHTML = hallados.length
      ? hallados.slice(0, MAX).map((o, i) => {
          const [cod, ...resto] = o.txt.split(' · ');
          return `<div class="opcion" role="option" data-i="${i}" data-valor="${esc(o.txt)}"><strong>${esc(cod)}</strong> <span>${esc(resto.join(' · '))}</span></div>`;
        }).join('') + (hallados.length > MAX ? `<div class="pie-lista">${hallados.length - MAX} más… siga escribiendo para acotar</div>` : '')
      : '<div class="pie-lista">Ninguna variedad coincide. <a href="nomenclador.php" target="_blank">Ver nomenclador</a></div>';
    caja.hidden = false;
    ubicar();
  };
  const cerrar = () => { caja.hidden = true; marcada = -1; };
  const elegir = el => {
    input.value = el.dataset.valor;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
    cerrar();
  };
  const marcar = i => {
    const ops = caja.querySelectorAll('.opcion');
    if (!ops.length) return;
    marcada = (i + ops.length) % ops.length;
    ops.forEach((o, k) => o.classList.toggle('marcada', k === marcada));
    ops[marcada].scrollIntoView({ block: 'nearest' });
  };
  const esVariedad = el => el && el.matches && el.matches('input[list="lista-variedades"], input[data-variedades]');

  document.addEventListener('focusin', e => {
    if (!esVariedad(e.target) || e.target.disabled) return;
    input = e.target;
    if (input.hasAttribute('list')) { input.removeAttribute('list'); input.dataset.variedades = ''; }
    input.setAttribute('autocomplete', 'off');
    mostrar();
  });
  document.addEventListener('input', e => { if (e.target === input && esVariedad(input)) mostrar(); });
  document.addEventListener('keydown', e => {
    if (e.target !== input || caja.hidden) return;
    if (e.key === 'ArrowDown') { e.preventDefault(); marcar(marcada + 1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); marcar(marcada - 1); }
    else if (e.key === 'Enter' && marcada >= 0) { e.preventDefault(); elegir(caja.querySelectorAll('.opcion')[marcada]); }
    else if (e.key === 'Escape' || e.key === 'Tab') cerrar();
  });
  caja.addEventListener('mousedown', e => {
    e.preventDefault(); // no quitar el foco del campo (el enlace igual se abre con el click)
    const op = e.target.closest('.opcion');
    if (op) elegir(op);
  });
  document.addEventListener('focusout', e => { if (e.target === input) setTimeout(cerrar, 120); });
  window.addEventListener('resize', () => { if (!caja.hidden) ubicar(); });
  window.addEventListener('scroll', () => { if (!caja.hidden) ubicar(); }, true);
})();

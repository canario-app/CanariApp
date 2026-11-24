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

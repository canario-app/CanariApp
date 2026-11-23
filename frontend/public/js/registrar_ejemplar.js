// Vista previa en vivo del ejemplar que se está registrando
const f = document.getElementById('formEjemplar');
const prevAnillo = document.getElementById('prevAnillo');
const prevBadges = document.getElementById('prevBadges');
const esc = s => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function actualizar() {
  const num = f.numero.value.trim() || '—';
  prevAnillo.innerHTML = `<strong>${esc(num)}</strong> <span class="muted">· ${esc(f.club.value)} · ${esc(f.socio.value.trim() || '—')} · ${esc(f.temp.value)}</span>`;
  const sexo = f.querySelector('input[name=sexo]:checked')?.value;
  const variedad = f.variedad.value.trim();
  prevBadges.innerHTML = (sexo ? `<span class="badge">${sexo}</span>` : '') + (variedad ? `<span class="badge">${esc(variedad)}</span>` : '');
}
f.addEventListener('input', actualizar);
f.addEventListener('change', actualizar);
actualizar();

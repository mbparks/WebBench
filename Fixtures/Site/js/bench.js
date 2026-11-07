let keys = '';
window.addEventListener('keydown', event => {
  keys = (keys + event.key.toUpperCase()).slice(-4);
  if (keys === 'ODIN') {
    document.getElementById('signal').textContent = 'Mjölnir unlocked';
    const badge = document.createElement('strong');
    badge.textContent = ' ⚡';
    document.getElementById('signal').append(badge);
    console.log('ODIN');
  }
});
const meter = document.getElementById('meter');
let grip;
let dragged = false;
meter.addEventListener('dragstart', event => event.preventDefault());
meter.addEventListener('pointerdown', event => {
  if (event.button !== 0) return;
  dragged = false;
  grip = [event.clientX, event.clientY, meter.offsetLeft, meter.offsetTop];
});
window.addEventListener('pointermove', event => {
  if (!grip || !event.buttons) return;
  const dx = event.clientX - grip[0], dy = event.clientY - grip[1];
  if (!dragged && Math.hypot(dx, dy) < 4) return;
  dragged = true;
  meter.style.left = grip[2] + dx + 'px';
  meter.style.top = grip[3] + dy + 'px';
});
window.addEventListener('pointerup', () => { grip = null; });
window.addEventListener('pointercancel', () => { grip = null; });
meter.addEventListener('click', event => {
  if (dragged) event.preventDefault();
}, true);

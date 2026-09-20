// The toy dock in the hero magnifies the way the real one does: every tile is
// scaled by its distance from the pointer, not just the one underneath it.
const dock = document.getElementById('dock');
if (dock) {
  const tiles = [...dock.querySelectorAll('.tile')];
  const MAX = 1.55;
  const REACH = 120;

  function magnify(event) {
    const pointer = event.clientX;
    for (const tile of tiles) {
      const box = tile.getBoundingClientRect();
      const distance = Math.abs(pointer - (box.left + box.width / 2));
      const falloff = Math.max(0, 1 - distance / REACH);
      const scale = 1 + (MAX - 1) * falloff * falloff;
      tile.style.transform = `scale(${scale.toFixed(3)})`;
    }
  }

  function rest() {
    for (const tile of tiles) tile.style.transform = 'scale(1)';
  }

  dock.addEventListener('pointermove', magnify);
  dock.addEventListener('pointerleave', rest);
}

// A real clock on the clock tile, because a screenshot of a clock that is
// always 10:09 is a small lie on a page about live widgets.
const face = document.getElementById('hands');
if (face) {
  const hands = {
    hour: face.querySelector('.hour'),
    minute: face.querySelector('.minute'),
    second: face.querySelector('.second'),
  };
  function tick() {
    const now = new Date();
    const seconds = now.getSeconds();
    const minutes = now.getMinutes() + seconds / 60;
    const hours = (now.getHours() % 12) + minutes / 60;
    hands.hour.style.transform = `rotate(${hours * 30}deg)`;
    hands.minute.style.transform = `rotate(${minutes * 6}deg)`;
    hands.second.style.transform = `rotate(${seconds * 6}deg)`;
    requestAnimationFrame(() => setTimeout(tick, 1000 - (Date.now() % 1000)));
  }
  tick();
}

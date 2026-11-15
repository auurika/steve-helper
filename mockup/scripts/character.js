/**
 * Стив: разметка пиксельного осьминога и управление его анимациями.
 *
 * Один и тот же Стив живёт в нескольких местах (меню-бар, всплывающее окно, окно, Dock),
 * поэтому все экземпляры играют одну анимацию одновременно.
 */
(function (app) {
  'use strict';

  /* ---------- разметка ---------- */
  const PIXEL_Z =
    '<rect x="0" y="0" width="10" height="2"/><rect x="6" y="2" width="2" height="2"/>' +
    '<rect x="4" y="4" width="2" height="2"/><rect x="2" y="6" width="2" height="2"/>' +
    '<rect x="0" y="8" width="10" height="2"/>';
  const PIXEL_NOTE =
    '<rect x="0" y="8" width="6" height="6"/><rect x="4" y="0" width="2" height="10"/>' +
    '<rect x="4" y="0" width="8" height="2"/>';

  function markup(tiny) {
    const letters = [1, 2, 3]
      .map(
        (n) =>
          `<g transform="translate(92 14)"><g class="steve-z steve-z${n}" fill="#E8DAFF"><g class="steve-zz">${PIXEL_Z}</g></g></g>`
      )
      .join('');

    return `<svg class="steve${tiny ? ' is-tiny' : ''}" viewBox="0 -30 128 150" xmlns="http://www.w3.org/2000/svg" shape-rendering="crispEdges" aria-hidden="true">
  <g class="steve-root"><g class="steve-body">
    <g fill="#B07CD9">
      <rect x="32" y="20" width="64" height="8"/><rect x="24" y="28" width="80" height="44"/>
      <rect class="steve-leg steve-leg1" x="28" y="72" width="12" height="24"/>
      <rect class="steve-leg steve-leg2" x="48" y="72" width="12" height="32"/>
      <rect class="steve-leg steve-leg3" x="68" y="72" width="12" height="26"/>
      <rect class="steve-leg steve-leg4" x="88" y="72" width="12" height="28"/>
    </g>
    <g class="steve-eyes" fill="#1F1F1F">
      <rect class="steve-eye" x="46" y="50" width="8" height="12"/>
      <rect class="steve-eye" x="74" y="50" width="8" height="12"/>
    </g>
    <rect class="steve-mouth" x="58" y="64" width="12" height="4" fill="#1F1F1F"/>
  </g></g>
  ${letters}
  <g class="steve-dots" fill="#F4F6FF">
    <rect class="steve-d1" x="100" y="10" width="4" height="4"/>
    <rect class="steve-d2" x="108" y="0" width="6" height="6"/>
    <rect class="steve-d3" x="118" y="-14" width="10" height="10"/>
  </g>
  <g class="steve-bang" fill="#FFD95A"><rect x="61" y="-22" width="6" height="16"/><rect x="61" y="-2" width="6" height="6"/></g>
  <g class="steve-sparks" fill="#FFF3A8">
    <g class="steve-spark steve-spark1"><rect x="16" y="22" width="2" height="8"/><rect x="13" y="25" width="8" height="2"/></g>
    <g class="steve-spark steve-spark2"><rect x="110" y="14" width="2" height="8"/><rect x="107" y="17" width="8" height="2"/></g>
    <g class="steve-spark steve-spark3"><rect x="114" y="52" width="2" height="6"/><rect x="112" y="54" width="6" height="2"/></g>
  </g>
  <g class="steve-notes" fill="#F4F6FF">
    <g transform="translate(104 20)"><g class="steve-note steve-n1">${PIXEL_NOTE}</g></g>
    <g transform="translate(14 24)"><g class="steve-note steve-n2">${PIXEL_NOTE}</g></g>
  </g>
</svg>`;
  }

  /* ---------- управление анимациями ---------- */
  const instances = [];
  const ONE_SHOT_MS = {
    blink: 300, 'look-left': 1800, 'look-right': 1800, 'look-around': 3600, hop: 1000, wiggle: 1400,
    wave: 2200, yawn: 2600, think: 2800, happy: 2000, surprise: 1800, dance: 3200, stretch: 2200,
  };
  const STATUS_ANIMATION = { listening: 'listen', thinking: 'think', working: 'work', speaking: 'talk' };

  const state = { anim: null, loop: false, asleep: false, timer: null };

  /** Создаёт Стива внутри контейнера и добавляет его в общий список. */
  function mount(container, { tiny = false } = {}) {
    container.innerHTML = markup(tiny);
    container.classList.add('character');
    instances.push(container.firstElementChild);
  }

  function clear() {
    clearTimeout(state.timer);
    instances.forEach((svg) => {
      delete svg.dataset.anim;
      svg.classList.remove('is-loop');
    });
    state.anim = null;
    state.loop = false;
  }

  /** Запускает анимацию. loop=true держит её, пока не вызовут clear(). */
  function play(name, { loop = false } = {}) {
    clear();
    void document.body.offsetHeight; // заставляет браузер перезапустить CSS-анимацию
    instances.forEach((svg) => {
      svg.dataset.anim = name;
      svg.classList.toggle('is-loop', loop);
    });
    state.anim = name;
    state.loop = loop;
    if (!loop) state.timer = setTimeout(clear, (ONE_SHOT_MS[name] || 1500) + 60);
  }

  /** Переводит Стива в позу, соответствующую статусу ассистента. */
  function setStatus(status) {
    if (status === 'idle') {
      if (state.loop) clear();
      return;
    }
    wake({ stretch: false });
    play(STATUS_ANIMATION[status], { loop: true });
  }

  function sleep() {
    clear();
    state.asleep = true;
    instances.forEach((svg) => svg.classList.add('is-asleep'));
  }

  function wake({ stretch = true } = {}) {
    if (!state.asleep) return;
    state.asleep = false;
    instances.forEach((svg) => svg.classList.remove('is-asleep'));
    if (stretch) play('stretch');
  }

  /** Глаза следят за кареткой в поле ввода: вниз и слева направо вдоль строки. */
  function followCaret(input) {
    const column = input.value.slice(0, input.selectionStart).split('\n').pop().length;
    const x = -6 + 12 * Math.min(1, column / 36);
    instances.forEach((svg) => {
      svg.style.setProperty('--eye-x', `${x.toFixed(1)}px`);
      svg.style.setProperty('--eye-y', '4px');
    });
    if (state.anim !== 'follow') play('follow', { loop: true });
  }

  function stopFollowing() {
    if (state.anim === 'follow') clear();
  }

  app.character = {
    mount, play, clear, setStatus, sleep, wake, followCaret, stopFollowing,
    get current() { return state.anim; },
    get isAsleep() { return state.asleep; },
    get isHolding() { return state.loop; },
  };
})(window.SteveApp = window.SteveApp || {});

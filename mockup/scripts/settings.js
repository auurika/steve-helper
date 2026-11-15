/** Простые настройки: переключатели, ползунок прозрачности, статус сети. */
(function (app) {
  'use strict';

  const { $, $$, clamp } = app.dom;

  const SWITCH_DEFAULTS = {
    censorship: true, // цензура включена по умолчанию
    showCommands: true,
    speak: true,
    autostart: false,
    listenAlways: true,
  };

  /* ---------- переключатели ---------- */
  function setSwitch(button, on) {
    button.setAttribute('aria-checked', String(on));
    if (button.dataset.setting === 'showCommands') {
      document.body.classList.toggle('hide-tools', !on);
    }
  }

  function initSwitches() {
    $$('.switch[data-setting]').forEach((button) => {
      const name = button.dataset.setting;
      setSwitch(button, app.store.read(`switch:${name}`, SWITCH_DEFAULTS[name]));
      button.addEventListener('click', () => {
        const next = button.getAttribute('aria-checked') !== 'true';
        setSwitch(button, next);
        app.store.write(`switch:${name}`, next);
      });
    });
  }

  /** Включена ли настройка. Используется озвучкой и другими модулями. */
  function isOn(name) {
    return $(`.switch[data-setting="${name}"]`).getAttribute('aria-checked') === 'true';
  }

  /* ---------- прозрачность Liquid Glass ---------- */
  // 0% — почти матовое стекло (плотность 0.9), 100% — почти невидимое (0.05)
  const alphaFor = (percent) => (0.9 - (percent / 100) * 0.85).toFixed(3);

  function applyGlass(percent) {
    document.documentElement.style.setProperty('--glass-alpha', alphaFor(percent));
    const slider = $('#glass-slider');
    slider.style.setProperty('--value', percent / 100);
    slider.classList.toggle('is-empty', percent === 0);
    slider.setAttribute('aria-valuenow', percent);
    $('#glass-value').textContent = `${percent}%`;
    app.store.write('glass', percent);
  }

  function initGlassSlider() {
    const slider = $('#glass-slider');
    let value = app.store.read('glass', 60);
    const set = (next) => {
      value = clamp(Math.round(next), 0, 100);
      applyGlass(value);
    };
    const fromPointer = (clientX) => {
      const box = slider.getBoundingClientRect();
      return ((clientX - box.left) / box.width) * 100;
    };

    slider.addEventListener('pointerdown', (event) => {
      try { slider.setPointerCapture(event.pointerId); } catch (error) { /* синтетические события без указателя */ }
      set(fromPointer(event.clientX));
      const onMove = (moveEvent) => set(fromPointer(moveEvent.clientX));
      const onUp = () => {
        slider.removeEventListener('pointermove', onMove);
        slider.removeEventListener('pointerup', onUp);
      };
      slider.addEventListener('pointermove', onMove);
      slider.addEventListener('pointerup', onUp);
    });

    slider.addEventListener('keydown', (event) => {
      const steps = { ArrowRight: 5, ArrowUp: 5, ArrowLeft: -5, ArrowDown: -5 };
      if (event.key in steps) set(value + steps[event.key]);
      else if (event.key === 'Home') set(0);
      else if (event.key === 'End') set(100);
      else return;
      event.preventDefault();
    });

    applyGlass(value);
  }

  /* ---------- статус сети ---------- */
  // Стив работает офлайн; «онлайн» означает только, что интернет есть для необязательных функций
  function setNetwork(online) {
    const status = $('#net-status');
    status.classList.toggle('is-offline', !online);
    $('.sidebar-label', status).textContent = online ? 'Работает онлайн' : 'Работает офлайн';
  }

  function initNetwork() {
    const status = $('#net-status');
    setNetwork(false);
    // в макете статус можно переключить кликом, чтобы увидеть оба цвета
    status.addEventListener('click', () => setNetwork(status.classList.contains('is-offline')));
    window.addEventListener('online', () => setNetwork(true));
    window.addEventListener('offline', () => setNetwork(false));
  }

  function init() {
    initSwitches();
    initGlassSlider();
    initNetwork();
  }

  app.settings = { init, isOn };
})(window.SteveApp = window.SteveApp || {});

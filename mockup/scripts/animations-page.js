/**
 * Страница с анимациями Стива: каждую можно запустить вручную,
 * сон наступает через 5 минут без запросов (счётчик виден на странице).
 */
(function (app) {
  'use strict';

  const { $, escapeHtml } = app.dom;

  const ANIMATIONS = [
    { id: 'blink', title: 'Моргает', note: 'сам в простое' },
    { id: 'look-left', title: 'Смотрит влево', note: 'сам в простое' },
    { id: 'look-right', title: 'Смотрит вправо', note: 'сам в простое' },
    { id: 'look-around', title: 'Осматривается', note: 'сам в простое' },
    { id: 'hop', title: 'Подпрыгивает', note: 'сам в простое' },
    { id: 'wiggle', title: 'Покачивается', note: 'сам в простое' },
    { id: 'wave', title: 'Машет лапкой', note: 'сам в простое' },
    { id: 'yawn', title: 'Зевает', note: 'сам в простое' },
    { id: 'think', title: 'Задумался', note: '' },
    { id: 'happy', title: 'Радуется', note: 'на «спасибо»' },
    { id: 'surprise', title: 'Удивился', note: '' },
    { id: 'dance', title: 'Танцует', note: '' },
    { id: 'stretch', title: 'Потягивается', note: 'просыпается' },
    { id: 'sleep', title: 'Спит (Zzz)', note: 'через 5 мин' },
  ];
  const TITLES = Object.fromEntries(ANIMATIONS.map((item) => [item.id, item.title]));
  const WAKE_THEN_THINK_MS = 2300;
  const THINK_THEN_HAPPY_MS = 2900;

  function renderList() {
    const items = ANIMATIONS.map((item) => `
      <button class="animation-item" type="button" data-animation="${item.id}">
        <span>${escapeHtml(item.title)}</span><small>${escapeHtml(item.note)}</small>
      </button>`);
    $('#animation-list').insertAdjacentHTML('beforeend', items.join(''));
  }

  function formatTime(ms) {
    const total = Math.ceil(ms / 1000);
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
  }

  function refresh() {
    const asleep = app.character.isAsleep;
    const current = app.character.current;
    $('#state-name').textContent = asleep ? 'Спит' : TITLES[current] || 'Бодрствует';
    $('#sleep-timer').textContent = asleep ? 'спит' : formatTime(app.idle.remaining());
    $('#sleep-progress').style.width = asleep ? '0%' : `${(app.idle.remaining() / app.idle.settings.sleepAfter) * 100}%`;
    $('#scene').classList.toggle('is-night', asleep);
    document.querySelectorAll('.animation-item').forEach((button) => {
      const active = button.dataset.animation === (asleep ? 'sleep' : current);
      button.classList.toggle('is-active', active);
    });
  }

  function playManually(id) {
    if (id === 'sleep') return app.character.sleep();
    if (app.character.isAsleep) app.character.wake({ stretch: false });
    app.idle.touch();
    return app.character.play(id);
  }

  function sendRequest() {
    const wasAsleep = app.character.isAsleep;
    app.idle.touch(); // будит и сбрасывает счётчик
    const delay = wasAsleep ? WAKE_THEN_THINK_MS : 0;
    setTimeout(() => app.character.play('think'), delay);
    setTimeout(() => app.character.play('happy'), delay + THINK_THEN_HAPPY_MS);
  }

  function init() {
    app.character.mount($('#stage-character'));
    renderList();
    app.idle.start(() => false);

    $('#animation-list').addEventListener('click', (event) => {
      const button = event.target.closest('.animation-item');
      if (button) playManually(button.dataset.animation);
    });
    $('#stage-character').addEventListener('click', () => {
      app.idle.touch();
      if (!app.character.isAsleep) app.character.play('surprise');
    });
    $('#sleep-now').addEventListener('click', () => app.character.sleep());
    $('#wake-now').addEventListener('click', () => app.idle.touch());

    const input = $('#request-input');
    input.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
        event.preventDefault();
        $('#request-form').requestSubmit();
      }
    });
    $('#request-form').addEventListener('submit', (event) => {
      event.preventDefault();
      if (!input.value.trim()) return;
      sendRequest();
      input.value = '';
    });

    setInterval(refresh, 250);
    refresh();
  }

  init();
})(window.SteveApp);

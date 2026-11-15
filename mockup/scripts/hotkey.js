/**
 * Сочетание для запуска Стива: от 1 до 3 клавиш и режим «нажатие» или «удерживание».
 * Нажми на сочетание в настройках, затем нажми новое. Escape отменяет запись.
 * Подойдёт и одна клавиша-модификатор: нажал и отпустил.
 */
(function (app) {
  'use strict';

  const { $ } = app.dom;

  const MAX_KEYS = 3;
  const PROMPT = 'Нажми сочетание…';
  const DEFAULT_COMBO = '⌥ + Пробел';
  const WARNING_MS = 1300;

  // порядок модификаторов как в macOS: ⌃ ⌥ ⇧ ⌘
  const MODIFIERS = [['ctrlKey', '⌃'], ['altKey', '⌥'], ['shiftKey', '⇧'], ['metaKey', '⌘']];
  const KEY_NAMES = {
    ' ': 'Пробел', Enter: 'Return', Tab: 'Tab', Backspace: '⌫', Delete: '⌦',
    ArrowUp: '↑', ArrowDown: '↓', ArrowLeft: '←', ArrowRight: '→',
  };
  const MODIFIER_KEYS = ['Control', 'Alt', 'Shift', 'Meta'];

  const MODES = {
    press: {
      label: 'Нажатие',
      hint: 'Нажал — Стив слушает, нажал ещё раз — закончил. Нажми, чтобы переключить на удерживание',
    },
    hold: {
      label: 'Удерживание',
      hint: 'Стив слушает, пока держишь сочетание. Нажми, чтобы переключить на нажатие',
    },
  };

  let combo = DEFAULT_COMBO;
  let mode = 'press';
  let recording = false;
  let peakModifiers = []; // самый большой набор модификаторов, удержанный за время записи
  let warningTimer = null;

  const isModifierKey = (key) => MODIFIER_KEYS.includes(key);
  const heldModifiers = (event) => MODIFIERS.filter(([flag]) => event[flag]).map(([, symbol]) => symbol);

  function keyName(event) {
    if (/^Key[A-Z]$/.test(event.code)) return event.code.slice(3);
    if (/^Digit\d$/.test(event.code)) return event.code.slice(5);
    if (KEY_NAMES[event.key]) return KEY_NAMES[event.key];
    return event.key.length === 1 ? event.key.toUpperCase() : event.key;
  }

  function showLive(modifiers) {
    const button = $('#hotkey-combo');
    button.classList.remove('is-warning');
    button.textContent = modifiers.length ? `${modifiers.join(' + ')} + …` : PROMPT;
  }

  function warnTooMany() {
    const button = $('#hotkey-combo');
    button.classList.add('is-warning');
    button.textContent = `Максимум ${MAX_KEYS} клавиши`;
    clearTimeout(warningTimer);
    warningTimer = setTimeout(() => {
      button.classList.remove('is-warning');
      if (recording) button.textContent = PROMPT;
    }, WARNING_MS);
  }

  function stopRecording() {
    const button = $('#hotkey-combo');
    clearTimeout(warningTimer);
    recording = false;
    peakModifiers = [];
    button.classList.remove('is-recording', 'is-warning');
    button.textContent = combo;
    button.blur();
  }

  function commit(parts) {
    combo = parts.join(' + ');
    app.store.write('hotkey', combo);
    stopRecording();
  }

  function onKeyDown(event) {
    if (!recording) return;
    event.preventDefault();
    event.stopPropagation();

    if (event.key === 'Escape' && !event.repeat) return stopRecording();

    if (isModifierKey(event.key)) {
      const modifiers = heldModifiers(event);
      if (modifiers.length > MAX_KEYS) return warnTooMany();
      if (modifiers.length >= peakModifiers.length) peakModifiers = modifiers;
      return showLive(modifiers);
    }

    const parts = [...heldModifiers(event), keyName(event)];
    if (parts.length > MAX_KEYS) return warnTooMany();
    commit(parts);
  }

  function onKeyUp(event) {
    if (!recording || !isModifierKey(event.key)) return;
    const modifiers = heldModifiers(event);
    // все модификаторы отпущены и ничего больше не нажимали: сохраняем только их
    if (modifiers.length === 0 && peakModifiers.length) return commit(peakModifiers);
    showLive(modifiers);
  }

  function setMode(next) {
    mode = next;
    const button = $('#hotkey-mode');
    button.dataset.mode = next;
    button.textContent = MODES[next].label;
    button.title = MODES[next].hint;
    app.store.write('hotkeyMode', next);
  }

  function init() {
    combo = app.store.read('hotkey', DEFAULT_COMBO);
    $('#hotkey-combo').textContent = combo;
    setMode(app.store.read('hotkeyMode', 'press'));

    $('#hotkey-combo').addEventListener('click', () => {
      if (recording) return;
      recording = true;
      peakModifiers = [];
      $('#hotkey-combo').classList.add('is-recording');
      $('#hotkey-combo').textContent = PROMPT;
    });
    $('#hotkey-mode').addEventListener('click', () => setMode(mode === 'press' ? 'hold' : 'press'));

    // слушатели в фазе перехвата, чтобы клавиши не попали в другие обработчики
    document.addEventListener('keydown', onKeyDown, true);
    document.addEventListener('keyup', onKeyUp, true);
    document.addEventListener('mousedown', (event) => {
      if (recording && event.target !== $('#hotkey-combo')) stopRecording();
    });
  }

  app.hotkey = { init, get isRecording() { return recording; } };
})(window.SteveApp = window.SteveApp || {});

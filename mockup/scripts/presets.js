/**
 * Пресеты: готовые и свои команды быстрого доступа.
 * Быстрые команды (4 значка во всплывающем окне) выбираются из этого же списка,
 * поэтому правка пресета сразу видна и в слотах настроек, и во всплывающем окне.
 */
(function (app) {
  'use strict';

  const { $, escapeHtml } = app.dom;
  const { icon } = app.icons;

  const LIMITS = { name: 30, description: 60, phrase: 40 };
  const DEFAULT_ICON = 'puzzle';

  const DEFAULT_PRESETS = [
    { name: 'Открыть Safari', description: 'Открывает Safari на Mac', phrase: 'Открой Safari', icon: 'globe' },
    {
      name: 'Таймер на 10 минут',
      description: 'Запускает таймер на 10 минут в приложении «Часы»',
      phrase: 'Таймер на 10 минут',
      icon: 'timer',
    },
    {
      name: 'Новая заметка',
      description: 'Создаёт новую заметку в приложении «Заметки»',
      phrase: 'Запиши заметку: купить молоко',
      icon: 'note',
    },
    {
      name: 'Событие в календаре',
      description: 'Добавляет событие в приложение «Календарь»',
      phrase: '23 ноября с 17 до 19 событие Зал',
      icon: 'calendar',
    },
    {
      name: 'Громкость 30%',
      description: 'Системный звук становится на уровень 30%',
      phrase: 'Громкость 30%',
      icon: 'vol',
    },
  ];
  // по умолчанию во всплывающем окне: таймер, заметка, Safari, календарь
  const DEFAULT_QUICK = [1, 2, 0, 3];

  let presets = app.store.read('presets', DEFAULT_PRESETS);
  let quick = app.store.read('quick', DEFAULT_QUICK).filter((index) => presets[index]);
  let editingIndex = null; // null — создаём новый пресет
  let editingIcon = DEFAULT_ICON;
  let pickingSlot = 0;
  let onIconPicked = null;

  function save() {
    app.store.write('presets', presets);
    app.store.write('quick', quick);
  }

  /* ---------- экран «Пресеты» ---------- */
  function renderGrid() {
    const cards = presets.map((preset, index) => `
      <button class="preset" type="button" data-index="${index}">
        <span class="preset-head">
          <span class="icon-tile">${icon(preset.icon)}</span>
          <span class="preset-title">${escapeHtml(preset.name)}</span>
        </span>
        <span class="preset-description">${escapeHtml(preset.description)}</span>
        <span class="preset-phrase">«${escapeHtml(preset.phrase)}»</span>
      </button>`);
    cards.push(`
      <button class="preset preset--add" type="button" id="preset-add">
        <span class="preset-head">
          <span class="icon-tile">${icon('plus')}</span>
          <span class="preset-title">Новая команда</span>
        </span>
        <span class="preset-description">Создайте свою собственную команду для Стива</span>
      </button>`);
    $('#preset-grid').innerHTML = cards.join('');
  }

  /* ---------- быстрые команды ---------- */
  function renderQuick() {
    $('#quick-buttons').innerHTML = quick.map((index) => {
      const preset = presets[index];
      return `<button class="quick-button glass-control" type="button" data-index="${index}" title="${escapeHtml(preset.name)}">${icon(preset.icon)}</button>`;
    }).join('');

    $('#quick-grid').innerHTML = quick.map((index, slot) => {
      const preset = presets[index];
      return `<button class="slot" type="button" data-slot="${slot}" title="Сменить команду">${icon(preset.icon)}<span class="slot-name">${escapeHtml(preset.name)}</span></button>`;
    }).join('');
  }

  function openQuickPicker(slot) {
    pickingSlot = slot;
    $('#quick-subtitle').textContent = `Выбери команду для кнопки ${slot + 1}. Уже выбранные недоступны.`;
    $('#quick-list').innerHTML = presets.map((preset, index) => {
      const isMine = quick[slot] === index;
      const isTaken = quick.includes(index) && !isMine;
      return `<button class="pick${isMine ? ' is-selected' : ''}" type="button" data-index="${index}"${isTaken ? ' disabled title="Уже выбрана"' : ''}>${icon(preset.icon)}<span class="slot-name">${escapeHtml(preset.name)}</span></button>`;
    }).join('');
    app.dialogs.open('quick');
  }

  /* ---------- окно редактирования ---------- */
  function updateCounter(input) {
    const counter = $('.counter', input.parentElement);
    counter.textContent = `${input.value.length}/${input.maxLength}`;
    counter.classList.toggle('is-low', input.maxLength - input.value.length <= 5);
  }

  function refreshForm() {
    const name = $('#command-name');
    const description = $('#command-description');
    const phrase = $('#command-phrase');
    [name, description, phrase].forEach(updateCounter);
    $('#command-save').disabled = !(name.value.trim() && phrase.value.trim());
  }

  function openEditor(index) {
    editingIndex = index;
    const preset = index === null ? null : presets[index];
    editingIcon = preset ? preset.icon : DEFAULT_ICON;

    $('#command-icon').innerHTML = icon(editingIcon);
    $('#command-name').value = preset ? preset.name : '';
    $('#command-description').value = preset ? preset.description : '';
    $('#command-phrase').value = preset ? preset.phrase : '';
    $('#command-title').textContent = preset ? 'Редактирование команды' : 'Новая команда';
    $('#command-save').textContent = preset ? 'Сохранить' : 'Создать';
    refreshForm();
    app.dialogs.open('command');
  }

  function saveEditor() {
    const preset = {
      name: $('#command-name').value.trim(),
      description: $('#command-description').value.trim() || 'Своя команда',
      phrase: $('#command-phrase').value.trim(),
      icon: editingIcon,
    };
    if (editingIndex === null) presets.push(preset);
    else presets[editingIndex] = preset;
    save();
    renderAll();
    app.dialogs.close('command');
  }

  /* ---------- выбор иконки ---------- */
  function openIconPicker(current, callback) {
    onIconPicked = callback;
    $('#icon-grid').innerHTML = app.icons.names.map((name) =>
      `<button class="icon-option${name === current ? ' is-selected' : ''}" type="button" data-icon="${name}">${icon(name)}</button>`
    ).join('');
    app.dialogs.open('icon');
  }

  function renderAll() {
    renderGrid();
    renderQuick();
  }

  function init() {
    Object.entries(LIMITS).forEach(([key, max]) => {
      $(`#command-${key === 'phrase' ? 'phrase' : key}`).maxLength = max;
    });

    renderAll();

    $('#preset-grid').addEventListener('click', (event) => {
      const card = event.target.closest('.preset');
      if (!card) return;
      openEditor(card.id === 'preset-add' ? null : Number(card.dataset.index));
    });

    $('#quick-grid').addEventListener('click', (event) => {
      const slot = event.target.closest('.slot');
      if (slot) openQuickPicker(Number(slot.dataset.slot));
    });

    $('#quick-list').addEventListener('click', (event) => {
      const pick = event.target.closest('.pick');
      if (!pick || pick.disabled) return;
      quick[pickingSlot] = Number(pick.dataset.index);
      save();
      renderQuick();
      app.dialogs.close('quick');
    });

    $('#quick-buttons').addEventListener('click', (event) => {
      const button = event.target.closest('.quick-button');
      if (button) app.assistant.ask(presets[Number(button.dataset.index)].phrase);
    });

    $('#command-icon').addEventListener('click', () => {
      openIconPicker(editingIcon, (name) => {
        editingIcon = name;
        $('#command-icon').innerHTML = icon(name);
      });
    });

    $('#icon-grid').addEventListener('click', (event) => {
      const option = event.target.closest('.icon-option');
      if (!option) return;
      const callback = onIconPicked;
      app.dialogs.close('icon');
      if (callback) callback(option.dataset.icon);
    });

    ['name', 'description', 'phrase'].forEach((key) => {
      $(`#command-${key}`).addEventListener('input', refreshForm);
    });
    $('#command-save').addEventListener('click', saveEditor);
    document.addEventListener('dialog:close', (event) => {
      if (event.detail === 'icon') onIconPicked = null;
    });
  }

  app.presets = { init };
})(window.SteveApp = window.SteveApp || {});

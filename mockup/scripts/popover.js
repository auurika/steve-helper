/**
 * Всплывающее окно из значка Стива в меню-баре.
 * Вылетает из значка, закрывается кликом по значку, кликом в стороне или клавишей Escape.
 */
(function (app) {
  'use strict';

  const { $ } = app.dom;

  const WIDTH = 340;
  const SCREEN_MARGIN = 8;
  const GAP_BELOW_TRAY = 8;
  const CLOSE_ANIMATION_MS = 220;
  const FIRST_SHOW_DELAY_MS = 600;

  let closeTimer = null;

  const isOpen = () => $('#popover').classList.contains('is-open');

  /** Ставит окно под значком и запоминает, откуда оно должно «вылететь». */
  function place() {
    const popover = $('#popover');
    const tray = $('#tray-button').getBoundingClientRect();
    const width = Math.min(WIDTH, window.innerWidth - SCREEN_MARGIN * 2);
    const trayCenter = tray.left + tray.width / 2;
    const left = Math.max(SCREEN_MARGIN, Math.min(trayCenter - width / 2, window.innerWidth - width - SCREEN_MARGIN));

    popover.style.left = `${left}px`;
    popover.style.top = `${tray.bottom + GAP_BELOW_TRAY}px`;
    popover.style.setProperty('--origin-x', `${trayCenter - left}px`);
  }

  function open() {
    const popover = $('#popover');
    clearTimeout(closeTimer);
    place();
    popover.classList.remove('is-closing', 'is-open');
    void popover.offsetWidth; // перезапуск анимации появления
    popover.classList.add('is-open');
    $('#tray-button').classList.add('is-open');
  }

  function close() {
    if (!isOpen()) return;
    const popover = $('#popover');
    $('#tray-button').classList.remove('is-open');
    popover.classList.remove('is-open');
    popover.classList.add('is-closing');
    closeTimer = setTimeout(() => popover.classList.remove('is-closing'), CLOSE_ANIMATION_MS);
  }

  function init() {
    const popover = $('#popover');
    const tray = $('#tray-button');

    tray.addEventListener('click', () => {
      app.idle.touch();
      if (isOpen()) close();
      else open();
    });

    document.addEventListener('mousedown', (event) => {
      if (isOpen() && !popover.contains(event.target) && !tray.contains(event.target)) close();
    });

    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && isOpen() && !app.dialogs.hasOpen() && !app.hotkey.isRecording) close();
    });

    window.addEventListener('resize', () => isOpen() && place());

    // первый показ: сразу видно, как окно вылетает из меню-бара
    setTimeout(open, FIRST_SHOW_DELAY_MS);
  }

  app.popover = { init, open, close };
})(window.SteveApp = window.SteveApp || {});

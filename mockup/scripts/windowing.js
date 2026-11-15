/**
 * Окно приложения как в macOS:
 *  - красная кнопка прячет окно (приложение остаётся в меню-баре и Dock),
 *  - жёлтая сворачивает окно в Dock,
 *  - зелёная (или двойной клик по заголовку) раскрывает на весь экран и возвращает обратно,
 *  - за заголовок окно можно перетаскивать,
 *  - тянуть можно за любой край и любой угол.
 */
(function (app) {
  'use strict';

  const { $, $$, clamp } = app.dom;

  const MIN_WIDTH = 420;
  const MIN_HEIGHT = 460;
  const DEFAULT_SIZE = { width: 960, height: 640 };
  const DOCK_SPACE = 84; // место под Dock при первом размещении
  const TITLEBAR_HEIGHT = 40;
  const VISIBLE_STRIP = 100; // сколько окна должно оставаться на экране при перетаскивании
  const ANIMATION_MS = 320;

  let rect = null; // положение и размер в обычном режиме
  let isFullscreen = false;
  let rectBeforeFullscreen = null;

  const windowEl = () => $('#window');
  const desktopSize = () => {
    const desktop = $('#desktop').getBoundingClientRect();
    return { width: desktop.width, height: desktop.height };
  };

  function apply(next) {
    const el = windowEl();
    el.style.left = `${next.x}px`;
    el.style.top = `${next.y}px`;
    el.style.width = `${next.width}px`;
    el.style.height = `${next.height}px`;
  }

  function save() {
    if (!isFullscreen) app.store.write('window', rect);
  }

  /** Держит окно в пределах рабочего стола и не даёт сделать его слишком маленьким. */
  function fit(next) {
    const desk = desktopSize();
    const width = clamp(next.width, MIN_WIDTH, Math.max(MIN_WIDTH, desk.width));
    const height = clamp(next.height, MIN_HEIGHT, Math.max(MIN_HEIGHT, desk.height));
    return {
      width,
      height,
      x: clamp(next.x, VISIBLE_STRIP - width, desk.width - VISIBLE_STRIP),
      y: clamp(next.y, 0, desk.height - TITLEBAR_HEIGHT),
    };
  }

  function defaultRect() {
    const desk = desktopSize();
    const width = Math.min(DEFAULT_SIZE.width, desk.width - 32);
    const height = Math.min(DEFAULT_SIZE.height, desk.height - DOCK_SPACE);
    return { width, height, x: (desk.width - width) / 2, y: 20 };
  }

  /** Плавно меняет размер, например при переходе в полный экран. */
  function animateGeometry(change) {
    const el = windowEl();
    el.classList.add('is-animating');
    change();
    setTimeout(() => el.classList.remove('is-animating'), ANIMATION_MS);
  }

  /* ---------- кнопки в заголовке ---------- */
  function hide() {
    windowEl().classList.add('is-hidden');
  }

  function minimize() {
    const el = windowEl();
    const win = el.getBoundingClientRect();
    const dock = $('#dock-button').getBoundingClientRect();
    el.style.setProperty('--to-x', `${dock.left + dock.width / 2 - (win.left + win.width / 2)}px`);
    el.style.setProperty('--to-y', `${dock.top + dock.height / 2 - (win.top + win.height / 2)}px`);
    el.classList.add('is-minimized');
  }

  function restore() {
    windowEl().classList.remove('is-hidden', 'is-minimized');
  }

  function toggleFullscreen() {
    const el = windowEl();
    animateGeometry(() => {
      if (isFullscreen) {
        isFullscreen = false;
        el.classList.remove('is-fullscreen');
        rect = rectBeforeFullscreen;
        apply(rect);
      } else {
        rectBeforeFullscreen = rect;
        isFullscreen = true;
        el.classList.add('is-fullscreen');
        apply({ x: 0, y: 0, ...desktopSize() });
      }
    });
  }

  /** Захватывает указатель, чтобы движение мыши не терялось за пределами элемента. */
  function capturePointer(element, pointerId) {
    try {
      element.setPointerCapture(pointerId);
    } catch (error) {
      /* события без настоящего указателя: движение всё равно придёт */
    }
  }

  /* ---------- перетаскивание за заголовок ---------- */
  function startDrag(event) {
    if (isFullscreen || event.button !== 0 || event.target.closest('.traffic')) return;
    const el = windowEl();
    const handle = event.currentTarget; // после обработки события currentTarget обнуляется, поэтому запоминаем
    const origin = { x: event.clientX, y: event.clientY, left: rect.x, top: rect.y };
    el.classList.add('is-dragging');
    capturePointer(handle, event.pointerId);

    const onMove = (move) => {
      rect = fit({ ...rect, x: origin.left + move.clientX - origin.x, y: origin.top + move.clientY - origin.y });
      apply(rect);
    };
    const onUp = () => {
      el.classList.remove('is-dragging');
      save();
      handle.removeEventListener('pointermove', onMove);
      handle.removeEventListener('pointerup', onUp);
    };
    handle.addEventListener('pointermove', onMove);
    handle.addEventListener('pointerup', onUp);
  }

  /* ---------- растягивание за края и углы ---------- */
  /** Считает новый размер при тяге за край. Противоположный край остаётся на месте. */
  function resizedRect(start, edge, dx, dy) {
    const desk = desktopSize();
    let { x, y, width, height } = start;

    if (edge.includes('e')) width = start.width + dx;
    if (edge.includes('s')) height = start.height + dy;
    if (edge.includes('w')) {
      width = start.width - dx;
      x = start.x + dx;
    }
    if (edge.includes('n')) {
      height = start.height - dy;
      y = start.y + dy;
    }

    // минимальный размер: при тяге за левый или верхний край двигаем и сам край
    if (width < MIN_WIDTH) {
      if (edge.includes('w')) x -= MIN_WIDTH - width;
      width = MIN_WIDTH;
    }
    if (height < MIN_HEIGHT) {
      if (edge.includes('n')) y -= MIN_HEIGHT - height;
      height = MIN_HEIGHT;
    }

    // не выходим за рабочий стол
    if (x < 0) { width += x; x = 0; }
    if (y < 0) { height += y; y = 0; }
    width = Math.min(width, desk.width - x);
    height = Math.min(height, desk.height - y);
    return { x, y, width: Math.max(width, MIN_WIDTH), height: Math.max(height, MIN_HEIGHT) };
  }

  function startResize(event) {
    if (isFullscreen || event.button !== 0) return;
    const handle = event.currentTarget;
    const el = windowEl();
    const start = { ...rect };
    const origin = { x: event.clientX, y: event.clientY };
    el.classList.add('is-resizing');
    capturePointer(handle, event.pointerId);

    const onMove = (move) => {
      rect = resizedRect(start, handle.dataset.edge, move.clientX - origin.x, move.clientY - origin.y);
      apply(rect);
    };
    const onUp = () => {
      el.classList.remove('is-resizing');
      save();
      handle.removeEventListener('pointermove', onMove);
      handle.removeEventListener('pointerup', onUp);
    };
    handle.addEventListener('pointermove', onMove);
    handle.addEventListener('pointerup', onUp);
  }

  function init() {
    rect = fit(app.store.read('window', null) || defaultRect());
    apply(rect);

    $('[data-action="close"]').addEventListener('click', hide);
    $('[data-action="minimize"]').addEventListener('click', minimize);
    $('[data-action="zoom"]').addEventListener('click', toggleFullscreen);
    $('#titlebar').addEventListener('dblclick', (event) => {
      if (!event.target.closest('.traffic')) toggleFullscreen();
    });
    $('#titlebar').addEventListener('pointerdown', startDrag);
    $$('.resize-handle').forEach((handle) => handle.addEventListener('pointerdown', startResize));
    $('#dock-button').addEventListener('click', () => {
      app.idle.touch();
      restore();
    });

    window.addEventListener('resize', () => {
      if (isFullscreen) apply({ x: 0, y: 0, ...desktopSize() });
      else {
        rect = fit(rect);
        apply(rect);
      }
    });
  }

  app.windowing = { init, restore, hide, minimize, toggleFullscreen };
})(window.SteveApp = window.SteveApp || {});

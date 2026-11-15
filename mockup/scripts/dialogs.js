/**
 * Диалоги поверх окна. Закрываются крестиком, кликом по пустой области и клавишей Escape.
 * Если открыто несколько (например, выбор иконки над редактированием команды), Escape закрывает верхний.
 */
(function (app) {
  'use strict';

  const { $, $$ } = app.dom;

  const byId = (id) => $(`#dialog-${id}`);

  function isOpen(id) {
    return byId(id).classList.contains('is-open');
  }

  function open(id) {
    byId(id).classList.add('is-open');
  }

  function close(id) {
    const modal = byId(id);
    if (!modal.classList.contains('is-open')) return;
    modal.classList.remove('is-open');
    document.dispatchEvent(new CustomEvent('dialog:close', { detail: id }));
  }

  /** Открытые диалоги от верхнего к нижнему. */
  function openStack() {
    const zIndex = (modal) => Number(getComputedStyle(modal).zIndex) || 0;
    return $$('.modal.is-open').sort((a, b) => zIndex(b) - zIndex(a));
  }

  function hasOpen() {
    return openStack().length > 0;
  }

  function init() {
    $$('.modal').forEach((modal) => {
      const id = modal.id.replace('dialog-', '');
      // mousedown, а не click: выделение текста в поле не должно закрывать окно, если отпустить мышь снаружи
      modal.addEventListener('mousedown', (event) => {
        if (event.target === modal) close(id);
      });
      $('.close-button', modal).addEventListener('click', () => close(id));
    });

    document.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;
      const top = openStack()[0];
      if (!top) return;
      event.preventDefault();
      close(top.id.replace('dialog-', ''));
    });
  }

  app.dialogs = { init, open, close, isOpen, hasOpen };
})(window.SteveApp = window.SteveApp || {});

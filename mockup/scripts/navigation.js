/** Переключение экранов через боковую панель. */
(function (app) {
  'use strict';

  const { $, $$ } = app.dom;

  function show(view) {
    $$('.view').forEach((section) => section.classList.toggle('is-active', section.id === `view-${view}`));
    $$('.sidebar-item[data-view]').forEach((item) => item.classList.toggle('is-active', item.dataset.view === view));
  }

  function init() {
    const sidebar = $('#sidebar');

    sidebar.addEventListener('click', (event) => {
      const item = event.target.closest('.sidebar-item[data-view]');
      if (!item) return;
      show(item.dataset.view);
      // после выбора панель сразу сворачивается, даже если курсор остался над ней
      sidebar.classList.add('is-locked');
      item.blur();
    });

    // снова раскрывается, когда курсор уйдёт и вернётся
    sidebar.addEventListener('mouseleave', () => sidebar.classList.remove('is-locked'));
  }

  app.navigation = { init, show };
})(window.SteveApp = window.SteveApp || {});

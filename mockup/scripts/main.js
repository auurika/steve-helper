/** Точка входа макета: собирает страницу и запускает модули в нужном порядке. */
(function (app) {
  'use strict';

  const { $ } = app.dom;

  /** Один и тот же Стив живёт в меню-баре, окне, всплывающем окне и Dock. */
  function mountCharacters() {
    app.character.mount($('#orb-main'));
    app.character.mount($('#orb-popover'));
    app.character.mount($('#tray-icon'), { tiny: true });
    app.character.mount($('#dock-icon'));
  }

  app.icons.hydrate();
  mountCharacters();

  app.dialogs.init();
  app.settings.init();
  app.hotkey.init();
  app.wake.init();
  app.voice.init();
  app.presets.init();
  app.chat.init();
  app.navigation.init();
  app.windowing.init();
  app.popover.init();
  app.idle.start(() => app.assistant.isBusy());
})(window.SteveApp);

/** Хранение настроек в localStorage. Если хранилище недоступно, макет просто работает без сохранения. */
(function (app) {
  'use strict';

  const PREFIX = 'steve:';

  function read(key, fallback) {
    try {
      const raw = localStorage.getItem(PREFIX + key);
      return raw === null ? fallback : JSON.parse(raw);
    } catch (error) {
      return fallback;
    }
  }

  function write(key, value) {
    try {
      localStorage.setItem(PREFIX + key, JSON.stringify(value));
    } catch (error) {
      /* приватный режим или переполнение: настройка не сохранится, это не критично */
    }
  }

  app.store = { read, write };
})(window.SteveApp = window.SteveApp || {});

/** Мелкие помощники для работы со страницей. */
(function (app) {
  'use strict';

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

  const HTML_ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

  /** Экранирует текст перед вставкой в HTML: названия команд вводит пользователь. */
  const escapeHtml = (text) => String(text).replace(/[&<>"']/g, (char) => HTML_ESCAPES[char]);

  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  app.dom = { $, $$, escapeHtml, clamp, wait };
})(window.SteveApp = window.SteveApp || {});

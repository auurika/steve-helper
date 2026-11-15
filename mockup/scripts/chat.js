/** Сообщения в двух диалогах (окно и всплывающее окно) и строки ввода. */
(function (app) {
  'use strict';

  const { $, $$ } = app.dom;

  const GREETING = 'Привет, меня зовут Стив, я твой друг. Я всегда рядом, если что-то нужно.';
  const MAX_INPUT_HEIGHT = 124;

  /** Добавляет сообщение в оба диалога. Ответы Стива всегда начинаются с заглавной буквы. */
  function addMessage({ from, text, tool = null }) {
    const content = from === 'steve' && text ? text[0].toUpperCase() + text.slice(1) : text;
    $$('.messages').forEach((list) => {
      const bubble = document.createElement('div');
      bubble.className = from === 'user' ? 'msg is-user' : 'msg';
      bubble.textContent = content;
      if (tool) {
        const toolLine = document.createElement('span');
        toolLine.className = 'msg-tool';
        toolLine.textContent = `tool · ${tool}`;
        bubble.append(toolLine);
      }
      list.append(bubble);
      list.scrollTop = list.scrollHeight;
    });
  }

  /**
   * Подключает строку ввода: высота растёт только вместе с текстом,
   * Enter отправляет, Shift+Enter переносит строку, Стив следит глазами за кареткой.
   */
  function bindComposer({ input, form, minHeight }) {
    const fit = () => {
      input.style.height = `${minHeight}px`;
      if (!input.value) return;
      input.style.height = `${Math.max(minHeight, Math.min(input.scrollHeight + 2, MAX_INPUT_HEIGHT))}px`;
    };

    const followIfTyping = () => {
      if (input.value.trim()) app.character.followCaret(input);
    };

    input.addEventListener('input', () => {
      fit();
      const hasText = Boolean(input.value.trim());
      app.assistant.typing(hasText);
      if (hasText) app.character.followCaret(input);
      else app.character.stopFollowing();
    });
    input.addEventListener('keyup', followIfTyping);
    input.addEventListener('click', followIfTyping);
    input.addEventListener('blur', () => {
      if (app.assistant.isBusy()) return;
      if (!input.value.trim()) app.assistant.setStatus('idle');
      app.character.stopFollowing();
    });
    input.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
        event.preventDefault();
        form.requestSubmit();
      }
    });

    form.addEventListener('submit', (event) => {
      event.preventDefault();
      const text = input.value.trim();
      if (!text) return;
      input.value = '';
      fit();
      app.assistant.ask(text, { typed: true });
    });
  }

  function init() {
    addMessage({ from: 'steve', text: GREETING });
    bindComposer({ input: $('#composer-input'), form: $('#composer-form'), minHeight: 42 });
    bindComposer({ input: $('#compact-input'), form: $('#compact-form'), minHeight: 38 });

    // Нажатие на Стива или на микрофон имитирует голосовой запрос
    const voiceDemo = () => app.assistant.ask('Поставь таймер на 5 минут');
    $('#orb-main').addEventListener('click', voiceDemo);
    $('#orb-popover').addEventListener('click', voiceDemo);
    $('#mic-button').addEventListener('click', voiceDemo);
  }

  app.chat = { init, addMessage };
})(window.SteveApp = window.SteveApp || {});

/**
 * «Мозг» макета: простые правила вместо настоящей модели.
 * Здесь только демонстрация: что Стив отвечает, какие статусы проходит и когда радуется.
 * В приложении для Mac ту же роль играет движок на устройстве.
 */
(function (app) {
  'use strict';

  const { $, wait } = app.dom;

  const STATUS_LABELS = {
    idle: 'Готов',
    listening: 'Слушает',
    thinking: 'Думает',
    working: 'Выполняет',
    speaking: 'Выполняет', // пока Стив отправляет ответ, статус остаётся «Выполняет»
  };
  const STEP_MS = { listen: 900, think: 1100, work: 900, speak: 1800 };

  /** Слова-триггеры: только на них Стив радуется. */
  const JOY_WORDS = /спасибо|благодар|пожалуйста|молодец|умница|умничка|супер|отлично|круто|классно|thank|good job|well done/i;

  const FALLBACK_REPLY = 'Я пока тестовый макет, но в настоящей версии отвечу на это сам, офлайн.';

  const minutesIn = (text) => Number((text.match(/(\d+)\s*мин/) || [0, 5])[1]);
  const percentIn = (text) => Number((text.match(/(\d+)\s*%/) || [0, 30])[1]);

  /** Правила проверяются сверху вниз, срабатывает первое подходящее. */
  const RULES = [
    { match: /спасибо|благодар|thank/i, reply: 'да не за что' },
    { match: /пожалуйста/i, reply: 'обращайся' },
    { match: /молодец|умница|умничка|супер|отлично|круто|классно|good job|well done/i, reply: 'ага, стараюсь' },
    {
      match: /календар|событи|23 нояб/i,
      reply: 'Добавил в «Календарь» событие «Зал»: 23 ноября, 17:00–19:00.',
      tool: () => 'Calendar.create_event(title="Зал", start="2026-11-23 17:00", end="2026-11-23 19:00")',
    },
    {
      match: /секундомер|stopwatch/i,
      reply: 'Запустил секундомер в «Часах».',
      tool: () => 'Clock.start_stopwatch()',
    },
    {
      match: /таймер|timer/i,
      reply: 'Поставил таймер в «Часах». Скажу, когда сработает.',
      tool: (text) => `Clock.start_timer(seconds=${minutesIn(text) * 60})`,
    },
    {
      match: /заметк|запиши|note/i,
      reply: 'Создал заметку в «Заметках».',
      tool: () => 'Notes.create_note(text="…")',
    },
    {
      match: /громк|тише|громче/i,
      reply: (text) => `громкость ${percentIn(text)}%`,
      tool: (text) => `set_volume(percent=${percentIn(text)})`,
    },
    { match: /safari|открой|open/i, reply: 'Открываю Safari.', tool: () => 'open_app(name="Safari")' },
    { match: /врем|час|time/i, reply: 'Сейчас 16:40, воскресенье.', tool: () => 'get_time()' },
    { match: /батаре|заряд|battery/i, reply: 'Заряд 87%, ноутбук не на зарядке.', tool: () => 'battery()' },
  ];

  let status = 'idle';
  let busy = false;

  function setStatus(next) {
    status = next;
    const label = STATUS_LABELS[next];
    $('#status-main').textContent = label;
    $('#status-popover').textContent = label;
    ['#orb-main', '#orb-popover'].forEach((selector) => {
      $(selector).classList.toggle('is-listening', next === 'listening');
    });
    app.character.setStatus(next);
  }

  function respond(text) {
    const rule = RULES.find((candidate) => candidate.match.test(text));
    if (!rule) return { text: FALLBACK_REPLY };
    return {
      text: typeof rule.reply === 'function' ? rule.reply(text) : rule.reply,
      tool: rule.tool ? rule.tool(text) : null,
    };
  }

  /**
   * Полный цикл ответа: слушает, думает, выполняет, отвечает.
   * Если текст набран с клавиатуры, Стив уже «слушал» во время набора, поэтому пауза не нужна.
   */
  async function ask(text, { typed = false } = {}) {
    if (busy) return;
    busy = true;
    app.idle.touch();

    setStatus('listening');
    if (!typed) await wait(STEP_MS.listen);
    app.chat.addMessage({ from: 'user', text });

    setStatus('thinking');
    await wait(STEP_MS.think);
    const answer = respond(text);

    if (answer.tool) {
      setStatus('working');
      await wait(STEP_MS.work);
    }
    app.chat.addMessage({ from: 'steve', text: answer.text, tool: answer.tool });
    app.voice.speak(answer.text);

    setStatus('speaking');
    if (JOY_WORDS.test(text)) app.character.play('happy');
    await wait(STEP_MS.speak);

    setStatus('idle');
    busy = false;
  }

  /** Пока человек печатает, Стив «слушает». */
  function typing(hasText) {
    if (!busy) setStatus(hasText ? 'listening' : 'idle');
  }

  app.assistant = {
    ask,
    typing,
    setStatus,
    isBusy: () => busy,
    get status() { return status; },
  };
})(window.SteveApp = window.SteveApp || {});

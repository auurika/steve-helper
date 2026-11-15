/**
 * Голос Стива: выбор голоса, свой голос из файла и озвучивание ответов.
 *
 * В списке голоса системы. Последний пункт «Добавить свой голос…» открывает выбор файла:
 * Стив измеряет тон голоса в записи и говорит системным голосом с тем же тоном.
 * Полноценное клонирование голоса требует отдельной модели, поэтому в макете это приближение.
 * В приложении для Mac в списке также будет «Личный голос» из настроек macOS.
 */
(function (app) {
  'use strict';

  const { $, escapeHtml, clamp } = app.dom;

  const SAMPLE = 'Привет, меня зовут Стив';
  const ADD_VALUE = '__add__';
  const CUSTOM_PREFIX = 'custom:';
  const FALLBACK_VOICES = ['Милена (рус)', 'Юрий (рус)', 'Samantha (en)'];

  // оценка тона: границы человеческого голоса и «обычный» тон, которому соответствует pitch = 1
  const PITCH_RANGE_HZ = { min: 70, max: 400 };
  const REFERENCE_HZ = 150;
  const FRAME = 2048;
  const MAX_ANALYZED_SECONDS = 30;

  const hasSynthesis = 'speechSynthesis' in window;
  let systemVoices = [];
  let customVoices = app.store.read('customVoices', []); // { id, name, hz }
  let lastChoice = '';

  /* ---------- текст для озвучки ---------- */
  /** Убирает то, что синтезатор прочитал бы вслух: кавычки, скобки, значки разметки, эмодзи. */
  function speechText(text) {
    return String(text)
      .replace(/\p{Extended_Pictographic}/gu, ' ')
      .replace(/[«»“”„‟"`]/g, '')
      .replace(/(?<!\p{L})['‘’]|['‘’](?!\p{L})/gu, '')
      .replace(/[*_#~|\\^<>[\]{}()]/g, ' ')
      .replace(/[→←↑↓•·]/g, ' ')
      .replace(/…/g, ',')
      .replace(/\s+[—–]\s+/g, ', ')
      .replace(/\s+([.,!?:;])/g, '$1')
      .replace(/\s+/g, ' ')
      .trim();
  }

  /* ---------- оценка тона голоса из файла ---------- */
  /** Автокорреляция по кадрам: находит основной тон (Гц) и берёт медиану по записи. */
  function estimatePitch(samples, sampleRate) {
    const minLag = Math.floor(sampleRate / PITCH_RANGE_HZ.max);
    const maxLag = Math.floor(sampleRate / PITCH_RANGE_HZ.min);
    const limit = Math.min(samples.length, sampleRate * MAX_ANALYZED_SECONDS);
    const estimates = [];

    for (let start = 0; start + FRAME + maxLag < limit; start += FRAME) {
      let energy = 0;
      for (let i = 0; i < FRAME; i += 1) energy += samples[start + i] ** 2;
      if (energy / FRAME < 1e-4) continue; // тишина

      const correlation = [];
      let max = 0;
      for (let lag = minLag; lag <= maxLag; lag += 1) {
        let sum = 0;
        for (let i = 0; i < FRAME; i += 1) sum += samples[start + i] * samples[start + i + lag];
        correlation.push(sum);
        if (sum > max) max = sum;
      }
      // самый короткий период с почти максимальной корреляцией: так не путаем тон с его октавой ниже
      const index = correlation.findIndex((sum, i) =>
        sum >= max * 0.9 && sum >= (correlation[i - 1] ?? 0) && sum >= (correlation[i + 1] ?? 0));
      const bestLag = index === -1 ? 0 : minLag + index;
      const best = max;
      // берём только уверенные кадры: пик корреляции должен быть заметным
      if (bestLag && best / energy > 0.3) estimates.push(sampleRate / bestLag);
    }

    if (!estimates.length) return null;
    estimates.sort((a, b) => a - b);
    return estimates[Math.floor(estimates.length / 2)];
  }

  async function analyzeFile(file) {
    const context = new (window.AudioContext || window.webkitAudioContext)();
    try {
      const buffer = await context.decodeAudioData(await file.arrayBuffer());
      return estimatePitch(buffer.getChannelData(0), buffer.sampleRate);
    } finally {
      context.close();
    }
  }

  /* ---------- список голосов ---------- */
  function findSystemVoices() {
    if (!hasSynthesis) return [];
    const wanted = speechSynthesis.getVoices().filter((voice) => /^(ru|en)/i.test(voice.lang));
    return wanted.sort((a, b) => Number(b.lang.startsWith('ru')) - Number(a.lang.startsWith('ru')));
  }

  function option(value, label) {
    return `<option value="${escapeHtml(value)}">${escapeHtml(label)}</option>`;
  }

  function renderSelect() {
    systemVoices = findSystemVoices();
    const select = $('#voice-select');

    const system = systemVoices.length
      ? systemVoices.map((voice) => option(voice.name, `${voice.name} (${voice.lang})`))
      : FALLBACK_VOICES.map((name) => option(name, name));
    const custom = customVoices.map((voice) => option(CUSTOM_PREFIX + voice.id, `Свой: ${voice.name} (${Math.round(voice.hz)} Гц)`));

    select.innerHTML = [...system, ...custom, option(ADD_VALUE, 'Добавить свой голос…')].join('');

    const saved = app.store.read('voice', '');
    if ([...select.options].some((item) => item.value === saved)) select.value = saved;
    lastChoice = select.value;
  }

  /** Какой системный голос и какой тон использовать для выбранного пункта. */
  function currentVoice() {
    const value = $('#voice-select').value;
    const custom = customVoices.find((voice) => CUSTOM_PREFIX + voice.id === value);
    const base = systemVoices.find((voice) => voice.lang.startsWith('ru')) || systemVoices[0] || null;
    if (custom) {
      return { voice: base, pitch: clamp(custom.hz / REFERENCE_HZ, 0.5, 2) };
    }
    return { voice: systemVoices.find((voice) => voice.name === value) || null, pitch: 1 };
  }

  /* ---------- озвучка ---------- */
  function say(text) {
    const clean = speechText(text);
    if (!hasSynthesis || !clean) return;
    // cancel() на уже замолчавшем синтезаторе даёт в Chrome щелчок, поэтому прерываем только живую речь
    if (speechSynthesis.speaking || speechSynthesis.pending) speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(clean);
    const { voice, pitch } = currentVoice();
    if (voice) utterance.voice = voice;
    if (pitch !== 1) utterance.pitch = pitch; // тон трогаем только для своего голоса
    utterance.lang = /[а-яё]/i.test(clean) ? 'ru-RU' : 'en-US';
    speechSynthesis.speak(utterance);
  }

  /** Озвучивает ответ, если озвучка включена в настройках. */
  function speak(text) {
    if (app.settings.isOn('speak')) say(text);
  }

  /* ---------- добавление своего голоса ---------- */
  function setNote(text) {
    const note = $('#voice-note');
    note.textContent = text;
    note.hidden = !text;
  }

  async function addFromFile(file) {
    setNote('Слушаю запись…');
    try {
      const hz = await analyzeFile(file);
      if (!hz) return setNote('В записи не слышно голоса. Попробуйте другой файл.');
      const id = String(Date.now());
      customVoices = [...customVoices, { id, name: file.name.replace(/\.[^.]+$/, ''), hz }];
      app.store.write('customVoices', customVoices);
      app.store.write('voice', CUSTOM_PREFIX + id);
      renderSelect();
      setNote(`Тон вашего голоса: ${Math.round(hz)} Гц. Стив говорит с этим тоном.`);
      say(SAMPLE);
    } catch (error) {
      setNote('Не удалось прочитать файл. Подойдёт аудио: mp3, wav, m4a.');
    }
  }

  function init() {
    renderSelect();
    if (hasSynthesis) speechSynthesis.addEventListener('voiceschanged', renderSelect);

    $('#voice-select').addEventListener('change', (event) => {
      if (event.target.value === ADD_VALUE) {
        event.target.value = lastChoice; // пункт «Добавить» не остаётся выбранным
        $('#voice-file').click();
        return;
      }
      lastChoice = event.target.value;
      app.store.write('voice', lastChoice);
      setNote('');
      say(SAMPLE); // сразу даём послушать, чтобы было слышно, что голос применился
    });

    $('#voice-file').addEventListener('change', (event) => {
      const [file] = event.target.files;
      event.target.value = '';
      if (file) addFromFile(file);
    });
  }

  app.voice = { init, speak, speechText };
})(window.SteveApp = window.SteveApp || {});

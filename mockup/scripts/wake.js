/**
 * Слово активации: фраза и три записи голоса для лучшего распознавания.
 * В макете запись имитируется анимацией волны, в приложении для Mac пишется настоящий звук.
 */
(function (app) {
  'use strict';

  const { $, $$ } = app.dom;

  const SAMPLES_NEEDED = 3;
  const WAVE_BARS = 28;
  const RECORD_TICKS = 22;
  const DEFAULT_PHRASE = 'Привет, Стив';

  let phrase = DEFAULT_PHRASE;
  let recorded = 0;
  let recordTimer = null;

  const waveBars = () => $$('#wake-wave i');
  const quote = (text) => `«${text}»`;

  function setHint(text) {
    $('#wake-hint').textContent = text;
  }

  function resetWave() {
    $('#wake-wave').classList.remove('is-recording');
    waveBars().forEach((bar) => { bar.style.height = '6px'; });
  }

  function resetSamples() {
    recorded = 0;
    $$('.sample').forEach((sample, index) => {
      sample.className = index === 0 ? 'sample is-current' : 'sample';
      sample.textContent = `${index + 1} · ожидает`;
    });
    $('#wake-save').disabled = true;
    $('#wake-record').disabled = false;
    $('#wake-big').textContent = quote($('#wake-input').value);
    setHint(`Образец 1 из ${SAMPLES_NEEDED} — нажми «Записать» и произнеси:`);
  }

  function finishSample() {
    clearInterval(recordTimer);
    recordTimer = null;
    resetWave();

    const sample = $$('.sample')[recorded];
    sample.className = 'sample is-done';
    sample.textContent = `${recorded + 1} · готово`;
    recorded += 1;

    if (recorded < SAMPLES_NEEDED) {
      $$('.sample')[recorded].classList.add('is-current');
      $('#wake-record').disabled = false;
      setHint(`Образец ${recorded + 1} из ${SAMPLES_NEEDED} — произнеси ещё раз:`);
    } else {
      $('#wake-save').disabled = false;
      setHint('Все образцы записаны. Сохрани, чтобы применить.');
    }
  }

  function record() {
    if (recordTimer || recorded >= SAMPLES_NEEDED) return;
    $('#wake-wave').classList.add('is-recording');
    $('#wake-record').disabled = true;
    setHint('Говори сейчас…');

    let ticks = 0;
    recordTimer = setInterval(() => {
      waveBars().forEach((bar) => { bar.style.height = `${6 + Math.random() * 28}px`; });
      if (++ticks > RECORD_TICKS) finishSample();
    }, 90);
  }

  /** Закрыли окно посреди записи: сбрасываем таймер, иначе следующая запись зависнет. */
  function cancelRecording() {
    clearInterval(recordTimer);
    recordTimer = null;
    resetWave();
  }

  function init() {
    phrase = app.store.read('wakePhrase', DEFAULT_PHRASE);
    $('#wake-phrase').textContent = quote(phrase);

    const wave = $('#wake-wave');
    for (let i = 0; i < WAVE_BARS; i += 1) wave.append(document.createElement('i'));

    $('#wake-edit').addEventListener('click', () => {
      $('#wake-input').value = phrase;
      resetSamples();
      app.dialogs.open('wake');
    });
    $('#wake-input').addEventListener('input', resetSamples);
    $('#wake-record').addEventListener('click', record);
    $('#wake-save').addEventListener('click', () => {
      phrase = $('#wake-input').value.trim() || DEFAULT_PHRASE;
      app.store.write('wakePhrase', phrase);
      $('#wake-phrase').textContent = quote(phrase);
      app.dialogs.close('wake');
    });
    document.addEventListener('dialog:close', (event) => {
      if (event.detail === 'wake') cancelRecording();
    });
  }

  app.wake = { init };
})(window.SteveApp = window.SteveApp || {});

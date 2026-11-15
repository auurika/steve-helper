/**
 * Жизнь Стива в покое:
 *  - моргает примерно раз в 3-6 секунд;
 *  - раз в 40 секунд делает что-нибудь ещё (смотрит по сторонам, прыгает, машет, зевает);
 *  - после 5 минут без запросов засыпает.
 * Для проверки время можно сократить в адресе: ?sleep=10&idle=5 (секунды).
 */
(function (app) {
  'use strict';

  const params = new URLSearchParams(location.search);
  const seconds = (name, fallback) => (Number(params.get(name)) || fallback) * 1000;

  const settings = {
    sleepAfter: seconds('sleep', 300),
    idleEvery: seconds('idle', 40),
    blinkEvery: 3000,
    blinkSpread: 3000,
  };

  const IDLE_ANIMATIONS = [
    'look-left', 'look-left', 'look-right', 'look-right', 'look-around', 'look-around',
    'hop', 'hop', 'wiggle', 'wiggle', 'wave', 'yawn',
  ];
  const YAWN_BEFORE_SLEEP_MS = 60000;

  let lastActivity = Date.now();
  let isBusy = () => false;

  /** Любой запрос к Стиву: будит его и сбрасывает таймер сна. */
  function touch() {
    app.character.wake();
    lastActivity = Date.now();
  }

  const character = () => app.character;
  const canPlayIdle = () => !character().isAsleep && !character().current && !isBusy();

  function scheduleBlink() {
    setTimeout(() => {
      if (canPlayIdle() && document.visibilityState === 'visible') character().play('blink');
      scheduleBlink();
    }, settings.blinkEvery + Math.random() * settings.blinkSpread);
  }

  function scheduleDirector() {
    setTimeout(() => {
      if (canPlayIdle()) {
        const untilSleep = settings.sleepAfter - (Date.now() - lastActivity);
        const yawnNow = untilSleep < YAWN_BEFORE_SLEEP_MS && Math.random() < 0.5;
        const pick = IDLE_ANIMATIONS[Math.floor(Math.random() * IDLE_ANIMATIONS.length)];
        character().play(yawnNow ? 'yawn' : pick);
      }
      scheduleDirector();
    }, settings.idleEvery);
  }

  function watchSleepTimer() {
    setInterval(() => {
      const idleFor = Date.now() - lastActivity;
      if (!character().isAsleep && !character().isHolding && !isBusy() && idleFor > settings.sleepAfter) {
        character().sleep();
      }
    }, 500);
  }

  /** busyCheck сообщает, занят ли ассистент: тогда Стив не отвлекается на моргание и сон. */
  function start(busyCheck) {
    isBusy = busyCheck;
    scheduleBlink();
    scheduleDirector();
    watchSleepTimer();
  }

  /** Сколько миллисекунд осталось до сна (для счётчика на странице анимаций). */
  const remaining = () => Math.max(0, settings.sleepAfter - (Date.now() - lastActivity));

  app.idle = { start, touch, remaining, settings };
})(window.SteveApp = window.SteveApp || {});

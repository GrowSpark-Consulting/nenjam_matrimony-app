/** The instant [freezeClock] pins `new Date()` to. */
export const FROZEN_NOW = new Date('2026-09-22T00:00:00.000Z');

/**
 * Pins `new Date()` for the rest of the spec file. Call it at the top level of
 * the file: it takes effect immediately — so expectations built while the file
 * is being collected see the frozen clock too — and is undone after the file's
 * last test (Jest isolates each file, so nothing leaks into other files).
 *
 * Only `Date` is faked — timers, microtasks and nextTick stay real, so async
 * code under test runs normally.
 *
 * Needed wherever a spec compares WHEREs built at different moments: the
 * eligibility rules embed the current time (subscription expiry), so two
 * otherwise-identical filters built a millisecond apart would not be equal.
 */
export function freezeClock(now: Date = FROZEN_NOW): void {
  jest.useFakeTimers({
    now,
    doNotFake: [
      'hrtime',
      'nextTick',
      'performance',
      'queueMicrotask',
      'requestAnimationFrame',
      'cancelAnimationFrame',
      'requestIdleCallback',
      'cancelIdleCallback',
      'setImmediate',
      'clearImmediate',
      'setInterval',
      'clearInterval',
      'setTimeout',
      'clearTimeout',
    ],
  });
  afterAll(() => {
    jest.useRealTimers();
  });
}

import {
  PsychologyCircuitBreaker,
  PsychologyTimeoutError,
  withTimeout,
} from '../scoring/psychology/psychology-fail-open';

describe('withTimeout', () => {
  it('resolves with the value when the promise settles in time', async () => {
    await expect(withTimeout(Promise.resolve(42), 100)).resolves.toBe(42);
  });

  it('propagates the original rejection when it fails in time', async () => {
    await expect(
      withTimeout(Promise.reject(new Error('boom')), 100),
    ).rejects.toThrow('boom');
  });

  it('rejects with PsychologyTimeoutError when the promise outruns the budget', async () => {
    await expect(
      withTimeout(new Promise(() => undefined), 20),
    ).rejects.toBeInstanceOf(PsychologyTimeoutError);
  });

  it('clears its timer once the promise settles, so nothing is left pending', async () => {
    const clear = jest.spyOn(global, 'clearTimeout');
    await withTimeout(Promise.resolve(1), 10_000);
    expect(clear).toHaveBeenCalled();
    clear.mockRestore();
  });
});

describe('PsychologyCircuitBreaker', () => {
  it('starts closed and allows calls', () => {
    expect(new PsychologyCircuitBreaker().allow()).toBe(true);
  });

  it('opens after the threshold of consecutive failures', () => {
    const b = new PsychologyCircuitBreaker(3, 1000);
    b.recordFailure(0);
    b.recordFailure(0);
    expect(b.allow(0)).toBe(true);
    b.recordFailure(0);
    expect(b.isOpen).toBe(true);
    expect(b.allow(500)).toBe(false);
  });

  it('lets one trial through after the cool-down, and re-opens if it fails', () => {
    const b = new PsychologyCircuitBreaker(2, 1000);
    b.recordFailure(0);
    b.recordFailure(0);
    expect(b.allow(1000)).toBe(true);
    b.recordFailure(1000);
    expect(b.allow(1500)).toBe(false);
    expect(b.allow(2000)).toBe(true);
  });

  it('closes on success', () => {
    const b = new PsychologyCircuitBreaker(2, 1000);
    b.recordFailure(0);
    b.recordFailure(0);
    b.recordSuccess();
    expect(b.isOpen).toBe(false);
    expect(b.allow(1)).toBe(true);
  });

  it('a success resets the consecutive count', () => {
    const b = new PsychologyCircuitBreaker(3, 1000);
    b.recordFailure(0);
    b.recordFailure(0);
    b.recordSuccess();
    b.recordFailure(0);
    b.recordFailure(0);
    expect(b.isOpen).toBe(false);
  });
});

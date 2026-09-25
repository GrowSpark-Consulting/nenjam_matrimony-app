import configuration from './configuration';
import { validationSchema } from './validation';

describe('psychology config', () => {
  const originalEnv = process.env;
  beforeEach(() => {
    process.env = { ...originalEnv };
    delete process.env.PSYCHOLOGY_MATCHING_ENABLED;
    delete process.env.PSYCHOLOGY_TIMEOUT_MS;
  });
  afterAll(() => {
    process.env = originalEnv;
  });

  it('defaults to enabled with an 800ms budget', () => {
    expect(configuration().psychology).toEqual({
      enabled: true,
      timeoutMs: 800,
      retakeCooldownDays: 7,
    });
  });

  it('PSYCHOLOGY_MATCHING_ENABLED=false is the kill switch; anything else keeps it on', () => {
    process.env.PSYCHOLOGY_MATCHING_ENABLED = 'false';
    expect(configuration().psychology.enabled).toBe(false);
    process.env.PSYCHOLOGY_MATCHING_ENABLED = 'true';
    expect(configuration().psychology.enabled).toBe(true);
  });

  it('reads the time budget, falling back to the default when blank or not a number', () => {
    process.env.PSYCHOLOGY_TIMEOUT_MS = '1200';
    expect(configuration().psychology.timeoutMs).toBe(1200);
    process.env.PSYCHOLOGY_TIMEOUT_MS = '';
    expect(configuration().psychology.timeoutMs).toBe(800);
    process.env.PSYCHOLOGY_TIMEOUT_MS = 'soon';
    expect(configuration().psychology.timeoutMs).toBe(800);
  });

  it('reads the retake cooldown; 0 disables it; junk falls back to the default', () => {
    delete process.env.PSYCHOLOGY_RETAKE_COOLDOWN_DAYS;
    expect(configuration().psychology.retakeCooldownDays).toBe(7);
    process.env.PSYCHOLOGY_RETAKE_COOLDOWN_DAYS = '0';
    expect(configuration().psychology.retakeCooldownDays).toBe(0);
    process.env.PSYCHOLOGY_RETAKE_COOLDOWN_DAYS = '14';
    expect(configuration().psychology.retakeCooldownDays).toBe(14);
    process.env.PSYCHOLOGY_RETAKE_COOLDOWN_DAYS = 'soon';
    expect(configuration().psychology.retakeCooldownDays).toBe(7);
  });

  describe('validation', () => {
    const timeout = validationSchema.extract('PSYCHOLOGY_TIMEOUT_MS');
    const enabled = validationSchema.extract('PSYCHOLOGY_MATCHING_ENABLED');

    it('both are optional', () => {
      expect(timeout.validate(undefined).error).toBeUndefined();
      expect(enabled.validate(undefined).error).toBeUndefined();
    });

    it.each(['0', '49', '5001', '-1', 'fast', '1.5'])(
      'rejects a timeout of %s',
      (raw) => {
        expect(timeout.validate(raw).error).toBeDefined();
      },
    );

    it.each(['50', '800', '5000'])('accepts a timeout of %s', (raw) => {
      expect(timeout.validate(raw).error).toBeUndefined();
    });

    it.each(['-1', '366', 'often', '1.5'])(
      'rejects a retake cooldown of %s',
      (raw) => {
        expect(
          validationSchema
            .extract('PSYCHOLOGY_RETAKE_COOLDOWN_DAYS')
            .validate(raw).error,
        ).toBeDefined();
      },
    );

    it('rejects a non-boolean kill switch', () => {
      expect(enabled.validate('maybe').error).toBeDefined();
      expect(enabled.validate('false').error).toBeUndefined();
    });
  });
});

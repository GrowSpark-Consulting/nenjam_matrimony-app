import { BadRequestException } from '@nestjs/common';
import type { PrismaService } from '@app/database';
import {
  OTP_POLICY,
  OtpDeliveryUnavailableError,
  OtpRateLimitError,
} from '../../../platform/otp/otp.service';
import { PlatformSettingsService } from '../../../platform/settings/platform-settings.service';
import { AgentServiceError } from '../../errors/agent-service-error';
import { AgentOtpRateLimitError } from '../../ports/agent-platform-ports';
import {
  AGENT_PROGRAM_SETTING_KEYS,
  parseAgentProgramSettings,
} from '../../settings/agent-program-settings';
import {
  AgentSettingValidators,
  agentSettingValidator,
  OTP_SERVICE_RESEND_FLOOR_SECONDS,
  PlatformOtpAdapter,
  PlatformSettingsAdapter,
} from './agent-platform.adapters';

const PHONE = '+919000000001';

/** The rejection reason, typed as unknown (never any). */
const caught = (error: unknown): unknown => error;

describe('PlatformSettingsAdapter (over PlatformSettingsService.getMany)', () => {
  it('asks for exactly the keys given and returns his answer untouched', async () => {
    const getMany = jest
      .fn()
      .mockResolvedValue({ 'commission.auto_approve': true });
    const adapter = new PlatformSettingsAdapter({ getMany });
    await expect(
      adapter.getMany(['commission.auto_approve', 'payout.tax_withholding']),
    ).resolves.toEqual({ 'commission.auto_approve': true });
    expect(getMany).toHaveBeenCalledWith([
      'commission.auto_approve',
      'payout.tax_withholding',
    ]);
  });
});

describe('PlatformOtpAdapter (over OtpService)', () => {
  const send = jest.fn();
  const verify = jest.fn();
  const adapter = new PlatformOtpAdapter({
    send,
    verify,
  });

  beforeEach(() => {
    send.mockReset();
    verify.mockReset();
  });

  it('sends for the purpose and phone, returning only the challenge', async () => {
    const expiresAt = new Date('2026-10-29T10:05:00Z');
    send.mockResolvedValue({ challengeId: 'c-1', expiresAt, extra: 'x' });
    await expect(adapter.send('AGENT_SIGN_IN', PHONE)).resolves.toEqual({
      challengeId: 'c-1',
      expiresAt,
    });
    expect(send).toHaveBeenCalledWith('AGENT_SIGN_IN', PHONE);
  });

  it('turns his OtpRateLimitError into AgentOtpRateLimitError with the same wait', async () => {
    send.mockRejectedValue(new OtpRateLimitError(17));
    const error = await adapter.send('AGENT_SIGN_IN', PHONE).catch(caught);
    expect(error).toBeInstanceOf(AgentOtpRateLimitError);
    expect((error as AgentOtpRateLimitError).retryAfterSeconds).toBe(17);
  });

  it('never reports a wait below one second', async () => {
    send.mockRejectedValue(new OtpRateLimitError(0));
    const error = await adapter.send('AGENT_SIGN_IN', PHONE).catch(caught);
    expect((error as AgentOtpRateLimitError).retryAfterSeconds).toBe(1);
  });

  it('turns his RangeError (not an E.164 phone) into VALIDATION_FAILED on phone', async () => {
    send.mockRejectedValue(
      new RangeError('phoneE164 must be an E.164 number.'),
    );
    const error = await adapter.send('AGENT_SIGN_IN', 'nope').catch(caught);
    expect(error).toBeInstanceOf(AgentServiceError);
    expect((error as AgentServiceError).code).toBe('VALIDATION_FAILED');
    expect((error as AgentServiceError).fields).toEqual(['phone']);
  });

  it('lets his 503 and any other error through unchanged', async () => {
    const unavailable = new OtpDeliveryUnavailableError();
    send.mockRejectedValueOnce(unavailable);
    await expect(adapter.send('AGENT_SIGN_IN', PHONE)).rejects.toBe(
      unavailable,
    );
    const boom = new Error('database down');
    send.mockRejectedValueOnce(boom);
    await expect(adapter.send('AGENT_SIGN_IN', PHONE)).rejects.toBe(boom);
  });

  it('verifies for the purpose and passes his result through', async () => {
    verify.mockResolvedValueOnce({ ok: true, phoneE164: PHONE });
    await expect(
      adapter.verify('AGENT_SIGN_IN', 'c-1', '123456'),
    ).resolves.toEqual({ ok: true, phoneE164: PHONE });
    expect(verify).toHaveBeenCalledWith('AGENT_SIGN_IN', 'c-1', '123456');
    verify.mockResolvedValueOnce({ ok: false, reason: 'EXPIRED' });
    await expect(
      adapter.verify('AGENT_SIGN_IN', 'c-1', '123456'),
    ).resolves.toEqual({ ok: false, reason: 'EXPIRED' });
  });
});

describe('agentSettingValidator', () => {
  it('accepts what the parser accepts, and refuses what it refuses', () => {
    expect(agentSettingValidator('commission.auto_approve')(true)).toBeNull();
    expect(agentSettingValidator('commission.auto_approve')('yes')).toMatch(
      /must be a boolean/,
    );
    expect(
      agentSettingValidator('referral.member_discount_bps')(500),
    ).toBeNull();
    expect(
      agentSettingValidator('referral.member_discount_bps')(10_001),
    ).toMatch(/0 to 10000/);
    expect(
      agentSettingValidator('commission.base')('AMOUNT_PAID_EXCLUDING_GST'),
    ).toBeNull();
    expect(agentSettingValidator('commission.base')('GROSS')).not.toBeNull();
  });

  it('refuses null except where null is a real value ("not decided")', () => {
    expect(agentSettingValidator('payout.tax_withholding')(null)).toBeNull();
    expect(agentSettingValidator('commission.base')(null)).toBeNull();
    expect(agentSettingValidator('payout.minimum_amount_paise')(null)).toMatch(
      /must be an integer >= 0/,
    );
    expect(
      agentSettingValidator('commission.auto_approve')(null),
    ).not.toBeNull();
  });

  it('the OTP resend time may not be shorter than the OTP service enforces', () => {
    const resend = agentSettingValidator('agent.otp_resend_after_seconds');
    expect(OTP_SERVICE_RESEND_FLOOR_SECONDS).toBe(
      Math.ceil(OTP_POLICY.resendAfterMs / 1000),
    );
    expect(resend(OTP_SERVICE_RESEND_FLOOR_SECONDS)).toBeNull();
    expect(resend(OTP_SERVICE_RESEND_FLOOR_SECONDS - 1)).toMatch(/at least/);
    expect(resend(0)).toMatch(/integer >= 1/);
    // The floor applies to this key only.
    expect(
      agentSettingValidator('agent.access_token_ttl_seconds')(1),
    ).toBeNull();
  });

  it('agrees with parseAgentProgramSettings on every key for a sample of values', () => {
    const samples: unknown[] = [true, false, 0, 1, 30, 500, -1, 1.5, 'x', {}];
    for (const key of AGENT_PROGRAM_SETTING_KEYS) {
      for (const value of samples) {
        let parserOk = true;
        try {
          parseAgentProgramSettings({ [key]: value });
        } catch {
          parserOk = false;
        }
        const extraFloor =
          key === 'agent.otp_resend_after_seconds' &&
          typeof value === 'number' &&
          value < OTP_SERVICE_RESEND_FLOOR_SECONDS;
        expect([
          key,
          value,
          agentSettingValidator(key)(value) === null,
        ]).toEqual([key, value, parserOk && !extraFloor]);
      }
    }
  });

  it('a key that is not ours is a programming error', () => {
    expect(() => agentSettingValidator('payment.gst_rate_bps')(0)).toThrow(
      RangeError,
    );
  });
});

describe('AgentSettingValidators (registered with the real PlatformSettingsService)', () => {
  const transaction = jest.fn();
  const settings = new PlatformSettingsService({
    $transaction: transaction,
  } as unknown as PrismaService);
  new AgentSettingValidators(settings).onModuleInit();

  beforeEach(() => transaction.mockReset());

  it('registers a validator for every one of the 18 keys', () => {
    expect(AGENT_PROGRAM_SETTING_KEYS).toHaveLength(18);
    for (const key of AGENT_PROGRAM_SETTING_KEYS) {
      expect(() => settings.registerValidator(key, () => null)).toThrow(
        /already registered/,
      );
    }
  });

  it('an admin entering a bad value is refused with 400 before any database work', async () => {
    const error = await settings
      .update({
        key: 'payout.minimum_amount_paise',
        value: 'five hundred',
        expectedVersion: 1,
        reason: 'Testing a bad value.',
        actorId: 'user-1',
      })
      .catch(caught);
    expect(error).toBeInstanceOf(BadRequestException);
    expect(transaction).not.toHaveBeenCalled();
  });

  it('a good value goes on to his update', async () => {
    transaction.mockResolvedValue('updated');
    await expect(
      settings.update({
        key: 'agent.otp_resend_after_seconds',
        value: OTP_SERVICE_RESEND_FLOOR_SECONDS,
        expectedVersion: 1,
        reason: 'Testing a good value.',
        actorId: 'user-1',
      }),
    ).resolves.toBe('updated');
  });
});

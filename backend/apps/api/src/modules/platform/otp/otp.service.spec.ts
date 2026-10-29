import { Logger } from '@nestjs/common';
import type { AppConfigService } from '@app/config';
import type { PrismaService } from '@app/database';
import {
  OTP_POLICY,
  OtpDeliveryUnavailableError,
  OtpService,
  sendRetryAfterMs,
} from './otp.service';

const now = new Date('2026-10-29T10:00:00Z');
const ago = (ms: number) => new Date(now.getTime() - ms);

describe('sendRetryAfterMs', () => {
  it('allows the first send', () => {
    expect(sendRetryAfterMs([], now)).toBe(0);
  });

  it('makes a resend wait out the gap', () => {
    expect(sendRetryAfterMs([ago(10_000)], now)).toBe(
      OTP_POLICY.resendAfterMs - 10_000,
    );
    expect(sendRetryAfterMs([ago(OTP_POLICY.resendAfterMs)], now)).toBe(0);
  });

  it('caps sends per window until the oldest counted one ages out', () => {
    const sends = [50, 40, 30, 20, 10].map((min) => ago(min * 60_000));
    expect(sendRetryAfterMs(sends, now)).toBe(10 * 60_000);
    expect(sendRetryAfterMs(sends.slice(1), now)).toBe(0);
  });
});

describe('OtpService delivery (dummy mode)', () => {
  const phone = '+919876543210';
  const build = (
    agentOtp: {
      dummyEnabled: boolean;
      dummyPhones: string[];
      dummyCode?: string;
    },
    isProduction = false,
  ) =>
    new OtpService(
      {} as PrismaService,
      { agentOtp, isProduction } as unknown as AppConfigService,
    );
  // Delivery is decided before anything touches the database.
  const refusesDelivery = (service: OtpService) =>
    expect(service.send('AGENT_SIGN_IN', phone)).rejects.toBeInstanceOf(
      OtpDeliveryUnavailableError,
    );

  beforeEach(() => {
    jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
  });

  it('refuses every phone while dummy mode is off (no SMS provider yet)', async () => {
    await refusesDelivery(build({ dummyEnabled: false, dummyPhones: [] }));
    await refusesDelivery(
      build({ dummyEnabled: true, dummyPhones: [] /* no code */ }),
    );
  });

  it('refuses phones outside the allow-list', async () => {
    await refusesDelivery(
      build({
        dummyEnabled: true,
        dummyPhones: ['+919000000001'],
        dummyCode: '123456',
      }),
    );
  });

  it('covers no phone in production when the allow-list is empty', async () => {
    await refusesDelivery(
      build({ dummyEnabled: true, dummyPhones: [], dummyCode: '123456' }, true),
    );
  });

  it('refuses a phone that is not E.164 with a RangeError', async () => {
    const service = build({
      dummyEnabled: true,
      dummyPhones: [],
      dummyCode: '123456',
    });
    await expect(
      service.send('AGENT_SIGN_IN', '9876543210'),
    ).rejects.toBeInstanceOf(RangeError);
  });

  it('never logs the dummy code', () => {
    const warn = jest.spyOn(Logger.prototype, 'warn');
    build({ dummyEnabled: true, dummyPhones: [phone], dummyCode: '424242' });
    build({ dummyEnabled: true, dummyPhones: [], dummyCode: '424242' });
    for (const [message] of warn.mock.calls) {
      expect(String(message)).not.toContain('424242');
      expect(String(message)).not.toContain(phone);
    }
  });
});

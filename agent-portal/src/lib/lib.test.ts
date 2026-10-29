import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { buildPayoutDetails } from '../pages/PayoutDetailsPage';
import { help } from './helpContent';
import { hasTamil, pickLabel } from './labels';
import { formatBasisPoints, formatPaise } from './money';
import { normalizeIndianPhone, normalizePan, stripSpacesAndHyphens } from './normalize';

describe('normalisation', () => {
  it('strips spaces and hyphens (referral codes, account numbers)', () => {
    expect(stripSpacesAndHyphens(' NM 7K2-P9X ')).toBe('NM7K2P9X');
    expect(stripSpacesAndHyphens('1234 5678-9012')).toBe('123456789012');
  });

  it('phone to E.164', () => {
    expect(normalizeIndianPhone('98765 43210')).toBe('+919876543210');
    expect(normalizeIndianPhone('+91 98765-43210')).toBe('+919876543210');
  });

  it('PAN upper-cased and trimmed', () => {
    expect(normalizePan(' abcde1234f ')).toBe('ABCDE1234F');
  });

  it('payout body: exactly one method, cleaned', () => {
    expect(
      buildPayoutDetails('UPI', { vpa: ' Ravi@OkBank ', holder: '', account: '', ifsc: '' }),
    ).toEqual({ upi: { vpa: 'ravi@okbank' } });
    expect(
      buildPayoutDetails('BANK', {
        vpa: '',
        holder: ' Ravi K ',
        account: '1234-5678 9012',
        ifsc: 'hdfc0001234',
      }),
    ).toEqual({
      bank: { accountHolderName: 'Ravi K', accountNumber: '123456789012', ifsc: 'HDFC0001234' },
    });
    expect(
      buildPayoutDetails('BANK', { vpa: '', holder: 'R', account: '12', ifsc: 'HDFC0001234' }),
    ).toBeNull();
    expect(
      buildPayoutDetails('UPI', { vpa: 'no-at-sign', holder: '', account: '', ifsc: '' }),
    ).toBeNull();
  });
});

describe('money', () => {
  it('paise to rupees', () => {
    expect(formatPaise(50000)).toBe('₹500.00');
    expect(formatPaise(9990)).toBe('₹99.90');
    expect(formatPaise(15000000)).toBe('₹1,50,000.00');
  });

  it('basis points', () => {
    expect(formatBasisPoints(1000)).toBe('10%');
  });
});

describe('labels from /agent/config', () => {
  it('pending Tamil falls back to English, never shows the placeholder', () => {
    const t = { en: 'Paused', ta: '<to be supplied>' };
    expect(pickLabel(t, 'SUSPENDED', 'ta')).toBe('Paused');
    expect(hasTamil(t)).toBe(false);
    expect(pickLabel(undefined, 'SUSPENDED')).toBe('SUSPENDED');
  });
});

describe('help content', () => {
  it('is the approved wording, pinned: any rewording fails here', () => {
    expect(help).toMatchSnapshot();
  });

  // The Flutter app shows the same approved text from its ARB (`partnerHelp*`
  // keys). When those keys are present in this checkout, both must match.
  const arbPath = resolve(__dirname, '../../../Frontend/lib/l10n/app_en.arb');
  const arb = JSON.parse(readFileSync(arbPath, 'utf8')) as Record<string, string>;
  it.runIf('partnerHelpTitle' in arb)('matches the app ARB word for word', () => {
    expect(help.title).toBe(arb.partnerHelpTitle);
    expect(help.welcome).toBe(arb.partnerHelpWelcome);
    expect(help.sections.map((s) => [s.title, s.body])).toEqual([
      [arb.partnerHelpGettingStartedTitle, arb.partnerHelpGettingStartedBody],
      [arb.partnerHelpReferringTitle, arb.partnerHelpReferringBody],
      [arb.partnerHelpTrackingTitle, arb.partnerHelpTrackingBody],
      [arb.partnerHelpBankTitle, arb.partnerHelpBankBody],
    ]);
    expect(help.termsTitle).toBe(arb.partnerHelpTermsTitle);
    expect(help.terms).toEqual([
      arb.partnerHelpTermNoFees,
      arb.partnerHelpTermNoFalsePromises,
      arb.partnerHelpTermNoSharing,
      arb.partnerHelpTermConsent,
    ]);
    expect(help.termsConsequence).toBe(arb.partnerHelpTermsConsequence);
    expect(help.needHelpTitle).toBe(arb.partnerHelpNeedHelpTitle);
    expect(help.contact).toBe(arb.partnerHelpContact);
    expect(help.otpWarning).toBe(arb.partnerHelpOtpWarning);
  });
});

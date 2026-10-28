import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/referral/domain/models/referral_models.dart';

void main() {
  group('normalizeReferralCode', () {
    test('accepts a well-formed code as typed', () {
      expect(normalizeReferralCode('NM7K2P9X'), 'NM7K2P9X');
    });

    test('removes spaces and hyphens and trims', () {
      expect(normalizeReferralCode('  NM 7K2 P9X '), 'NM7K2P9X');
      expect(normalizeReferralCode('NM-7K2-P9X'), 'NM7K2P9X');
      expect(normalizeReferralCode('nm - 7k2p - 9x'), 'NM7K2P9X');
    });

    test('upper-cases ASCII only', () {
      expect(normalizeReferralCode('nm7k2p9x'), 'NM7K2P9X');
      // The long s upper-cases to "S" in some runtimes; it is not a code.
      expect(normalizeReferralCode('NM7K2P9ſ'), isNull);
    });

    test('rejects malformed codes rather than correcting them', () {
      expect(normalizeReferralCode(''), isNull);
      expect(normalizeReferralCode('NM7K2P9'), isNull); // too short
      expect(normalizeReferralCode('NM7K2P9XX'), isNull); // too long
      expect(normalizeReferralCode('AB7K2P9X'), isNull); // wrong prefix
      expect(normalizeReferralCode('NM0K2P9X'), isNull); // 0 not allowed
      expect(normalizeReferralCode('NMOK2P9X'), isNull); // O not allowed
      expect(normalizeReferralCode('NM1K2P9X'), isNull); // 1 not allowed
      expect(normalizeReferralCode('NMIK2P9X'), isNull); // I not allowed
      expect(normalizeReferralCode('NMLK2P9X'), isNull); // L not allowed
      expect(normalizeReferralCode('NM7K2_9X'), isNull);
    });
  });

  group('ReferralCodeValidation.fromJson', () {
    test('valid with a name', () {
      final v = ReferralCodeValidation.fromJson({
        'valid': true,
        'agentDisplayName': 'Ravi K.',
      });
      expect(v.valid, isTrue);
      expect(v.agentDisplayName, 'Ravi K.');
    });

    test('invalid never carries a name', () {
      final v = ReferralCodeValidation.fromJson({
        'valid': false,
        'agentDisplayName': 'Ravi K.',
      });
      expect(v.valid, isFalse);
      expect(v.agentDisplayName, isNull);
    });

    test('a malformed body reads as invalid', () {
      final v = ReferralCodeValidation.fromJson({'valid': 'yes'});
      expect(v.valid, isFalse);
    });
  });

  test('ReferralAttachment.fromJson keeps the IST date as given', () {
    final a = ReferralAttachment.fromJson({
      'attached': true,
      'agentDisplayName': 'Ravi K.',
      'windowEndsAt': '2026-12-27',
    });
    expect(a.attached, isTrue);
    expect(a.windowEndsAt, '2026-12-27');
  });

  group('PendingReferralCode', () {
    test('round-trips through JSON', () {
      const code = PendingReferralCode(
        code: 'NM7K2P9X',
        agentDisplayName: 'Ravi K.',
        attempts: 2,
      );
      final back = PendingReferralCode.tryFromJson(code.toJson())!;
      expect(back.code, 'NM7K2P9X');
      expect(back.agentDisplayName, 'Ravi K.');
      expect(back.attempts, 2);
    });

    test('a corrupted record is no code at all', () {
      expect(PendingReferralCode.tryFromJson(null), isNull);
      expect(PendingReferralCode.tryFromJson('NM7K2P9X'), isNull);
      expect(PendingReferralCode.tryFromJson({'code': 'nonsense'}), isNull);
    });
  });
}

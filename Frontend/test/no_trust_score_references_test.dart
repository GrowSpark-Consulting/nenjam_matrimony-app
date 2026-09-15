import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Trust Score is gone from the Flutter app. This is the regression guard
/// that keeps it from creeping back in via a new widget, route, or string —
/// it scans the real sources rather than any one screen.
///
/// "Profile Complete Score" is a *different* feature and is deliberately
/// untouched by this scan.
const _trustScorePattern =
    r'trust[\s_-]?score|trustScore|TrustScore|TRUST_SCORE';

/// Trust-adjacent copy that legitimately survives: the login page's
/// SECURE / PRIVATE / VERIFIED badges and the verification wizard's
/// "build trust with matches" framing are about verification, not a score.
const _allowedKeys = {
  'authTrustSecure',
  'authTrustPrivate',
  'authTrustVerified',
  'settingsIdVerificationSubtitle',
  'registrationVerificationTitle',
  'registrationVerificationSubtitle',
  'registrationTipVerification',
  'registrationWizardVerificationHeadline',
  'onboardingVerifiedDescription',
  'completionCardBodyVerification',
};

void main() {
  final regex = RegExp(_trustScorePattern, caseSensitive: false);

  test('no Trust Score identifiers remain in lib/', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (regex.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'Trust Score references found:\n${offenders.join('\n')}');
  });

  test('no Trust Score localization keys or values remain', () {
    for (final locale in const ['en', 'ta']) {
      final file = File('lib/l10n/app_$locale.arb');
      final lines = file.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final key = RegExp(r'^\s*"@?([A-Za-z0-9_]+)"\s*:').firstMatch(line);
        if (key != null && _allowedKeys.contains(key.group(1))) continue;

        expect(
          regex.hasMatch(line),
          isFalse,
          reason: 'Trust Score copy in ${file.path}:${i + 1}: ${line.trim()}',
        );
        expect(
          line.toLowerCase().contains('trust'),
          isFalse,
          reason: 'Trust copy in ${file.path}:${i + 1}: ${line.trim()}',
        );
      }
    }
  });

  test('Profile Complete Score copy is still present', () {
    final en = File('lib/l10n/app_en.arb').readAsStringSync();

    expect(en, contains('"profileCompletionLabel"'));
    expect(en, contains('"profilePriorityCompletionImpact"'));
    expect(
      File('lib/features/profile/presentation/widgets/identity_hero_card.dart')
          .readAsStringSync(),
      contains('profileCompletion'),
    );
  });
}

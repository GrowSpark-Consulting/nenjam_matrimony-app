import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/compatibility_entity.dart';
import 'package:nenjam_matrimony/features/discover/presentation/widgets/compatibility_badge.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Psychology privacy guard. The backend deliberately sends
/// `isPsychologyCompleted: false` and `compatibility.psychologyMatchPercent:
/// 0` for every member — exposing either would let one member infer another
/// member's quiz answers (and filtering on them hid every member from search
/// once already). These fields may be parsed for API compatibility, but no
/// widget, filter, sort or condition may read them.
///
/// Like no_trust_score_references_test.dart, this scans the real sources
/// rather than any one screen, so a new card/filter can't slip past it.
const _reservedFields = ['isPsychologyCompleted', 'psychologyMatchPercent'];

/// The only places allowed to mention them: the entity declarations and the
/// JSON model that parses/serializes them.
const _allowedFiles = {
  'lib/features/discover/domain/entities/discovery_profile_entity.dart',
  'lib/features/discover/domain/entities/compatibility_entity.dart',
  'lib/features/discover/data/models/discovery_profile_model.dart',
};

void main() {
  test('reserved Psychology fields are only parsed, never used', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_allowedFiles.contains(path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_reservedFields.any(lines[i].contains)) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Psychology fields are intentionally unpopulated for privacy and '
          'must not be rendered, filtered or ranked on:\n'
          '${offenders.join('\n')}',
    );
  });

  test('no per-member Psychology display strings exist', () {
    for (final locale in const ['en', 'ta']) {
      final arb = File('lib/l10n/app_$locale.arb').readAsStringSync();
      expect(arb, isNot(contains('"homePsychologyCompletedLabel"')));
      expect(arb, isNot(contains('"homePsychologyMatchScoreLabel"')));
    }
  });

  testWidgets('a match badge never shows a Psychology score, even if one '
      'arrived', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              CompatibilityBadgeRow(
                compatibility: CompatibilityEntity(
                  aiMatchPercent: 73,
                  psychologyMatchPercent: 91,
                ),
              ),
              CompatibilityBadge(
                compatibility: CompatibilityEntity(
                  aiMatchPercent: 73,
                  psychologyMatchPercent: 91,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('73%'), findsNWidgets(2));
    expect(find.textContaining('91'), findsNothing);
    expect(find.textContaining('Psychology'), findsNothing);
  });
}

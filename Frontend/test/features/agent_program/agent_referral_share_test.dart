import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/agent_program/data/repositories/mock_agent_referral_link_repository.dart';
import 'package:nenjam_matrimony/features/agent_program/domain/models/agent_referral_link.dart';
import 'package:nenjam_matrimony/features/agent_program/domain/services/whatsapp_share.dart';
import 'package:nenjam_matrimony/features/agent_program/presentation/providers/agent_program_providers.dart';
import 'package:nenjam_matrimony/features/agent_program/presentation/widgets/agent_referral_share_card.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Referral sharing against the MOCK `GET /agent/referral-links` — the
/// endpoint is not built, so none of this is live-verified.
void main() {
  Map<String, dynamic> linkJson({
    Object? link,
    bool shareable = true,
    Object? messages,
  }) => {
    'codeId': '3f1c2b9e-0d5a-4e7b-9c1a-2b6d8e4f7a10',
    'code': 'NM7K2P9X',
    'isPrimary': true,
    'link': link,
    'qrPayload': link,
    'shareMessages':
        messages ??
        [
          {
            'id': 'default',
            'text': {
              'en': MockAgentReferralLinkRepository.mockEnglishMessage,
              'ta': MockAgentReferralLinkRepository.mockTamilMessage,
            },
          },
        ],
    'shareable': shareable,
  };

  group('AgentReferralLink.fromJson', () {
    test('reads the contract shape; null link and QR stay null', () {
      final link = AgentReferralLink.fromJson(linkJson());
      expect(link.code, 'NM7K2P9X');
      expect(link.isPrimary, isTrue);
      expect(link.link, isNull);
      expect(link.qrPayload, isNull);
      expect(link.shareable, isTrue);
      expect(
        link.shareTextFor('en'),
        MockAgentReferralLinkRepository.mockEnglishMessage,
      );
      expect(
        link.shareTextFor('ta'),
        MockAgentReferralLinkRepository.mockTamilMessage,
      );
    });

    test('missing shareable fails closed; missing messages are none', () {
      final link = AgentReferralLink.fromJson({'code': 'NM7K2P9X'});
      expect(link.shareable, isFalse);
      expect(link.shareMessages, isEmpty);
      expect(link.shareTextFor('en'), isNull);
    });

    test('an empty language is missing, never swapped for the other', () {
      final link = AgentReferralLink.fromJson(
        linkJson(
          messages: [
            {
              'id': 'default',
              'text': {'en': 'Hello NM7K2P9X', 'ta': ''},
            },
          ],
        ),
      );
      expect(link.shareTextFor('ta'), isNull);
      expect(link.shareTextFor('en'), 'Hello NM7K2P9X');
    });
  });

  test(
    'the mock carries the approved templates, rendered with no link line',
    () {
      // The mock is response data shaped like the backend's renderShareMessage
      // output; it must not contain an unfilled placeholder or a link line.
      for (final text in [
        MockAgentReferralLinkRepository.mockEnglishMessage,
        MockAgentReferralLinkRepository.mockTamilMessage,
      ]) {
        expect(text, isNot(contains('{')));
        expect(text, isNot(contains('\n')));
        expect(text, contains('NM7K2P9X'));
      }
      expect(
        MockAgentReferralLinkRepository.mockEnglishMessage,
        startsWith("Hi! I'm Ravi Kumar. Join Nenjam, a trusted matrimony app"),
      );
    },
  );

  group('WhatsApp', () {
    test('wa.me URL carries the message exactly, encoded', () {
      const message = 'Hi! I\'m Ravi & co — NM7K2P9X\nhttps://x.example/a?b=1';
      final uri = whatsAppShareUri(message);
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.queryParameters['text'], message);
    });

    test('empty message and launcher failure both return false', () async {
      expect(await shareOnWhatsApp('  ', open: (_) async => true), isFalse);
      expect(
        await shareOnWhatsApp('x', open: (_) async => throw Exception('no')),
        isFalse,
      );
    });
  });

  group('share card', () {
    late List<Uri> opened;
    var openResult = true;

    Future<void> pump(
      WidgetTester tester,
      AgentReferralLink link, {
      Locale locale = const Locale('en'),
    }) async {
      opened = [];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            urlOpenerProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return openResult;
            }),
          ],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: AgentReferralShareCard(link: link),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() => openResult = true);

    testWidgets('shares the link\'s own English message unchanged', (
      tester,
    ) async {
      await pump(tester, AgentReferralLink.fromJson(linkJson()));
      expect(find.text('NM7K2P9X'), findsOneWidget);
      await tester.tap(find.text('Share on WhatsApp'));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(
        opened.single.queryParameters['text'],
        MockAgentReferralLinkRepository.mockEnglishMessage,
      );
    });

    testWidgets('Tamil is chosen by toggle and sent as returned', (
      tester,
    ) async {
      await pump(tester, AgentReferralLink.fromJson(linkJson()));
      await tester.tap(find.text('தமிழ்'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share on WhatsApp'));
      await tester.pumpAndSettle();
      expect(
        opened.single.queryParameters['text'],
        MockAgentReferralLinkRepository.mockTamilMessage,
      );
    });

    testWidgets('not shareable (paused): button disabled, code still shown', (
      tester,
    ) async {
      await pump(
        tester,
        AgentReferralLink.fromJson(linkJson(shareable: false)),
      );
      expect(find.text('NM7K2P9X'), findsOneWidget);
      expect(
        find.text('Sharing is turned off for this code right now.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Share on WhatsApp'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
    });

    testWidgets('missing message: explained, nothing shared', (tester) async {
      await pump(tester, AgentReferralLink.fromJson(linkJson(messages: [])));
      expect(
        find.text('No ready-made message is available for this language.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Share on WhatsApp'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
    });

    testWidgets('link hidden when null, shown when present', (tester) async {
      await pump(tester, AgentReferralLink.fromJson(linkJson()));
      expect(find.textContaining('https://'), findsNothing);
      await pump(
        tester,
        AgentReferralLink.fromJson(linkJson(link: 'https://portal.invalid/r')),
      );
      expect(find.text('https://portal.invalid/r'), findsOneWidget);
    });

    testWidgets('fits a 320dp-wide phone in Tamil without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pump(
        tester,
        AgentReferralLink.fromJson(linkJson()),
        locale: const Locale('ta'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a share that cannot open says so', (tester) async {
      openResult = false;
      await pump(tester, AgentReferralLink.fromJson(linkJson()));
      await tester.tap(find.text('Share on WhatsApp'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't open WhatsApp. You can copy the code instead."),
        findsOneWidget,
      );
    });
  });
}

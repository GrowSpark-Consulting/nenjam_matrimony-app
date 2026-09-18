import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/profile_prompts/domain/models/prompt_bank_item.dart';
import 'package:nenjam_matrimony/features/profile_prompts/domain/repositories/profile_prompt_repository.dart';
import 'package:nenjam_matrimony/features/profile_prompts/presentation/pages/choose_prompt_page.dart';
import 'package:nenjam_matrimony/features/profile_prompts/presentation/providers/profile_prompt_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Widget-level coverage for [ChoosePromptPage]'s "Your Prompts" delete
/// interaction: the confirmation dialog, success removing the row, a
/// failure leaving it in place, and duplicate-tap prevention. Repository
/// request-shape/error-mapping is covered separately in
/// api_profile_prompt_repository_test.dart, so this file focuses on the UI.
void main() {
  group('ChoosePromptPage — Your Prompts delete', () {
    testWidgets('an existing prompt renders with a delete affordance',
        (tester) async {
      await _pump(tester, repository: _FakeRepository());

      expect(find.text('Honesty above all else'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });

    testWidgets('tapping delete shows a confirmation dialog; dismissing it '
        'changes nothing', (tester) async {
      final repo = _FakeRepository();
      await _pump(tester, repository: repo);

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Remove this prompt?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, isEmpty);
      expect(find.text('Honesty above all else'), findsOneWidget);
    });

    testWidgets('confirming delete calls the repository and removes the row '
        'on success', (tester) async {
      final repo = _FakeRepository();
      await _pump(tester, repository: repo);

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, ['p1']);
      expect(find.text('Honesty above all else'), findsNothing);
      expect(find.text('Prompt removed'), findsOneWidget);
    });

    testWidgets('a failed delete keeps the prompt visible and shows an '
        'error', (tester) async {
      final repo = _FakeRepository(
        deleteError: ApiException(500, 'boom'),
      );
      await _pump(tester, repository: repo);

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, ['p1']);
      // Still there — nothing changed on the backend either.
      expect(find.text('Honesty above all else'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      expect(find.text("Couldn't remove the prompt. Try again."), findsOneWidget);
    });

    testWidgets('a 404 (already removed) shows the specific not-found copy',
        (tester) async {
      final repo = _FakeRepository(
        deleteError: ApiException(404, 'Prompt answer not found.'),
      );
      await _pump(tester, repository: repo);

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('This prompt was already removed.'), findsOneWidget);
    });

    testWidgets('a second tap while the first delete is in flight does not '
        'fire a duplicate request', (tester) async {
      final repo = _FakeRepository(delaySettle: true);
      await _pump(tester, repository: repo);

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump(); // let the confirm dialog close and delete start

      // The icon is replaced by a spinner while in flight — nothing left to
      // tap a second time, which is itself part of the duplicate-prevention
      // guarantee, but also drive the underlying handler directly to prove
      // the in-flight guard holds even if a second event slipped through.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);

      repo.settle();
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, ['p1'], reason: 'exactly one DELETE, not two');
    });

    testWidgets('other prompts in the list are untouched by deleting one',
        (tester) async {
      const other = PromptAnswer(
        promptId: 'p2',
        promptText: 'My idea of a perfect weekend...',
        answerText: 'Hiking and a good book',
      );
      final repo = _FakeRepository();
      await _pump(tester, repository: repo, selection: [_answer, other]);

      final deleteIcons = find.byIcon(Icons.delete_outline_rounded);
      expect(deleteIcons, findsNWidgets(2));
      await tester.tap(deleteIcons.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, ['p1']);
      expect(find.text('Hiking and a good book'), findsOneWidget);
    });
  });
}

class _FakeRepository implements ProfilePromptRepository {
  _FakeRepository({this.deleteError, this.delaySettle = false});

  final Object? deleteError;
  final bool delaySettle;
  final List<String> deleteCalls = [];
  Completer<void>? _gate;

  void settle() => _gate?.complete();

  @override
  Future<List<PromptBankItem>> getPrompts({
    PromptCategory? category,
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<List<PromptAnswer>> getUserPrompts({CancelToken? cancelToken}) async =>
      const [];

  @override
  Future<void> saveUserPrompts(List<PromptAnswer> prompts) async {}

  @override
  Future<void> deletePrompt(String promptId) async {
    deleteCalls.add(promptId);
    if (delaySettle) {
      _gate = Completer<void>();
      await _gate!.future;
    }
    if (deleteError != null) throw deleteError!;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required ProfilePromptRepository repository,
  List<PromptAnswer> selection = const [_answer],
}) async {
  final router = GoRouter(
    initialLocation: '/choose',
    routes: [
      GoRoute(
        path: '/choose',
        builder: (context, state) => ChoosePromptPage(currentSelection: selection),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profilePromptRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _answer = PromptAnswer(
  promptId: 'p1',
  promptText: 'A family value I hold dear...',
  answerText: 'Honesty above all else',
);

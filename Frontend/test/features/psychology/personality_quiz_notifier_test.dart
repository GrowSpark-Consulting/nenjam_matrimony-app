import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_feed_entity.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/matches/presentation/providers/reel_feed_provider.dart';
import 'package:nenjam_matrimony/features/psychology/domain/models/personality_result.dart';
import 'package:nenjam_matrimony/features/psychology/domain/models/quiz_question.dart';
import 'package:nenjam_matrimony/features/psychology/presentation/providers/personality_provider.dart';
import 'package:nenjam_matrimony/features/search/presentation/providers/search_providers.dart';

import 'psychology_test_support.dart';

/// A fixed "now" after the fixtures' retake hint (completedAt Sep 20 + 7d).
final _now = DateTime.utc(2026, 10, 1, 12);

/// Builds a container around [repo], keeps the autoDispose notifier alive,
/// and lets its on-open `GET /me` check settle.
Future<ProviderContainer> _container(
  FakePersonalityRepository repo, {
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      personalityRepositoryProvider.overrideWithValue(repo),
      psychologyClockProvider.overrideWithValue(() => _now),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  container.listen(personalityQuizProvider, (_, __) {});
  await Future<void>.delayed(Duration.zero);
  return container;
}

PersonalityQuizState _state(ProviderContainer c) =>
    c.read(personalityQuizProvider);

PersonalityQuizNotifier _notifier(ProviderContainer c) =>
    c.read(personalityQuizProvider.notifier);

void main() {
  group('opening the quiz', () {
    test('not taken (GET /me -> null) starts at the intro', () async {
      final c = await _container(FakePersonalityRepository());
      expect(_state(c).phase, QuizPhase.intro);
    });

    test(
      'already taken opens at the completed state with the answers',
      () async {
        final c = await _container(
          FakePersonalityRepository(
            myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
          ),
        );
        expect(_state(c).phase, QuizPhase.result);
        expect(_state(c).result!.answers, hasLength(3));
      },
    );

    test(
      'GET /me 404 (thrown by a repository) is "not taken" — intro',
      () async {
        final c = await _container(
          FakePersonalityRepository(meError: ApiException(404, 'not taken')),
        );
        expect(_state(c).phase, QuizPhase.intro);
        expect(_state(c).error, isNull);
      },
    );

    final failures = <String, Object>{
      'network': DioException(
        requestOptions: RequestOptions(path: '/psychology/quiz/me'),
        type: DioExceptionType.connectionError,
      ),
      '401': ApiException(401, 'Unauthorized'),
      '500': DioException(
        requestOptions: RequestOptions(path: '/psychology/quiz/me'),
        response: Response(
          requestOptions: RequestOptions(path: '/psychology/quiz/me'),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      ),
    };
    failures.forEach((name, error) {
      test(
        'a $name failure on GET /me is checkFailed, never the intro',
        () async {
          final c = await _container(FakePersonalityRepository(meError: error));
          expect(_state(c).phase, QuizPhase.checking);
          expect(_state(c).error, QuizError.checkFailed);
        },
      );
    });

    test('retryCheck repeats GET /me and recovers', () async {
      final repo = FakePersonalityRepository(meError: Exception('offline'));
      final c = await _container(repo);
      expect(_state(c).error, QuizError.checkFailed);

      repo
        ..meError = null
        ..myResponse = PsychologyQuizResponse.fromJson(myResponseJson());
      await _notifier(c).retryCheck();
      expect(_state(c).phase, QuizPhase.result);
      expect(_state(c).error, isNull);
      expect(_state(c).result, isNotNull);
    });
  });

  group('loading', () {
    test('startQuiz loads the active quiz with a dynamic length', () async {
      final repo = FakePersonalityRepository(
        quiz: Quiz.fromJson(activeQuizJson(questionCount: 5)),
      );
      final c = await _container(repo);
      await _notifier(c).startQuiz();

      expect(_state(c).phase, QuizPhase.question);
      expect(_state(c).quiz!.questions, hasLength(5));
      expect(_state(c).currentIndex, 0);
      expect(_state(c).answers, isEmpty);
      expect(_state(c).error, isNull);
    });

    test('404 on /active -> unavailable', () async {
      final c = await _container(
        FakePersonalityRepository(
          activeError: ApiException(404, 'No active psychology quiz'),
        ),
      );
      await _notifier(c).startQuiz();
      expect(_state(c).quiz, isNull);
      expect(_state(c).error, QuizError.unavailable);
    });

    test(
      'network failure on /active -> loadFailed, and retry recovers',
      () async {
        final repo = FakePersonalityRepository(activeError: Exception('down'));
        final c = await _container(repo);
        await _notifier(c).startQuiz();
        expect(_state(c).error, QuizError.loadFailed);

        repo.activeError = null;
        await _notifier(c).startQuiz();
        expect(_state(c).error, isNull);
        expect(_state(c).quiz, isNotNull);
      },
    );
  });

  group('answering and navigation', () {
    test('stores the selected option KEY per question id', () async {
      final c = await _container(FakePersonalityRepository());
      await _notifier(c).startQuiz();
      _notifier(c).answer('q1', 'C');
      _notifier(c).answer('q1', 'D'); // changing an answer replaces it
      _notifier(c).answer('q2', 'A');
      expect(_state(c).answers, {'q1': 'D', 'q2': 'A'});
    });

    test('next/previous are bounded by questions.length', () async {
      final c = await _container(FakePersonalityRepository());
      await _notifier(c).startQuiz();
      final n = _notifier(c);

      n.previousQuestion();
      expect(_state(c).currentIndex, 0);
      n.nextQuestion();
      n.nextQuestion();
      expect(_state(c).currentIndex, 2);
      expect(_state(c).isLastQuestion, isTrue);
      n.nextQuestion();
      expect(_state(c).currentIndex, 2);
      n.previousQuestion();
      expect(_state(c).currentIndex, 1);
    });
  });

  group('submit', () {
    test('incomplete answers are not sent; jumps to the first gap', () async {
      final repo = FakePersonalityRepository();
      final c = await _container(repo);
      await _notifier(c).startQuiz();
      _notifier(c).answer('q1', 'A');
      _notifier(c).answer('q3', 'B');
      _notifier(c).nextQuestion();
      _notifier(c).nextQuestion();

      await _notifier(c).submit();

      expect(repo.submits, isEmpty);
      expect(_state(c).error, QuizError.incomplete);
      expect(_state(c).currentIndex, 1);
      expect(_state(c).phase, QuizPhase.question);
    });

    test('submits the loaded quizId and every answer in question order, '
        'then shows the completed state', () async {
      final repo = FakePersonalityRepository(
        quiz: Quiz.fromJson(activeQuizJson(id: 'server-given-id')),
      );
      final c = await _container(repo);
      await _notifier(c).startQuiz();
      _notifier(c).answer('q3', 'D');
      _notifier(c).answer('q1', 'B');
      _notifier(c).answer('q2', 'C');

      await _notifier(c).submit();

      expect(repo.submits.single.quizId, 'server-given-id');
      expect(repo.submits.single.answers.keys, ['q1', 'q2', 'q3']);
      expect(repo.submits.single.answers, {'q1': 'B', 'q2': 'C', 'q3': 'D'});
      expect(_state(c).phase, QuizPhase.result);
      expect(_state(c).isSubmitting, isFalse);
      expect(_state(c).result!.selectedKeys, {'q1': 'B', 'q2': 'C', 'q3': 'D'});
    });

    test('a network failure stops loading, keeps answers, stays on the quiz, '
        'and can be retried', () async {
      final repo = FakePersonalityRepository()
        ..submitError = Exception('timeout');
      final c = await _container(repo);
      await _notifier(c).startQuiz();
      for (final q in ['q1', 'q2', 'q3']) {
        _notifier(c).answer(q, 'A');
      }

      await _notifier(c).submit();
      expect(_state(c).isSubmitting, isFalse);
      expect(_state(c).error, QuizError.submitFailed);
      expect(_state(c).phase, QuizPhase.question);
      expect(_state(c).answers, {'q1': 'A', 'q2': 'A', 'q3': 'A'});

      await _notifier(c).submit(); // retry
      expect(_state(c).phase, QuizPhase.result);
      expect(repo.submits, hasLength(2));
    });

    test('a 400 (quiz changed) re-fetches the quiz, keeps answers that still '
        'fit, and points at the first gap', () async {
      final repo = FakePersonalityRepository();
      final c = await _container(repo);
      await _notifier(c).startQuiz();
      for (final q in ['q1', 'q2', 'q3']) {
        _notifier(c).answer(q, 'B');
      }
      // The active quiz is replaced by one with an extra question.
      repo
        ..submitError = ApiException(400, 'quizId does not match')
        ..quiz = Quiz.fromJson(activeQuizJson(id: 'new-id', questionCount: 4));

      await _notifier(c).submit();

      expect(_state(c).error, QuizError.rejected);
      expect(_state(c).isSubmitting, isFalse);
      expect(_state(c).phase, QuizPhase.question);
      expect(_state(c).quiz!.id, 'new-id');
      expect(_state(c).answers, {'q1': 'B', 'q2': 'B', 'q3': 'B'});
      expect(_state(c).currentIndex, 3);

      _notifier(c).answer('q4', 'A');
      await _notifier(c).submit();
      expect(repo.submits.last.quizId, 'new-id');
      expect(_state(c).phase, QuizPhase.result);
    });
  });

  group('retake', () {
    test(
      'pre-fills saved answers and resubmits through the same endpoint',
      () async {
        final repo = FakePersonalityRepository(
          myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
        );
        final c = await _container(repo);
        expect(_state(c).phase, QuizPhase.result);

        await _notifier(c).retake();
        expect(_state(c).phase, QuizPhase.question);
        expect(_state(c).currentIndex, 0);
        expect(_state(c).answers, {'q1': 'B', 'q2': 'C', 'q3': 'A'});

        _notifier(c).answer('q2', 'D');
        await _notifier(c).submit();
        expect(repo.submits.single.answers, {'q1': 'B', 'q2': 'D', 'q3': 'A'});
        expect(_state(c).phase, QuizPhase.result);
        expect(_state(c).result!.selectedKeys['q2'], 'D');
      },
    );

    test(
      'saved answers from a different (retired) quiz are not pre-filled',
      () async {
        final repo = FakePersonalityRepository(
          myResponse: PsychologyQuizResponse.fromJson(
            myResponseJson(quizId: 'retired-quiz'),
          ),
        );
        final c = await _container(repo);
        await _notifier(c).retake();
        expect(_state(c).answers, isEmpty);
      },
    );
  });

  group('429 on submit', () {
    ApiException cooldown(int seconds) => ApiException(
      429,
      'You can change your quiz answers again in 3 days.',
      retryAfterSeconds: seconds,
    );

    test('with retryAfterSeconds on a retake: retakeCooldown, back to the '
        'saved answers, attempted answers kept, no automatic retry', () async {
      final repo = FakePersonalityRepository(
        myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
      );
      final c = await _container(repo);
      await _notifier(c).retake();
      _notifier(c).answer('q2', 'D');
      repo.submitError = cooldown(259200);

      await _notifier(c).submit();
      await Future<void>.delayed(Duration.zero);

      final s = _state(c);
      expect(s.error, QuizError.retakeCooldown);
      expect(s.cooldownSeconds, 259200);
      expect(s.isSubmitting, isFalse);
      expect(s.phase, QuizPhase.result);
      expect(s.result!.selectedKeys, {'q1': 'B', 'q2': 'C', 'q3': 'A'});
      expect(s.answers, {'q1': 'B', 'q2': 'D', 'q3': 'A'});
      expect(s.serverRetakeAvailableAt, _now.add(const Duration(days: 3)));
      expect(s.retakeAvailableAt, _now.add(const Duration(days: 3)));
      expect(repo.submits, hasLength(1));
    });

    test('overrides a client hint that said retaking was allowed', () async {
      // Clock is past the hint (Sep 27), yet the server says wait.
      final repo = FakePersonalityRepository(
        myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
      );
      final c = await _container(repo);
      expect(_now.isAfter(_state(c).retakeAvailableAt!), isTrue);

      await _notifier(c).retake();
      repo.submitError = cooldown(3600);
      await _notifier(c).submit();

      expect(_state(c).error, QuizError.retakeCooldown);
      expect(_now.isBefore(_state(c).retakeAvailableAt!), isTrue);
    });

    test(
      'with no saved response, stays on the quiz with answers kept',
      () async {
        final repo = FakePersonalityRepository()..submitError = cooldown(90000);
        final c = await _container(repo);
        await _notifier(c).startQuiz();
        for (final q in ['q1', 'q2', 'q3']) {
          _notifier(c).answer(q, 'C');
        }

        await _notifier(c).submit();

        expect(_state(c).error, QuizError.retakeCooldown);
        expect(_state(c).phase, QuizPhase.question);
        expect(_state(c).answers, {'q1': 'C', 'q2': 'C', 'q3': 'C'});
      },
    );

    test('an absurdly large retryAfterSeconds does not overflow', () async {
      final repo = FakePersonalityRepository(
        myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
      );
      final c = await _container(repo);
      await _notifier(c).retake();
      repo.submitError = cooldown(1 << 50);
      await _notifier(c).submit();

      expect(_state(c).error, QuizError.retakeCooldown);
      expect(_state(c).serverRetakeAvailableAt, isNotNull);
      expect(_state(c).serverRetakeAvailableAt!.isAfter(_now), isTrue);
    });

    test('without retryAfterSeconds it is the generic rate limit, not a '
        'cooldown', () async {
      final repo = FakePersonalityRepository(
        myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
      );
      final c = await _container(repo);
      await _notifier(c).retake();
      repo.submitError = ApiException(429, 'ThrottlerException');

      await _notifier(c).submit();

      expect(_state(c).error, QuizError.rateLimited);
      expect(_state(c).phase, QuizPhase.question);
      expect(_state(c).serverRetakeAvailableAt, isNull);
      expect(_state(c).answers, {'q1': 'B', 'q2': 'C', 'q3': 'A'});
    });
  });

  group('feed refresh after submit', () {
    late int discoverBuilds;
    late int reelBuilds;
    late int searchBuilds;

    Future<ProviderContainer> feedContainer(
      FakePersonalityRepository repo,
    ) async {
      discoverBuilds = 0;
      reelBuilds = 0;
      searchBuilds = 0;
      final c = await _container(
        repo,
        overrides: [
          discoverFeedProvider.overrideWith((ref) {
            discoverBuilds++;
            return Completer<DiscoverFeedEntity>().future;
          }),
          reelFeedProvider.overrideWith(
            () => _CountingReelFeed(() => reelBuilds++),
          ),
          searchResultsProvider.overrideWith(
            () => _CountingSearchResults(() => searchBuilds++),
          ),
        ],
      );
      // Mounted, as if their screens were open.
      c.listen(discoverFeedProvider, (_, __) {});
      c.listen(reelFeedProvider, (_, __) {});
      c.listen(searchResultsProvider, (_, __) {});
      return c;
    }

    void readFeeds(ProviderContainer c) {
      c.read(discoverFeedProvider);
      c.read(reelFeedProvider);
      c.read(searchResultsProvider);
    }

    test('a successful submit invalidates Discover, reel and search', () async {
      final c = await feedContainer(FakePersonalityRepository());
      expect([discoverBuilds, reelBuilds, searchBuilds], [1, 1, 1]);

      await _notifier(c).startQuiz();
      for (final q in ['q1', 'q2', 'q3']) {
        _notifier(c).answer(q, 'A');
      }
      await _notifier(c).submit();
      await Future<void>.delayed(Duration.zero);
      readFeeds(c);

      expect(_state(c).phase, QuizPhase.result);
      expect([discoverBuilds, reelBuilds, searchBuilds], [2, 2, 2]);
    });

    for (final (name, error) in [
      ('network failure', Exception('timeout') as Object),
      ('cooldown 429', ApiException(429, 'wait', retryAfterSeconds: 60)),
      ('rate-limit 429', ApiException(429, 'ThrottlerException')),
      ('400 rejection', ApiException(400, 'quiz changed')),
    ]) {
      test('a failed submit ($name) does not invalidate the feeds', () async {
        final repo = FakePersonalityRepository();
        final c = await feedContainer(repo);
        await _notifier(c).startQuiz();
        for (final q in ['q1', 'q2', 'q3']) {
          _notifier(c).answer(q, 'A');
        }
        repo.submitError = error;
        await _notifier(c).submit();
        await Future<void>.delayed(Duration.zero);
        readFeeds(c);

        expect(_state(c).phase, QuizPhase.question);
        expect([discoverBuilds, reelBuilds, searchBuilds], [1, 1, 1]);
      });
    }
  });
}

class _CountingReelFeed extends ReelFeedNotifier {
  _CountingReelFeed(this._onBuild);
  final void Function() _onBuild;

  @override
  Future<ReelFeedState> build() {
    _onBuild();
    return Completer<ReelFeedState>().future;
  }
}

class _CountingSearchResults extends SearchResultsNotifier {
  _CountingSearchResults(this._onBuild);
  final void Function() _onBuild;

  @override
  Future<SearchResultsState> build() {
    _onBuild();
    return Completer<SearchResultsState>().future;
  }
}

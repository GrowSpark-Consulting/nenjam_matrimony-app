import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/network/api_endpoints.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/partner_preferences/data/repositories/partner_preferences_repository_impl.dart';
import 'package:nenjam_matrimony/features/partner_preferences/domain/models/partner_preference_extended.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';

/// Records the method/path/body of every request and replays a canned
/// response — the same stubbing approach `location_repository_test.dart`
/// and `search_repository_test.dart` use.
class _StubClient extends ApiClient {
  _StubClient({this.data, this.status = 200});

  Map<String, dynamic>? data;
  int status;

  /// Thrown instead of returning, when set — stands in for a timeout or a
  /// dead connection (Dio surfaces both as a DioException).
  DioException? throws;

  final List<String> methods = [];
  final List<String> paths = [];
  final List<dynamic> bodies = [];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    methods.add('GET');
    paths.add(path);
    bodies.add(null);
    if (throws != null) throw throws!;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      data: data as T?,
    );
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    methods.add('PUT');
    paths.add(path);
    bodies.add(data);
    if (throws != null) throw throws!;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      data: this.data as T?,
    );
  }
}

/// What `GET /discover/preferences` returns for a member who has never saved
/// anything: no limits at all. (It used to fill in 18-45 / 140-210, which the
/// app then showed — and re-saved — as a real range.)
Map<String, dynamic> _defaultsResponse() => {
      'minAge': null,
      'maxAge': null,
      'minHeightCm': null,
      'maxHeightCm': null,
      'minIncomeLakhs': null,
      'preferredReligions': <String>[],
      'preferredCastes': <String>[],
      'preferredMotherTongues': <String>[],
      'preferredEducation': <String>[],
      'preferredOccupations': <String>[],
      'preferredCities': <String>[],
      'preferredStates': <String>[],
      'maritalStatusPref': <String>[],
    };

void main() {
  group('PartnerPreferencesRepositoryImpl.getPreferences', () {
    test('calls GET /discover/preferences', () async {
      final client = _StubClient(data: _defaultsResponse());

      await PartnerPreferencesRepositoryImpl(client).getPreferences();

      expect(client.methods, ['GET']);
      expect(client.paths, ['/discover/preferences']);
      expect(ApiEndpoints.discoverPreferences, '/discover/preferences');
    });

    test('schema defaults parse to an unset-looking, non-crashing form',
        () async {
      final client = _StubClient(data: _defaultsResponse());

      final result =
          await PartnerPreferencesRepositoryImpl(client).getPreferences();

      // No limit reads back as "", the placeholder a fresh PartnerPreference
      // already renders — never as a range the member didn't choose.
      expect(result.preferredAgeRange, '');
      expect(result.preferredHeightRange, '');
      expect(result.incomePref, '');
      expect(result.religionPref, '');
      expect(result.castePref, '');
      expect(result.motherTonguePref, '');
      expect(result.occupationPref, '');
      expect(result.locationPref, '');
      expect(result.maritalStatusPref, '');
      expect(result.educationPref, '');
    });

    test('extended reads back empty for a member who never saved any',
        () async {
      final client = _StubClient(data: _defaultsResponse());

      final result =
          await PartnerPreferencesRepositoryImpl(client).getPreferences();

      expect(result.extended.isEmpty, isTrue);
    });

    test('extended is parsed from the response, not discarded', () async {
      // The whole point of the fix: what the member saved comes back, so the
      // page can show it instead of an empty form.
      final client = _StubClient(data: {
        ..._defaultsResponse(),
        'extended': const {
          'diet': 'Vegetarian',
          'smoking': 'No',
          'ethnicity': 'Iyer',
        },
      });

      final result =
          await PartnerPreferencesRepositoryImpl(client).getPreferences();

      expect(result.extended.isEmpty, isFalse);
      expect(result.extended.diet, 'Vegetarian');
      expect(result.extended.smoking, 'No');
      expect(result.extended.ethnicity, 'Iyer');
    });

    test('a missing or malformed extended reads as empty, never throws',
        () async {
      // An older backend omits the key entirely; a hand-edited row could hold
      // something that is not an object at all.
      for (final value in [null, 'garbage', 42, <dynamic>[]]) {
        final client = _StubClient(data: {
          ..._defaultsResponse(),
          if (value != null) 'extended': value,
        });

        final result =
            await PartnerPreferencesRepositoryImpl(client).getPreferences();

        expect(result.extended.isEmpty, isTrue);
      }
    });

    test('parses a fully-saved response back to the exact picker strings',
        () async {
      final client = _StubClient(data: {
        'minAge': 26,
        'maxAge': 30,
        // 4'6" = 54in * 2.54 = 137.16 -> 137; 5'0" = 60in * 2.54 = 152.4 -> 152.
        'minHeightCm': 137,
        'maxHeightCm': 152,
        // parseLeadingNumber('10-20 Lakhs') == 10, not '5-10 Lakhs' (== 5).
        'minIncomeLakhs': 10,
        'preferredReligions': ['Hindu'],
        'preferredCastes': ['Same Caste'],
        'preferredMotherTongues': ['Tamil'],
        'preferredEducation': ['B.E / B.Tech+'],
        'preferredOccupations': ['Doctor'],
        'preferredCities': ['Same City'],
        'preferredStates': <String>[],
        'maritalStatusPref': ['Never Married'],
      });

      final result =
          await PartnerPreferencesRepositoryImpl(client).getPreferences();

      expect(result.preferredAgeRange, '26-30');
      expect(result.preferredHeightRange, '4\'6"-5\'0"');
      expect(result.incomePref, '10-20 Lakhs');
      expect(result.religionPref, 'Hindu');
      expect(result.castePref, 'Same Caste');
      expect(result.motherTonguePref, 'Tamil');
      expect(result.educationPref, 'B.E / B.Tech+');
      expect(result.occupationPref, 'Doctor');
      expect(result.locationPref, 'Same City');
      expect(result.maritalStatusPref, 'Never Married');
    });

    test('a saved value matching no known preset falls back to "" rather '
        'than fabricating a label', () async {
      final client = _StubClient(data: {
        ..._defaultsResponse(),
        'minHeightCm': 133,
        'maxHeightCm': 190,
        'minIncomeLakhs': 37,
      });

      final result =
          await PartnerPreferencesRepositoryImpl(client).getPreferences();

      expect(result.preferredHeightRange, '');
      expect(result.incomePref, '');
    });

    test('throws ApiException on 401', () async {
      final client = _StubClient(
        status: 401,
        data: {'statusCode': 401, 'message': 'Empty bearer token.'},
      );

      await expectLater(
        PartnerPreferencesRepositoryImpl(client).getPreferences(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
    });

    test('propagates a connection failure rather than swallowing it', () async {
      final client = _StubClient()
        ..throws = DioException.connectionTimeout(
          timeout: const Duration(seconds: 20),
          requestOptions: RequestOptions(path: ApiEndpoints.discoverPreferences),
        );

      await expectLater(
        PartnerPreferencesRepositoryImpl(client).getPreferences(),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('PartnerPreferencesRepositoryImpl.updatePreferences — request shape',
      () {
    test('calls PUT /discover/preferences', () async {
      final client = _StubClient(data: _defaultsResponse());

      await PartnerPreferencesRepositoryImpl(client)
          .updatePreferences(const PartnerPreference());

      expect(client.methods, ['PUT']);
      expect(client.paths, ['/discover/preferences']);
    });

    test('an entirely-unset draft sends only an empty advanced blob — never '
        'invents a base field', () async {
      final client = _StubClient(data: _defaultsResponse());

      await PartnerPreferencesRepositoryImpl(client)
          .updatePreferences(const PartnerPreference());

      // `extended` always travels (the page owns every field in it, so the
      // whole object is the unit of save); the base fields stay omitted. An
      // untouched blob still serializes its boolean flags, so the model's own
      // toJson is the expectation rather than a hand-written {}.
      expect(client.bodies.single, {
        'extended': const PartnerPreferenceExtended().toJson(),
      });
    });

    test('sends exactly the UpdatePartnerPreferenceDto field names, parsed '
        'to the backend types', () async {
      final client = _StubClient(data: _defaultsResponse());

      await PartnerPreferencesRepositoryImpl(client).updatePreferences(
        const PartnerPreference(
          preferredAgeRange: '26-30',
          preferredHeightRange: '4\'6"-5\'0"',
          religionPref: 'Hindu',
          castePref: 'Same Caste',
          educationPref: 'B.E / B.Tech+',
          occupationPref: 'Doctor',
          incomePref: '10-20 Lakhs',
          locationPref: 'Same City',
          motherTonguePref: 'Tamil',
          maritalStatusPref: 'Never Married',
        ),
      );

      expect(client.bodies.single, {
        'minAge': 26,
        'maxAge': 30,
        // 4'6" = 54in * 2.54 = 137.16 -> 137; 5'0" = 60in * 2.54 = 152.4 -> 152.
        'minHeightCm': 137,
        'maxHeightCm': 152,
        'minIncomeLakhs': 10.0,
        'preferredReligions': ['Hindu'],
        'preferredCastes': ['Same Caste'],
        'preferredMotherTongues': ['Tamil'],
        'preferredEducation': ['B.E / B.Tech+'],
        'preferredOccupations': ['Doctor'],
        'preferredCities': ['Same City'],
        'maritalStatusPref': ['Never Married'],
        'extended': const PartnerPreferenceExtended().toJson(),
      });
      // preferredStates is never sent — the UI has no control for it and
      // omitting it (rather than forcing []) preserves whatever the server
      // already has, per the partial-update contract.
      expect(client.bodies.single, isNot(contains('preferredStates')));
    });

    test('"Any" age/height/income are sent as null, which CLEARS a saved '
        'limit', () async {
      final client = _StubClient(data: _defaultsResponse());

      await PartnerPreferencesRepositoryImpl(client).updatePreferences(
        const PartnerPreference(
          preferredAgeRange: 'Any',
          preferredHeightRange: 'Any',
          incomePref: 'Any',
        ),
      );

      // Explicit nulls, not omissions: an omitted field is left as it is on
      // the server, so omitting "Any" could never remove a range once saved.
      expect(client.bodies.single, <String, dynamic>{
        'minAge': null,
        'maxAge': null,
        'minHeightCm': null,
        'maxHeightCm': null,
        'minIncomeLakhs': null,
        'extended': const PartnerPreferenceExtended().toJson(),
      });
    });

    test('the advanced preferences reach the wire — the whole point of the '
        'fix', () async {
      // Before: `_toRequestBody` omitted `extended` entirely, so a member's
      // advanced edits were discarded while Save reported success.
      final client = _StubClient(data: _defaultsResponse());

      await PartnerPreferencesRepositoryImpl(client).updatePreferences(
        const PartnerPreference(
          religionPref: 'Hindu',
          extended: PartnerPreferenceExtended(
            diet: 'Vegetarian',
            smoking: 'No',
            ethnicity: 'Iyer',
          ),
        ),
      );

      final body = client.bodies.single as Map<String, dynamic>;
      final extended = body['extended'] as Map<String, dynamic>;
      expect(extended['diet'], 'Vegetarian');
      expect(extended['smoking'], 'No');
      expect(extended['ethnicity'], 'Iyer');
      // And the base half is unaffected by carrying it.
      expect(body['preferredReligions'], ['Hindu']);
    });

    test('a save round-trips the advanced preferences back from the server',
        () async {
      final client = _StubClient(data: {
        ..._defaultsResponse(),
        'extended': const {'diet': 'Vegetarian'},
      });

      final saved =
          await PartnerPreferencesRepositoryImpl(client).updatePreferences(
        const PartnerPreference(
          extended: PartnerPreferenceExtended(diet: 'Vegetarian'),
        ),
      );

      // The response is authoritative, so the page can adopt it wholesale
      // instead of re-merging its local copy.
      expect(saved.extended.diet, 'Vegetarian');
    });

    test('an untouched range is still omitted — only "Any" clears', () async {
      final client = _StubClient(data: _defaultsResponse());

      await PartnerPreferencesRepositoryImpl(client).updatePreferences(
        const PartnerPreference(religionPref: 'Hindu'),
      );

      final body = client.bodies.single as Map<String, dynamic>;
      expect(body.containsKey('minAge'), isFalse);
      expect(body.containsKey('minHeightCm'), isFalse);
      expect(body.containsKey('minIncomeLakhs'), isFalse);
    });

    test('the open-ended height preset ("6\'0"+") has no maximum', () async {
      final client = _StubClient(data: _defaultsResponse());

      await PartnerPreferencesRepositoryImpl(client).updatePreferences(
        const PartnerPreference(preferredHeightRange: '6\'0"+'),
      );

      final body = client.bodies.single as Map<String, dynamic>;
      expect(body['minHeightCm'], 183);
      // Sent as a cleared upper bound — the same thing the backend seeds for
      // this preset from a registration draft.
      expect(body.containsKey('maxHeightCm'), isTrue);
      expect(body['maxHeightCm'], isNull);
    });

    test('an open-ended height reads back as its preset, with no maximum or '
        'with the 250 older builds stored', () async {
      for (final max in <int?>[null, 250]) {
        final client = _StubClient(data: {
          ..._defaultsResponse(),
          'minHeightCm': 183,
          'maxHeightCm': max,
        });
        final result =
            await PartnerPreferencesRepositoryImpl(client).getPreferences();
        expect(result.preferredHeightRange, '6\'0"+', reason: 'max=$max');
      }
    });

    test('returns the backend\'s post-write response, not an echo of the '
        'request', () async {
      final client = _StubClient(data: {
        ..._defaultsResponse(),
        'minAge': 26,
        'maxAge': 30,
      });

      final result = await PartnerPreferencesRepositoryImpl(client)
          .updatePreferences(const PartnerPreference(preferredAgeRange: '99-99'));

      // 99-99 is what was SENT; 26-30 is what the (stubbed) server says was
      // actually stored — the repository must surface the latter.
      expect(result.preferredAgeRange, '26-30');
    });

    test('throws ApiException on a 400 validation error, carrying the '
        'backend message', () async {
      final client = _StubClient(
        status: 400,
        data: {
          'statusCode': 400,
          'message': ['minAge must not be less than 18'],
        },
      );

      await expectLater(
        PartnerPreferencesRepositoryImpl(client)
            .updatePreferences(const PartnerPreference(preferredAgeRange: '5-10')),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.message, 'message',
                  'minAge must not be less than 18'),
        ),
      );
    });
  });
}

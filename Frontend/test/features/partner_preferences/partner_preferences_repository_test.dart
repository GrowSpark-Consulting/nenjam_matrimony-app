import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/network/api_endpoints.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/partner_preferences/data/repositories/partner_preferences_repository_impl.dart';
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

/// The backend's schema defaults (`PreferencesService.DEFAULTS`) — what
/// `GET /discover/preferences` returns for a member who has never saved
/// anything.
Map<String, dynamic> _defaultsResponse() => {
      'minAge': 18,
      'maxAge': 45,
      'minHeightCm': 140,
      'maxHeightCm': 210,
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

      // 18-45 is a real, exact slider value (age has no bucket ambiguity),
      // but height/income defaults are indistinguishable from "never set"
      // and from an explicit "Any" — both map to "" per the repository's
      // documented fallback, matching the placeholder a fresh
      // PartnerPreference already renders.
      expect(result.preferredAgeRange, '18-45');
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

    test('extended is always empty — this endpoint has no such field',
        () async {
      final client = _StubClient(data: _defaultsResponse());

      final result =
          await PartnerPreferencesRepositoryImpl(client).getPreferences();

      expect(result.extended.isEmpty, isTrue);
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

    test('an entirely-unset draft sends an empty body — never invents a '
        'field', () async {
      final client = _StubClient(data: _defaultsResponse());

      await PartnerPreferencesRepositoryImpl(client)
          .updatePreferences(const PartnerPreference());

      expect(client.bodies.single, <String, dynamic>{});
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
      });
      // preferredStates is never sent — the UI has no control for it and
      // omitting it (rather than forcing []) preserves whatever the server
      // already has, per the partial-update contract.
      expect(client.bodies.single, isNot(contains('preferredStates')));
    });

    test('"Any" age/height/income are indistinguishable from unset and are '
        'omitted, matching the backend\'s own fallback collapse', () async {
      final client = _StubClient(data: _defaultsResponse());

      await PartnerPreferencesRepositoryImpl(client).updatePreferences(
        const PartnerPreference(
          preferredAgeRange: 'Any',
          preferredHeightRange: 'Any',
          incomePref: 'Any',
        ),
      );

      expect(client.bodies.single, <String, dynamic>{});
    });

    test('the open-ended height preset ("6\'0"+") parses to a bounded '
        'max, not an unbounded one', () async {
      final client = _StubClient(data: _defaultsResponse());

      await PartnerPreferencesRepositoryImpl(client).updatePreferences(
        const PartnerPreference(preferredHeightRange: '6\'0"+'),
      );

      final body = client.bodies.single as Map<String, dynamic>;
      expect(body['minHeightCm'], 183);
      expect(body['maxHeightCm'], 250); // DTO's own @Max(250) ceiling
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

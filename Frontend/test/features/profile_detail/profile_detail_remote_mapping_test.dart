import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/profile_detail/data/datasources/profile_detail_remote_datasource.dart';
import 'package:nenjam_matrimony/features/profile_detail/domain/entities/verification_checklist_entity.dart';

/// Answers every GET with a canned response, or throws — the stubbing
/// approach `partner_preferences_repository_test.dart` uses.
class _StubClient extends ApiClient {
  _StubClient({this.data, this.status = 200, this.throws});

  final Map<String, dynamic>? data;
  final int status;
  final DioException? throws;
  final List<String> paths = [];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    paths.add(path);
    if (throws != null) throw throws!;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      data: data as T?,
    );
  }
}

/// The detail screen must show what the member saved and nothing else: the
/// previous in-memory source invented parents' names, a bio, a horoscope and
/// partner preferences from a hash of the profile id.
void main() {
  const base = DiscoveryProfileEntity(
    id: 'u-1',
    matrimonyId: 'U1',
    name: 'Card Name',
    age: 29,
    location: 'Chennai, Tamil Nadu',
    profession: 'Engineer',
    education: 'B.E.',
    photoUrls: [],
    gender: 'female',
  );

  Map<String, dynamic> card({Map<String, dynamic>? detail}) => {
    'id': 'u-1',
    'name': 'Fresh Name',
    'age': 29,
    'location': 'Chennai, Tamil Nadu',
    'profession': 'Engineer',
    'photoUrls': <String>[],
    'maritalStatus': 'Never Married',
    'motherTongue': 'Tamil',
    'bio': '  Loves long walks.  ',
    'hobbies': ['Chess', 'Music'],
    'diet': 'Vegetarian',
    'smoking': 'No',
    'drinking': '',
    'physicalStatus': '',
    'phoneVerified': true,
    'isVerified': false,
    if (detail != null) 'detail': detail,
  };

  test('maps saved values through unchanged', () {
    final d = parseProfileDetail(
      base,
      card(
        detail: {
          'family': {
            'fatherName': 'Ravi Kumar',
            'fatherOccupation': 'Farmer',
            'motherName': '',
            'motherOccupation': '',
            'familyType': 'Nuclear',
            'familyValues': '',
            'familyStatus': '',
            'brothers': 1,
            'sisters': 0,
          },
          'fitness': 'Daily',
          'horoscope': {
            'rasi': 'Kumbha',
            'nakshatra': 'Sathayam',
            'dosham': 'Chevvai',
            'horoscopeAvailable': true,
          },
          'partnerPreference': {
            'minAge': 25,
            'maxAge': 30,
            'minHeightCm': 152,
            'maxHeightCm': null,
            'religions': ['Hindu'],
            'castes': <String>[],
            'education': <String>[],
            'occupations': <String>[],
            'minIncomeLakhs': 12.5,
            'cities': ['Chennai'],
            'states': ['Tamil Nadu'],
            'motherTongues': <String>[],
            'maritalStatuses': ['Never Married'],
          },
        },
      ),
    );

    // The tapped card is kept as `base` (it carries feed-computed scores).
    expect(d.base, same(base));
    expect(d.maritalStatus, 'Never Married');
    expect(d.motherTongue, 'Tamil');
    expect(d.bio, 'Loves long walks.');
    expect(d.interests, ['Chess', 'Music']);
    expect(d.coreValues, isEmpty);

    expect(d.family.fatherName, 'Ravi Kumar');
    expect(d.family.fatherOccupation, 'Farmer');
    expect(d.family.motherName, isEmpty);
    expect(d.family.brothers, 1);
    expect(d.family.sisters, 0);

    expect(d.lifestyle.eatingHabit, 'Vegetarian');
    expect(d.lifestyle.fitness, 'Daily');
    expect(d.lifestyle.drinking, isEmpty);
    expect(d.lifestyle.aboutMe, isEmpty);

    expect(d.horoscope.rasi, 'Kumbha');
    expect(d.horoscope.dosham, 'Chevvai');
    expect(d.horoscope.matchingEnabled, isTrue);
    expect(d.horoscope.matchingPoints, isEmpty);

    final p = d.partnerPreferences;
    expect(p.preferredAgeRange, '25-30');
    expect(p.preferredHeightRange, "5'0\"+");
    expect(p.religionPref, 'Hindu');
    expect(p.castePref, isEmpty);
    expect(p.incomePref, '12.5+ LPA');
    expect(p.locationPref, 'Chennai, Tamil Nadu');
    expect(p.maritalStatusPref, 'Never Married');

    // Only checks the backend reports — no invented email / government ID.
    final items = d.verification.items;
    expect(items, hasLength(2));
    expect(items[0].status, VerificationItemStatus.verified);
    expect(items[1].status, VerificationItemStatus.incomplete);
    expect(d.timeline, isEmpty);
  });

  test(
    'a member who filled in nothing gets an empty profile, not a made-up one',
    () {
      final d = parseProfileDetail(base, {
        ...card(
          detail: {
            'family': <String, dynamic>{},
            'fitness': '',
            'horoscope': <String, dynamic>{},
            'partnerPreference': null,
          },
        ),
        'bio': '',
        'hobbies': <String>[],
        'maritalStatus': '',
        'motherTongue': '',
      });

      expect(d.bio, isNull);
      expect(d.interests, isEmpty);
      expect(d.maritalStatus, isEmpty);
      expect(d.family.fatherName, isEmpty);
      expect(d.family.familyType, isEmpty);
      expect(d.family.brothers, 0);
      expect(d.horoscope.rasi, isEmpty);
      expect(d.horoscope.nakshatra, isEmpty);
      expect(d.horoscope.matchingEnabled, isFalse);
      expect(d.partnerPreferences.preferredAgeRange, isEmpty);
      expect(d.partnerPreferences.religionPref, isEmpty);
      expect(d.partnerPreferences.incomePref, isEmpty);
    },
  );

  test('tolerates a response without the detail block', () {
    final d = parseProfileDetail(base, card());
    expect(d.family.fatherName, isEmpty);
    expect(d.horoscope.rasi, isEmpty);
    expect(d.partnerPreferences.preferredAgeRange, isEmpty);
  });

  group('ProfileDetailRemoteDataSource', () {
    test('reads the tapped member by id from the lookup endpoint', () async {
      final client = _StubClient(data: card(detail: {'fitness': 'Daily'}));
      final d = await ProfileDetailRemoteDataSource(
        client,
      ).fetchProfileDetail(base);
      expect(client.paths, ['/discover/profiles/u-1']);
      expect(d.lifestyle.fitness, 'Daily');
    });

    // The page renders a thrown error as its error-and-retry state; returning
    // an empty entity instead would show a blank profile as if it were real.
    test('a 404 (no longer visible) throws, never yields an empty profile', () {
      final client = _StubClient(
        status: 404,
        data: {'statusCode': 404, 'message': 'Profile not available.'},
      );
      expect(
        ProfileDetailRemoteDataSource(client).fetchProfileDetail(base),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('a 5xx or a dropped connection propagates as an error', () {
      expect(
        ProfileDetailRemoteDataSource(
          _StubClient(status: 503, data: {'message': 'down'}),
        ).fetchProfileDetail(base),
        throwsA(isA<ApiException>()),
      );
      expect(
        ProfileDetailRemoteDataSource(
          _StubClient(
            throws: DioException(
              requestOptions: RequestOptions(path: '/x'),
              type: DioExceptionType.connectionError,
            ),
          ),
        ).fetchProfileDetail(base),
        throwsA(isA<DioException>()),
      );
    });

    test('an empty 200 body is an error, not an empty profile', () {
      expect(
        ProfileDetailRemoteDataSource(_StubClient()).fetchProfileDetail(base),
        throwsA(isA<ApiException>()),
      );
    });
  });
}

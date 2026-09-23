import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/constants/profile_options.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/registration/data/repositories/registration_repository.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'edit_profile_test_support.dart';

/// Edit Profile's saves **on the wire**: the real [RegistrationRepository]
/// and the real notifier, with only the HTTP transport stubbed.
///
/// Every section editor's save is recorded — method, path, query and JSON
/// body — and compared with a fixture checked into the BACKEND:
/// `backend/apps/api/src/modules/profiles/tests/fixtures/edit-profile-section-payloads.json`.
/// The backend's `edit-profile-section-payloads.spec.ts` feeds those same
/// bodies through its real `ValidationPipe` + DTOs and checks each path and
/// method against the controller's own routing metadata, and
/// `edit-profile-sections.integration.spec.ts` merges them into a real
/// Postgres draft and reads them back. So the two sides are tested against
/// one recorded contract rather than two copies that could drift.
///
/// Regenerate the fixture (only after a deliberate client change):
///   UPDATE_EDIT_PROFILE_FIXTURE=1 flutter test test/features/registration/edit_profile_wire_contract_test.dart
void main() {
  const fixturePath =
      '../backend/apps/api/src/modules/profiles/tests/fixtures/'
      'edit-profile-section-payloads.json';

  /// One visible, registration-collected edit per section, applied to the
  /// saved profile — so the body carries the edit AND every hidden field the
  /// member already had.
  final saved = savedProfile();
  final edits = <String, Future<void> Function(RegistrationNotifier)>{
    'basicDetails': (n) => n.publishBasicDetails(
      saved.basicDetails.copyWith(firstName: 'Meenakshi'),
    ),
    'religionDetails': (n) => n.publishReligionDetails(
      saved.religionDetails.copyWith(subCaste: 'Vathima'),
    ),
    'locationDetails': (n) => n.publishLocationDetails(
      saved.locationDetails.copyWith(
        state: 'Gujarat',
        stateCode: 'IN-GJ',
        city: 'Ahmedabad',
        cityCode: 'IN-GJ-AHMEDABAD',
      ),
    ),
    'educationDetails': (n) => n.publishEducationDetails(
      saved.educationDetails.copyWith(
        qualification: 'M.Tech / M.E',
        company: 'Globex',
        annualIncome: '20 - 50 Lakhs',
      ),
    ),
    'physicalDetails': (n) => n.publishPhysicalDetails(
      saved.physicalDetails.copyWith(height: ProfileOptions.heightLabel(168)),
    ),
    'lifestyleDetails': (n) => n.publishLifestyleDetails(
      saved.lifestyleDetails.copyWith(
        eatingHabit: 'Eggetarian',
        aboutMe: 'I love music and travel.',
      ),
    ),
    'familyDetails': (n) => n.publishFamilyDetails(
      saved.familyDetails.copyWith(familyType: 'Joint'),
    ),
    'horoscopeDetails': (n) => n.publishHoroscopeDetails(
      saved.horoscopeDetails.copyWith(nakshatra: 'Ashwini'),
    ),
  };

  ProviderContainer containerFor(_RecordingApiClient api) {
    final container = ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(
          RegistrationRepository(api),
        ),
      ],
    );
    container
        .read(registrationProvider.notifier)
        .restore(savedProfile(), ProfileFlowMode.edit);
    return container;
  }

  /// JSON round trip, so the comparison is on exactly what goes on the wire.
  Object? wire(Object? value) => jsonDecode(jsonEncode(value));

  test('each section save sends exactly the recorded request', () async {
    final recorded = <String, Object?>{};
    for (final entry in edits.entries) {
      final api = _RecordingApiClient();
      final container = containerFor(api);
      addTearDown(container.dispose);

      await entry.value(container.read(registrationProvider.notifier));

      expect(api.requests, hasLength(1), reason: '${entry.key}: one request');
      recorded[entry.key] = wire(api.requests.single);
    }

    final fixture = File(fixturePath);
    if (Platform.environment['UPDATE_EDIT_PROFILE_FIXTURE'] == '1') {
      fixture.createSync(recursive: true);
      fixture.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(recorded)}\n',
      );
    }
    expect(
      fixture.existsSync(),
      isTrue,
      reason: 'missing ${fixture.absolute.path}',
    );
    final expected = jsonDecode(fixture.readAsStringSync());
    expect(recorded, expected);
  });

  test('the recorded bodies carry the edit and every hidden field', () {
    final fixture =
        jsonDecode(File(fixturePath).readAsStringSync())
            as Map<String, dynamic>;
    Map<String, dynamic> body(String section) =>
        (fixture[section] as Map<String, dynamic>)['body']
            as Map<String, dynamic>;

    expect(body('basicDetails')['firstName'], 'Meenakshi');
    expect(body('basicDetails')['gender'], 'FEMALE');
    expect(body('basicDetails')['maritalStatus'], 'NEVER_MARRIED');
    expect(body('basicDetails')['dob'], '1995-03-21');
    expect(body('religionDetails')['subCaste'], 'Vathima');
    expect(body('religionDetails')['gothra'], 'Kashyapa');
    expect(body('religionDetails')['caste'], 'Brahmin');
    expect(body('religionDetails')['religionCode'], 'HINDU');
    expect(body('locationDetails')['cityCode'], 'IN-GJ-AHMEDABAD');
    expect(body('locationDetails')['pinCode'], '600001');
    expect(body('educationDetails')['company'], 'Globex');
    expect(body('physicalDetails')['weight'], '55');
    expect(body('lifestyleDetails')['smoking'], 'No');
    expect(body('familyDetails')['familyType'], 'Joint');
    for (final entry in fixture.entries) {
      final request = entry.value as Map<String, dynamic>;
      expect(request['method'], 'PATCH', reason: entry.key);
      expect(request['query'], isNull, reason: '${entry.key} materializes');
      expect(
        (request['path'] as String).startsWith('/profiles/draft/'),
        isTrue,
        reason: 'no /v1 or other prefix: ${request['path']}',
      );
    }
  });

  group('a rejected save changes nothing locally', () {
    for (final status in [400, 401, 403, 404, 409]) {
      test(
        'HTTP $status: throws the API\'s message, draft unchanged',
        () async {
          final api = _RecordingApiClient(
            status: status,
            body: {'statusCode': status, 'message': 'rejected $status'},
          );
          final container = containerFor(api);
          addTearDown(container.dispose);

          await expectLater(
            container
                .read(registrationProvider.notifier)
                .publishLocationDetails(
                  saved.locationDetails.copyWith(city: 'Ahmedabad'),
                ),
            throwsA(
              isA<ApiException>()
                  .having((e) => e.statusCode, 'statusCode', status)
                  .having((e) => e.message, 'message', 'rejected $status'),
            ),
          );
          expect(
            container.read(registrationProvider).locationDetails.city,
            'Chennai',
          );
        },
      );
    }

    test('HTTP 500 (Dio raises it): draft unchanged', () async {
      final api = _RecordingApiClient(throwServerError: true);
      final container = containerFor(api);
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(registrationProvider.notifier)
            .publishLocationDetails(
              saved.locationDetails.copyWith(city: 'Ahmedabad'),
            ),
        throwsA(isA<DioException>()),
      );
      expect(
        container.read(registrationProvider).locationDetails.city,
        'Chennai',
      );
    });
  });
}

/// The transport, and nothing more: records every PATCH and answers the way
/// [ApiClient] does — `validateStatus: status < 500`, so a 4xx comes back as a
/// response and a 5xx is raised by Dio.
class _RecordingApiClient implements ApiClient {
  _RecordingApiClient({
    this.status = 200,
    this.body,
    this.throwServerError = false,
  });

  final int status;
  final Map<String, dynamic>? body;
  final bool throwServerError;
  final List<Map<String, Object?>> requests = [];

  @override
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    requests.add({
      'method': 'PATCH',
      'path': path,
      'query': queryParameters,
      'body': data,
    });
    final options = RequestOptions(path: path, method: 'PATCH');
    if (throwServerError) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: options, statusCode: 500),
      );
    }
    return Response<T>(
      requestOptions: options,
      statusCode: status,
      data: (body ?? <String, dynamic>{'data': <String, dynamic>{}}) as T,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

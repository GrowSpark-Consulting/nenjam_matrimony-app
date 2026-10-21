import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/core/router/route_entity_resolvers.dart';
import 'package:nenjam_matrimony/features/discover/data/repositories/profile_by_id_repository.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';

/// Answers every request with a fixed status and JSON body, and records the
/// paths asked for.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.status, this.body);

  final int status;
  final Object body;
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ProfileByIdRepository _repoAnswering(_StubAdapter adapter) {
  final client = ApiClient()..dio.httpClientAdapter = adapter;
  return ProfileByIdRepository(client);
}

void main() {
  group('ProfileByIdRepository', () {
    test('reads the profile from /discover/profiles/:id', () async {
      final adapter = _StubAdapter(200, {
        'id': 'u2',
        'matrimonyId': 'NM-U2',
        'name': 'Meera',
        'age': 27,
        'location': 'Chennai',
        'profession': 'Engineer',
        'photoUrls': <String>[],
      });
      final profile = await _repoAnswering(adapter).get('u 2');

      expect(profile?.id, 'u2');
      expect(profile?.name, 'Meera');
      expect(adapter.paths.single, endsWith('/discover/profiles/u%202'));
    });

    test('a 404 means not available — null, not an error', () async {
      final adapter = _StubAdapter(404, {
        'statusCode': 404,
        'message': 'Profile not available.',
      });
      expect(await _repoAnswering(adapter).get('gone'), isNull);
    });

    test('a 401 is surfaced as an error, never as "not available"', () async {
      final adapter = _StubAdapter(401, {
        'statusCode': 401,
        'message': 'Invalid or expired Firebase ID token.',
      });
      await expectLater(
        _repoAnswering(adapter).get('u2'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('profileByIdProvider', () {
    test('asks the server when the profile is not already in memory', () async {
      final adapter = _StubAdapter(404, {'message': 'Profile not available.'});
      final container = ProviderContainer(
        overrides: [
          profileByIdRepositoryProvider.overrideWithValue(
            _repoAnswering(adapter),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(profileByIdProvider('nobody').future),
        isNull,
      );
      expect(adapter.paths, hasLength(1));
    });
  });
}

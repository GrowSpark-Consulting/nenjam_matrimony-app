import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/features/profile_photos/data/repositories/photo_repository.dart';

/// **`GET /profiles/me/photos` must never blind-cast its body.**
///
/// ApiClient uses `validateStatus: status < 500`, so a 401/403/404 arrives as
/// an ordinary response carrying Nest's error OBJECT — not the array the
/// endpoint returns on success. Asking Dio for a `List<dynamic>` made that
/// object fail an internal cast before any of our code ran, and the caller
/// saw `DioException [unknown]` with a null status instead of the 401 it
/// actually was. Observed in the field as:
///
///   `type '_Map<String, dynamic>' is not a subtype of type 'List<dynamic>?'`
///
/// These pin the shapes the parser has to survive.
void main() {
  PhotoRepository repoReturning(int status, dynamic body) =>
      PhotoRepository(_StubApiClient(status: status, body: body));

  Map<String, dynamic> photoJson(String id, {bool primary = false}) => {
        'id': id,
        'cdnUrl': 'https://cdn.example.test/$id.jpg?sig=redacted',
        'isPrimary': primary,
        'order': 0,
        'isApproved': true,
      };

  group('success bodies', () {
    test('parses the raw array the backend actually returns', () async {
      // PhotoController.list returns PhotoEntity[] with no envelope, and
      // there is no global transform interceptor — this is the real shape.
      final photos = await repoReturning(200, [
        photoJson('a', primary: true),
        photoJson('b'),
      ]).fetchPhotos();

      expect(photos, hasLength(2));
      expect(photos.first.id, 'a');
      expect(photos.first.isPrimary, isTrue);
    });

    test('parses an empty gallery', () async {
      expect(await repoReturning(200, <dynamic>[]).fetchPhotos(), isEmpty);
    });

    test('parses a wrapped object, should the API ever gain an envelope',
        () async {
      // Forward compatibility only: a later `{"photos": [...]}` must not
      // silently read as "this member has no photos".
      for (final key in ['photos', 'data', 'items']) {
        final photos = await repoReturning(200, {
          key: [photoJson('a')],
        }).fetchPhotos();
        expect(photos, hasLength(1), reason: 'wrapper key "$key"');
        expect(photos.single.id, 'a');
      }
    });
  });

  group('error bodies', () {
    test('a 401 object surfaces as PhotoApiException, not a cast failure',
        () async {
      // The exact regression: this body used to blow up inside Dio.
      await expectLater(
        repoReturning(401, {
          'statusCode': 401,
          'message': 'Unauthorized',
          'error': 'Unauthorized',
        }).fetchPhotos(),
        throwsA(
          isA<PhotoApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Unauthorized'),
        ),
      );
    });

    test('carries the backend message from a 400', () async {
      await expectLater(
        repoReturning(400, {
          'statusCode': 400,
          'message': 'Cannot upload more than 6 photos.',
        }).fetchPhotos(),
        throwsA(
          isA<PhotoApiException>().having(
            (e) => e.message,
            'message',
            'Cannot upload more than 6 photos.',
          ),
        ),
      );
    });

    test('an unrecognised 200 body is reported, not read as an empty gallery',
        () async {
      // Returning [] here would tell the member their photos had vanished.
      await expectLater(
        repoReturning(200, {'unexpected': true}).fetchPhotos(),
        throwsA(isA<PhotoApiException>()),
      );
    });
  });
}

/// Serves one canned response for any GET, so the parser is exercised
/// against real [Response] objects without a socket.
class _StubApiClient implements ApiClient {
  _StubApiClient({required this.status, required this.body});

  final int status;
  final dynamic body;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      data: body as T,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import '../models/client_invite_models.dart';

/// The calls of the client invitation flow. Errors surface as `ApiException`
/// (a refusal: branch on `code`) or [ClientInviteNetworkException] (no
/// usable answer).
abstract class ClientInviteRepository {
  Future<ClientOtpChallenge> requestOtp(String phoneE164);
  Future<ClientAccessToken> verifyOtp(String phoneE164, String code);
  Future<List<ClientInvite>> list(ClientAccessToken token);
  Future<ClientAcceptResult> accept(ClientAccessToken token, String id);
  Future<void> reject(ClientAccessToken token, String id);
}

/// Offline, timeout, DNS or an unreadable 5xx: the request may or may not
/// have been processed. Retrying accept is safe (the contract says so).
class ClientInviteNetworkException implements Exception {
  const ClientInviteNetworkException();
  @override
  String toString() => 'ClientInviteNetworkException';
}

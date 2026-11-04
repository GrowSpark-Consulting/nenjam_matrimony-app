import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/services/storage_service.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../data/repositories/api_client_invite_repository.dart';
import '../../domain/models/client_invite_models.dart';
import '../../domain/repositories/client_invite_repository.dart';

/// Own [ApiClient] on purpose: no Firebase `AuthInterceptor` (see
/// [ApiClientInviteRepository]).
final clientInviteRepositoryProvider = Provider<ClientInviteRepository>(
  (ref) => ApiClientInviteRepository(ApiClient()),
);

/// True once any client route answered `403 CLIENT_INVITES_DISABLED`. The
/// entry point on the landing screen hides itself on it. There is no config
/// call for members, so the first request is what tells us.
final clientInvitesDisabledProvider = StateProvider<bool>((ref) => false);

enum ClientInviteStep { phone, code, invites, signedIn }

/// What went wrong, by contract `code`. The page maps these to wording.
enum ClientInviteIssue {
  invalidPhone,
  invalidCode,
  validationFailed,
  otpUnavailable,
  rateLimited,
  otpInvalid,
  otpExpired,
  sessionExpired,
  inviteUnavailable,
  inviteNotFound,
  alreadyMember,
  featureDisabled,
  network,
  noSignInToken,
  signInFailed,
  unexpected,
}

class ClientInviteState {
  const ClientInviteState({
    this.step = ClientInviteStep.phone,
    this.phone,
    this.busy = false,
    this.busyInviteId,
    this.issue,
    this.retryAfterSeconds,
    this.resendAfterSeconds = 30,
    this.invites = const [],
    this.agentDisplayName,
  });

  final ClientInviteStep step;

  /// E.164, as sent. Not secret, but cleared with the rest on sign-in.
  final String? phone;
  final bool busy;
  final String? busyInviteId;
  final ClientInviteIssue? issue;
  final int? retryAfterSeconds;
  final int resendAfterSeconds;
  final List<ClientInvite> invites;

  /// Set after a successful sign-in, for the confirmation line.
  final String? agentDisplayName;

  ClientInviteState copyWith({
    ClientInviteStep? step,
    String? phone,
    bool? busy,
    String? busyInviteId,
    bool clearBusyInvite = false,
    ClientInviteIssue? issue,
    bool clearIssue = false,
    int? retryAfterSeconds,
    int? resendAfterSeconds,
    List<ClientInvite>? invites,
    String? agentDisplayName,
  }) => ClientInviteState(
    step: step ?? this.step,
    phone: phone ?? this.phone,
    busy: busy ?? this.busy,
    busyInviteId: clearBusyInvite ? null : (busyInviteId ?? this.busyInviteId),
    issue: clearIssue ? null : (issue ?? this.issue),
    retryAfterSeconds: clearIssue
        ? null
        : (retryAfterSeconds ?? this.retryAfterSeconds),
    resendAfterSeconds: resendAfterSeconds ?? this.resendAfterSeconds,
    invites: invites ?? this.invites,
    agentDisplayName: agentDisplayName ?? this.agentDisplayName,
  );
}

/// Phone → code → invitations → accept / reject → Firebase sign-in.
///
/// **Stops at sign-in.** Nothing here fetches `/profiles/draft`, resumes the
/// registration wizard or navigates anywhere after sign-in: the destination
/// after acceptance is a pending product/backend decision.
///
/// The CLIENT token lives only in [_token] — a private field of this
/// notifier, not in [state], not in storage, never logged.
class ClientInviteController extends AutoDisposeNotifier<ClientInviteState> {
  ClientInviteToken? _token;

  @override
  ClientInviteState build() {
    // Leaving the flow (or the app closing) drops the token with it.
    ref.onDispose(() => _token = null);
    return const ClientInviteState();
  }

  ClientInviteRepository get _repo => ref.read(clientInviteRepositoryProvider);

  /// `+919876543210`, or a bare 10-digit Indian mobile (gets `+91`). Null
  /// when it cannot be a phone number.
  static String? normalizePhone(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (RegExp(r'^[6-9]\d{9}$').hasMatch(cleaned)) return '+91$cleaned';
    if (RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(cleaned)) return cleaned;
    return null;
  }

  Future<void> requestCode(String rawPhone) async {
    if (state.busy) return;
    final phone = normalizePhone(rawPhone);
    if (phone == null) {
      state = state.copyWith(issue: ClientInviteIssue.invalidPhone);
      return;
    }
    state = state.copyWith(busy: true, clearIssue: true);
    try {
      final challenge = await _repo.requestOtp(phone);
      state = state.copyWith(
        step: ClientInviteStep.code,
        phone: phone,
        busy: false,
        resendAfterSeconds: challenge.resendAfterSeconds,
      );
    } catch (e) {
      _fail(e);
    }
  }

  /// Another code for the same phone (the newest one counts).
  Future<void> resend() async {
    final phone = state.phone;
    if (phone != null) await requestCode(phone);
  }

  Future<void> verifyCode(String rawCode) async {
    if (state.busy) return;
    final phone = state.phone;
    final code = rawCode.trim();
    if (phone == null || !RegExp(r'^[0-9]{4,8}$').hasMatch(code)) {
      state = state.copyWith(issue: ClientInviteIssue.invalidCode);
      return;
    }
    state = state.copyWith(busy: true, clearIssue: true);
    try {
      _token = await _repo.verifyOtp(phone, code);
      final invites = await _repo.list(_token!);
      state = state.copyWith(
        step: ClientInviteStep.invites,
        busy: false,
        invites: invites,
      );
    } catch (e) {
      _fail(e);
    }
  }

  /// Reloads the list (after a retry-able failure).
  Future<void> reload() async {
    final token = _token;
    if (token == null || state.busy) return;
    state = state.copyWith(busy: true, clearIssue: true);
    try {
      state = state.copyWith(busy: false, invites: await _repo.list(token));
    } catch (e) {
      _fail(e);
    }
  }

  /// Accept, then exchange the custom token. Safe to call again after any
  /// failure with the same CLIENT token: the server answers 200 with a fresh
  /// custom token for an invitation she already accepted.
  Future<void> accept(String id) async {
    final token = _token;
    if (token == null || state.busy) return;
    state = state.copyWith(busy: true, busyInviteId: id, clearIssue: true);
    try {
      final result = await _repo.accept(token, id);
      final custom = result.firebaseCustomToken;
      if (custom == null) {
        // Contract: only valid once she already holds a Firebase session.
        // No other way to sign her in is invented here.
        if (_alreadySignedIn()) {
          _signedIn(result);
        } else {
          state = state.copyWith(
            busy: false,
            clearBusyInvite: true,
            issue: ClientInviteIssue.noSignInToken,
          );
        }
        return;
      }
      try {
        await ref
            .read(firebaseAuthServiceProvider)
            .signInWithCustomToken(custom);
      } catch (_) {
        state = state.copyWith(
          busy: false,
          clearBusyInvite: true,
          issue: ClientInviteIssue.signInFailed,
        );
        return;
      }
      _signedIn(result);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> reject(String id) async {
    final token = _token;
    if (token == null || state.busy) return;
    state = state.copyWith(busy: true, busyInviteId: id, clearIssue: true);
    try {
      await _repo.reject(token, id);
      state = state.copyWith(
        busy: false,
        clearBusyInvite: true,
        invites: [
          for (final i in state.invites)
            if (i.id != id) i,
        ],
      );
    } catch (e) {
      _fail(e);
    }
  }

  /// Back to the phone screen, forgetting the token.
  void startOver() {
    _token = null;
    state = const ClientInviteState();
  }

  bool _alreadySignedIn() {
    try {
      return ref.read(firebaseAuthServiceProvider).currentUser != null;
    } catch (_) {
      return false;
    }
  }

  /// She is an ordinary member now: the temporary CLIENT state is dropped.
  /// No navigation, no profile loading: see the class comment.
  void _signedIn(ClientAcceptResult result) {
    _token = null;
    // The backend accepted: this profile was created for her by an agent, so
    // it never asks her for a selfie. Best-effort — storage not initialised
    // (a test harness) must not break sign-in.
    unawaited(
      storageService.setReferralCreatedProfile(true).catchError((Object _) {}),
    );
    state = ClientInviteState(
      step: ClientInviteStep.signedIn,
      agentDisplayName: result.agentDisplayName,
    );
  }

  void _fail(Object e) {
    var issue = ClientInviteIssue.unexpected;
    int? retryAfter;
    var dropToken = false;
    var dropToPhone = false;

    if (e is ClientInviteNetworkException) {
      issue = ClientInviteIssue.network;
    } else if (e is ApiException) {
      retryAfter = e.retryAfterSeconds;
      switch (e.code) {
        case 'CLIENT_INVITES_DISABLED':
          issue = ClientInviteIssue.featureDisabled;
          ref.read(clientInvitesDisabledProvider.notifier).state = true;
        case 'OTP_DELIVERY_UNAVAILABLE':
          issue = ClientInviteIssue.otpUnavailable;
        case 'RATE_LIMITED':
          issue = ClientInviteIssue.rateLimited;
        case 'OTP_INVALID':
          issue = ClientInviteIssue.otpInvalid;
        case 'OTP_EXPIRED':
          issue = ClientInviteIssue.otpExpired;
        case 'UNAUTHORIZED' || 'TOKEN_EXPIRED':
          issue = ClientInviteIssue.sessionExpired;
          dropToPhone = true;
        case 'INVITE_NOT_FOUND':
          issue = ClientInviteIssue.inviteNotFound;
        case 'INVITE_UNAVAILABLE':
          issue = ClientInviteIssue.inviteUnavailable;
        case 'ALREADY_MEMBER':
          issue = ClientInviteIssue.alreadyMember;
          dropToken = true;
        case 'VALIDATION_FAILED':
          issue = ClientInviteIssue.validationFailed;
        default:
          // CONCURRENT_CHANGE and anything unlisted: transient, retry.
          if (e.statusCode == 401) {
            issue = ClientInviteIssue.sessionExpired;
            dropToPhone = true;
          } else if (e.statusCode == 409 || (e.statusCode ?? 0) >= 500) {
            issue = ClientInviteIssue.network;
          }
      }
    } else {
      issue = ClientInviteIssue.network;
    }

    if (dropToken || dropToPhone) _token = null;
    state = ClientInviteState(
      step: dropToPhone ? ClientInviteStep.phone : state.step,
      phone: dropToPhone ? null : state.phone,
      resendAfterSeconds: state.resendAfterSeconds,
      invites: dropToPhone || dropToken ? const [] : state.invites,
      issue: issue,
      retryAfterSeconds: retryAfter,
    );
  }
}

/// Type alias kept private to this feature: the token is a
/// `ClientAccessToken`, named so a grep for "token" finds the one place.
typedef ClientInviteToken = ClientAccessToken;

final clientInviteControllerProvider =
    NotifierProvider.autoDispose<ClientInviteController, ClientInviteState>(
      ClientInviteController.new,
    );

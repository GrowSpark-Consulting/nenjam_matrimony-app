import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../domain/models/client_invite_models.dart';
import '../providers/client_invite_providers.dart';

/// "Added by an agent? Confirm here": phone, code, invitations, accept or
/// decline. After sign-in it opens the member home ([RouteNames.discover]).
///
/// English only for now (the Tamil copy is not supplied yet, as with the
/// guide's status labels). The test environment uses test codes, so nothing
/// here promises that an SMS was sent.
class ClientInvitePage extends ConsumerStatefulWidget {
  const ClientInvitePage({super.key});

  @override
  ConsumerState<ClientInvitePage> createState() => _ClientInvitePageState();
}

class _ClientInvitePageState extends ConsumerState<ClientInvitePage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  Timer? _ticker;
  int _resendIn = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startResendCountdown(int seconds) {
    _ticker?.cancel();
    setState(() => _resendIn = seconds);
    if (seconds <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) t.cancel();
    });
  }

  Future<void> _sendCode({bool resend = false}) async {
    final c = ref.read(clientInviteControllerProvider.notifier);
    if (resend) {
      await c.resend();
    } else {
      await c.requestCode(_phone.text);
    }
    final s = ref.read(clientInviteControllerProvider);
    if (s.step == ClientInviteStep.code && s.issue == null) {
      _startResendCountdown(s.resendAfterSeconds);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientInviteControllerProvider);
    final c = ref.read(clientInviteControllerProvider.notifier);

    // Signed in as an ordinary member: open the home page. Never the
    // registration wizard.
    ref.listen<ClientInviteState>(clientInviteControllerProvider, (prev, next) {
      if (prev?.step != ClientInviteStep.signedIn &&
          next.step == ClientInviteStep.signedIn) {
        context.go(RouteNames.discover);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Added by an agent'),
        leading: state.step == ClientInviteStep.signedIn
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  c.startOver();
                  context.go(RouteNames.registrationLanding);
                },
              ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (state.issue != null) _IssueBanner(state: state),
                ..._body(context, state, c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    ClientInviteState state,
    ClientInviteController c,
  ) {
    switch (state.step) {
      case ClientInviteStep.phone:
        return [
          Text(
            'Enter the mobile number your agent used.',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          NmTextField(
            label: 'Mobile number',
            hint: '+91 98765 43210',
            controller: _phone,
            keyboardType: TextInputType.phone,
            enabled: !state.busy,
            onSubmitted: (_) => _sendCode(),
          ),
          const SizedBox(height: AppSpacing.md),
          NmGradientButton(
            label: 'Send code',
            isLoading: state.busy,
            onPressed: state.busy ? null : _sendCode,
          ),
        ];
      case ClientInviteStep.code:
        return [
          Text(
            'Enter the code for ${state.phone}.',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          NmTextField(
            label: 'Code',
            controller: _code,
            keyboardType: TextInputType.number,
            enabled: !state.busy,
            onSubmitted: (_) => c.verifyCode(_code.text),
          ),
          const SizedBox(height: AppSpacing.md),
          NmGradientButton(
            label: 'Verify',
            isLoading: state.busy,
            onPressed: state.busy ? null : () => c.verifyCode(_code.text),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: (state.busy || _resendIn > 0)
                ? null
                : () => _sendCode(resend: true),
            child: Text(
              _resendIn > 0
                  ? 'Send a new code in $_resendIn s'
                  : 'Send a new code',
            ),
          ),
          TextButton(
            onPressed: state.busy ? null : c.startOver,
            child: const Text('Use a different number'),
          ),
        ];
      case ClientInviteStep.invites:
        if (state.invites.isEmpty && state.issue == null) {
          return [
            Text(
              "There's no invitation for this number.",
              style: AppTypography.titleSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            NmGradientButton(
              label: 'Sign up as usual',
              onPressed: () {
                c.startOver();
                context.go(RouteNames.registrationLanding);
              },
            ),
          ];
        }
        return [
          for (final invite in state.invites)
            _InviteCard(
              invite: invite,
              busy: state.busy,
              working: state.busyInviteId == invite.id,
              onAccept: () => c.accept(invite.id),
              onReject: () async {
                final yes = await _confirm(
                  "Decline ${invite.agentDisplayName}'s invitation?",
                  "They won't be able to add your number again.",
                  'Decline',
                );
                if (yes) await c.reject(invite.id);
              },
            ),
        ];
      case ClientInviteStep.signedIn:
        final agent = state.agentDisplayName;
        return [
          Icon(
            Icons.check_circle_rounded,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            "You're signed in.",
            textAlign: TextAlign.center,
            style: AppTypography.titleSmall,
          ),
          if (agent != null)
            Text(
              '$agent added you to Nenjam.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
        ];
    }
  }
}

class _IssueBanner extends ConsumerWidget {
  const _IssueBanner({required this.state});
  final ClientInviteState state;

  static String _text(ClientInviteState s) {
    final wait = s.retryAfterSeconds;
    switch (s.issue!) {
      case ClientInviteIssue.invalidPhone:
        return 'Enter a valid mobile number.';
      case ClientInviteIssue.invalidCode:
        return 'Enter the code we sent.';
      case ClientInviteIssue.validationFailed:
        return 'Please check what you entered and try again.';
      case ClientInviteIssue.otpUnavailable:
        return "We can't send a code to this number yet. Only approved test numbers work for now.";
      case ClientInviteIssue.rateLimited:
        return wait != null
            ? 'Too many attempts. Try again in $wait seconds.'
            : 'Too many attempts. Please wait a little and try again.';
      case ClientInviteIssue.otpInvalid:
        return "That code isn't right.";
      case ClientInviteIssue.otpExpired:
        return 'That code has expired. Request a new one.';
      case ClientInviteIssue.sessionExpired:
        return 'Your confirmation timed out. Please verify your number again.';
      case ClientInviteIssue.inviteUnavailable:
        return 'This invitation has expired or was closed.';
      case ClientInviteIssue.inviteNotFound:
        return "This invitation isn't available.";
      case ClientInviteIssue.alreadyMember:
        return 'This number already has a Nenjam account. Please sign in.';
      case ClientInviteIssue.featureDisabled:
        return "This isn't available right now.";
      case ClientInviteIssue.network:
        return "We couldn't reach the server. Please try again.";
      case ClientInviteIssue.noSignInToken:
        return "We couldn't sign you in. Please try again.";
      case ClientInviteIssue.signInFailed:
        return "You're accepted, but signing in didn't finish. Tap Accept again to retry.";
      case ClientInviteIssue.unexpected:
        return 'Something went wrong. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final issue = state.issue!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _text(state),
            style: AppTypography.bodyMedium.copyWith(color: colors.error),
          ),
          if (issue == ClientInviteIssue.alreadyMember)
            TextButton(
              onPressed: () => context.go(RouteNames.login),
              child: const Text('Go to sign in'),
            ),
          if (issue == ClientInviteIssue.inviteUnavailable ||
              issue == ClientInviteIssue.inviteNotFound ||
              issue == ClientInviteIssue.network &&
                  state.step == ClientInviteStep.invites &&
                  state.invites.isEmpty)
            TextButton(
              onPressed: ref
                  .read(clientInviteControllerProvider.notifier)
                  .reload,
              child: const Text('Reload'),
            ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.busy,
    required this.working,
    required this.onAccept,
    required this.onReject,
  });

  final ClientInvite invite;
  final bool busy;
  final bool working;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  static String _words(String camel) {
    final spaced = camel.replaceAllMapped(
      RegExp('([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]!.toLowerCase()}',
    );
    return spaced.isEmpty
        ? spaced
        : spaced[0].toUpperCase() + spaced.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final pct = invite.discountPercent;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${invite.agentDisplayName} added you',
              style: AppTypography.titleSmall,
            ),
            if (pct != null) Text('$pct% off your first plan'),
            if (invite.expiresOn.isNotEmpty)
              Text('Answer by ${invite.expiresOn}'),
            for (final section in invite.sections) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_words(section.key), style: AppTypography.titleSmall),
              for (final row in section.rows)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    '${_words(row.label.split('.').last)}: ${row.value}',
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.lg),
            NmGradientButton(
              label: 'Accept',
              isLoading: working,
              onPressed: busy ? null : onAccept,
            ),
            TextButton(
              onPressed: busy ? null : onReject,
              child: const Text('Decline'),
            ),
          ],
        ),
      ),
    );
  }
}

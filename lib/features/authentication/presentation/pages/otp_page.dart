import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/inputs/otp_input.dart';

/// OTP Verification Page.
///
/// Accepts either phone or email channel from GoRouter [extra]:
/// ```dart
/// context.push(RouteNames.otp, extra: {'identifier': '+91 98765…', 'channel': 'phone'});
/// ```
/// Supports 6-digit input, clipboard paste, 60-second countdown, and resend.
class OtpPage extends StatefulWidget {
  const OtpPage({super.key});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  String _otp = '';
  bool _isLoading = false;
  int _secondsRemaining = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    setState(() => _secondsRemaining = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  void _onVerify() {
    if (_otp.length == 6) {
      setState(() => _isLoading = true);
      final extra = _parseExtra(context);
      final flow = extra['flow'] ?? 'login';
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) {
          setState(() => _isLoading = false);
          if (flow == 'signup') {
            context.go(RouteNames.profile);
          } else {
            context.go(RouteNames.home);
          }
        }
      });
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────

  Map<String, String> _parseExtra(BuildContext context) {
    final extra = GoRouterState.of(context).extra;
    if (extra is Map) {
      return {
        'identifier': extra['identifier']?.toString() ?? 'your number',
        'channel': extra['channel']?.toString() ?? 'phone',
        'flow': extra['flow']?.toString() ?? 'login',
      };
    }
    if (extra is String) return {'identifier': extra, 'channel': 'phone', 'flow': 'login'};
    return {'identifier': 'your number', 'channel': 'phone', 'flow': 'login'};
  }

  String _channelDescription(
      String channel, String identifier, bool isDark) {
    if (channel == 'email') {
      return 'We sent a 6-digit code to $identifier';
    }
    return 'We sent a 6-digit code to +91 $identifier';
  }

  IconData _channelIcon(String channel) =>
      channel == 'email' ? Icons.mail_outline_rounded : Icons.phone_rounded;

  String _formatTimer() =>
      '${(_secondsRemaining ~/ 60).toString().padLeft(2, '0')}:'
      '${(_secondsRemaining % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final extra = _parseExtra(context);
    final identifier = extra['identifier'] ?? 'your number';
    final channel = extra['channel'] ?? 'phone';

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: Text(
          'Verify ${channel == 'email' ? 'Email' : 'Mobile'}',
          style: AppTypography.titleMedium
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // ─── Headline ──────────────────────────────────────
              Text(
                'Enter Verification\nCode',
                style: AppTypography.headlineLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),

              // ─── Channel indicator ─────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceVariantDark
                      : AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _channelIcon(channel),
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _channelDescription(channel, identifier, isDark),
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // ─── OTP Input (with built-in paste button) ────────
              NmOtpInput(
                length: 6,
                onCompleted: (value) {
                  _otp = value;
                  _onVerify();
                },
                onChanged: (value) => setState(() => _otp = value),
              ),
              const SizedBox(height: 40),

              // ─── Verify Button ─────────────────────────────────
              NmGradientButton(
                label: 'Verify & Continue',
                icon: Icons.check_circle_outline_rounded,
                onPressed: _otp.length == 6 ? _onVerify : null,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 32),

              // ─── Resend / Countdown ────────────────────────────
              Center(
                child: _secondsRemaining > 0
                    ? Column(
                        children: [
                          Text(
                            'Resend OTP in',
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiaryLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatTimer(),
                            style: AppTypography.titleLarge.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      )
                    : TextButton.icon(
                        onPressed: _startTimer,
                        icon: const Icon(
                            Icons.refresh_rounded, size: 18),
                        label: const Text('Resend OTP'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          textStyle: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

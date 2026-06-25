import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/inputs/otp_input.dart';

/// OTP Verification Page.
class OtpPage extends StatefulWidget {
  const OtpPage({super.key});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  String _otp = '';
  bool _isLoading = false;

  void _onVerify() {
    if (_otp.length == 6) {
      setState(() => _isLoading = true);
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          setState(() => _isLoading = false);
          context.go(RouteNames.home);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                'Enter Verification\nCode',
                style: AppTypography.headlineLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We have sent a 6-digit verification code to your mobile number.',
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 40),
              NmOtpInput(
                length: 6,
                onCompleted: (value) {
                  _otp = value;
                  _onVerify();
                },
                onChanged: (value) => _otp = value,
              ),
              const SizedBox(height: 40),
              NmPrimaryButton(
                label: 'Verify & Continue',
                onPressed: _otp.length == 6 ? _onVerify : null,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 32),
              Center(
                child: TextButton(
                  onPressed: () {},
                  child: Text(
                    'Resend OTP Code',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
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

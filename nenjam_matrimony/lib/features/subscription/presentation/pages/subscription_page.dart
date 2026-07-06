import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/primary_button.dart';

/// Payment checkout page placeholder for subscription.
class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order Summary', style: AppTypography.titleLarge),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gold Luxury Plan (3 Months)'),
                trailing: Text('₹4,999', style: AppTypography.titleMedium),
              ),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Amount Payable', style: AppTypography.titleMedium),
                  Text('₹4,999',
                      style: AppTypography.headlineSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
              const Spacer(),
              NmPrimaryButton(
                label: 'Pay ₹4,999 Securely',
                onPressed: () {
                  // Show success and go home
                  context.go(RouteNames.home);
                },
                icon: Icons.lock_outline_rounded,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

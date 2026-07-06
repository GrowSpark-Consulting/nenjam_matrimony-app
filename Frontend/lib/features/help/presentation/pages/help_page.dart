import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Help & Support center screen.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Frequently Asked Questions', style: AppTypography.titleLarge),
            const SizedBox(height: 16),
            const _FaqItem(
              question: 'How does AI matching work?',
              answer:
                  'Our AI evaluates over 50 compatibility markers including lifestyle, horoscope, and career preferences.',
            ),
            const _FaqItem(
              question: 'Is my phone number visible to everyone?',
              answer:
                  'No. Only premium members whom you have accepted can view your contact details.',
            ),
            const _FaqItem(
              question: 'How do I upgrade to Premium VIP?',
              answer:
                  'Go to the Premium tab from the bottom menu or navigation drawer to explore luxury membership plans.',
            ),
            const SizedBox(height: 32),
            Text('Still Need Help?', style: AppTypography.titleLarge),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.support_agent_rounded),
              title: const Text('Chat with Support'),
              subtitle: const Text('Available 24/7 for VIP members'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Email Us'),
              subtitle: const Text('support@nenjammatrimony.com'),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(question, style: AppTypography.titleSmall),
      childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      children: [
        Text(answer, style: AppTypography.bodyMedium),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../domain/models/prompt_bank_item.dart';

/// Answer Screen — shows the selected prompt, a text input with a
/// character limit, and a Save button. Pops a [PromptAnswer] on save.
class AnswerPromptPage extends StatefulWidget {
  final PromptBankItem prompt;
  final String initialAnswer;

  const AnswerPromptPage({
    super.key,
    required this.prompt,
    this.initialAnswer = '',
  });

  static const int maxLength = 150;

  @override
  State<AnswerPromptPage> createState() => _AnswerPromptPageState();
}

class _AnswerPromptPageState extends State<AnswerPromptPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAnswer);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(
      PromptAnswer(
        promptId: widget.prompt.id,
        promptText: widget.prompt.promptText,
        answerText: text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final category = widget.prompt.category;

    return Scaffold(
      appBar: AppBar(title: const Text('Your Answer')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: AppSpacing.cardPaddingLarge,
                decoration: AppDecorations.card(isDark: isDark),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: category.accentColor.withValues(alpha: 0.12),
                        borderRadius: AppSpacing.borderRadiusMd,
                      ),
                      child: Icon(category.icon, color: category.accentColor),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        widget.prompt.promptText,
                        style: AppTypography.titleMedium
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              NmTextField(
                controller: _controller,
                hint: 'Write your answer…',
                maxLines: 4,
                maxLength: AnswerPromptPage.maxLength,
                autovalidateMode: AutovalidateMode.disabled,
                onChanged: (_) => setState(() {}),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_controller.text.length}/${AnswerPromptPage.maxLength}',
                  style: AppTypography.labelSmall.copyWith(
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              NmGradientButton(
                label: 'Save',
                useGoldGradient: true,
                onPressed: _controller.text.trim().isEmpty ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

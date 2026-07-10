import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/prompt_bank_item.dart';
import '../providers/profile_prompt_provider.dart';
import 'answer_prompt_page.dart';

/// Choose Prompt Screen — horizontal category chips, rounded cards with a
/// leading colorful icon, prompt text, and a trailing arrow. Tapping a
/// prompt opens [AnswerPromptPage]; the answer bubbles back here and the
/// (possibly extended) selection is popped back to the caller.
class ChoosePromptPage extends ConsumerStatefulWidget {
  /// The user's current selection (0-3), passed in via GoRouter `extra` so
  /// this screen knows what's already answered and can enforce the max-3
  /// limit without depending on any shared/global state.
  final List<PromptAnswer> currentSelection;

  const ChoosePromptPage({super.key, required this.currentSelection});

  @override
  ConsumerState<ChoosePromptPage> createState() => _ChoosePromptPageState();
}

class _ChoosePromptPageState extends ConsumerState<ChoosePromptPage> {
  PromptCategory? _selectedCategory;
  late List<PromptAnswer> _selection;

  @override
  void initState() {
    super.initState();
    _selection = List.of(widget.currentSelection);
  }

  Future<void> _pickPrompt(PromptBankItem prompt) async {
    final answer = await Navigator.of(context).push<PromptAnswer>(
      MaterialPageRoute(builder: (_) => AnswerPromptPage(prompt: prompt)),
    );
    if (answer == null || !mounted) return;
    setState(() => _selection = [..._selection, answer]);
    if (!mounted) return;
    context.pop(_selection);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bankAsync = ref.watch(promptBankProvider(_selectedCategory));
    final chosenIds = _selection.map((a) => a.promptId).toSet();
    final atLimit = _selection.length >= 3;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a Prompt')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                children: [
                  _CategoryChip(
                    label: 'All',
                    selected: _selectedCategory == null,
                    color: AppColors.primary,
                    onTap: () => setState(() => _selectedCategory = null),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  for (final category in PromptCategory.values) ...[
                    _CategoryChip(
                      label: category.label,
                      selected: _selectedCategory == category,
                      color: category.accentColor,
                      icon: category.icon,
                      onTap: () =>
                          setState(() => _selectedCategory = category),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            if (atLimit)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base, vertical: AppSpacing.sm),
                child: Text(
                  "You've picked 3 prompts — the maximum. Remove one to add another.",
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                  ),
                ),
              ),
            Expanded(
              child: bankAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text('Could not load prompts.')),
                data: (prompts) {
                  final available =
                      prompts.where((p) => !chosenIds.contains(p.id)).toList();
                  if (available.isEmpty) {
                    return const Center(
                      child: Text('No more prompts in this category.'),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.base, 0, AppSpacing.base, AppSpacing.xl2),
                    itemCount: available.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final prompt = available[index];
                      return _PromptCard(
                        prompt: prompt,
                        isDark: isDark,
                        onTap: atLimit ? null : () => _pickPrompt(prompt),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: selected ? color : null),
            const SizedBox(width: 4),
          ],
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: color.withValues(alpha: 0.14),
      labelStyle: AppTypography.labelMedium.copyWith(
        color: selected ? color : null,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selected ? color.withValues(alpha: 0.4) : AppColors.dividerLight,
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  final PromptBankItem prompt;
  final bool isDark;
  final VoidCallback? onTap;

  const _PromptCard({required this.prompt, required this.isDark, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: AppSpacing.borderRadiusXl,
      child: InkWell(
        borderRadius: AppSpacing.borderRadiusXl,
        onTap: onTap,
        child: Container(
          padding: AppSpacing.cardPaddingLarge,
          decoration: AppDecorations.card(isDark: isDark).copyWith(
            color: onTap == null
                ? (isDark
                    ? AppColors.surfaceVariantDark
                    : AppColors.surfaceVariantLight)
                : (isDark ? AppColors.cardDark : AppColors.cardLight),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: prompt.category.accentColor.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderRadiusMd,
                ),
                child: Icon(prompt.category.icon,
                    color: prompt.category.accentColor),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  prompt.promptText,
                  style: AppTypography.bodyLarge
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

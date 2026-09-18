import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/dialogs/app_dialogs.dart';
import '../../domain/models/prompt_bank_item.dart';
import '../providers/profile_prompt_provider.dart';
import 'answer_prompt_page.dart';
import '../../../../l10n/app_localizations.dart';

/// Choose Prompt Screen — horizontal category chips, rounded cards with a
/// leading colorful icon, prompt text, and a trailing arrow. Tapping a
/// prompt opens [AnswerPromptPage]; the answer bubbles back here and the
/// (possibly extended) selection is popped back to the caller.
///
/// Also where an already-answered prompt is removed (the "Your Prompts"
/// section above the pickable bank): this is the only screen that ever
/// holds the user's full current selection in memory, so it is the natural
/// place for both "add" and "remove" to live, matching
/// [AppLocalizations.promptsMaxReached]'s existing copy ("Remove one to add
/// another"), which already anticipated this and had no way to do it until
/// now. Deletion calls `DELETE /profiles/prompts/me/:promptId` directly
/// through the repository the moment it's confirmed — it does not wait for
/// this screen's own pop-and-PUT-replace flow, so the removal is real and
/// immediate even if the user backs out without adding anything else. The
/// caller (ProfileIntelligencePage) invalidates `myPromptsProvider`
/// unconditionally on return, which is what keeps the hub's summary count
/// in sync afterward.
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

  /// The promptId currently being deleted, or null. Disables just that
  /// row's delete button — not the whole screen — while its request is in
  /// flight, and is the guard against a double-tap firing a second DELETE
  /// for the same prompt.
  String? _deletingPromptId;

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

  Future<void> _deletePrompt(PromptAnswer answer) async {
    if (_deletingPromptId != null) return; // one delete in flight at a time

    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialogs.showDelete(
      context,
      title: l10n.promptsDeleteConfirmTitle,
      message: l10n.promptsDeleteConfirmMessage,
    );
    if (!(confirmed ?? false)) return;
    if (!mounted) return;

    setState(() => _deletingPromptId = answer.promptId);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(profilePromptRepositoryProvider)
          .deletePrompt(answer.promptId);
      if (!mounted) return;
      // Remove immediately on confirmed success — the other prompts are
      // untouched, and nothing here forces a full profile/prompt-bank
      // reload; ProfileIntelligencePage's unconditional
      // `ref.invalidate(myPromptsProvider)` on return is what reconciles
      // the hub's own summary afterward.
      setState(() {
        _selection = _selection.where((a) => a.promptId != answer.promptId).toList();
        _deletingPromptId = null;
      });
      messenger.showSnackBar(SnackBar(content: Text(l10n.promptsDeleteSuccess)));
    } catch (error) {
      if (!mounted) return;
      // The prompt stays visible — deletion failed, so nothing changed on
      // the backend either. Tapping delete again retries.
      setState(() => _deletingPromptId = null);
      messenger.showSnackBar(
        SnackBar(content: Text(_promptDeleteErrorMessage(l10n, error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bankAsync = ref.watch(promptBankProvider(_selectedCategory));
    final chosenIds = _selection.map((a) => a.promptId).toSet();
    final atLimit = _selection.length >= 3;

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).promptsChooseTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.sm),
            if (_selection.isNotEmpty) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: Text(
                  AppLocalizations.of(context).promptsYourPromptsTitle,
                  style: AppTypography.titleSmall
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: Column(
                  children: [
                    for (final answer in _selection) ...[
                      _MyPromptCard(
                        answer: answer,
                        isDeleting: _deletingPromptId == answer.promptId,
                        onDelete: () => _deletePrompt(answer),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                children: [
                  _CategoryChip(
                    label: AppLocalizations.of(context).commonAll,
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
                  AppLocalizations.of(context).promptsMaxReached,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiaryLight,
                  ),
                ),
              ),
            Expanded(
              child: bankAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    Center(child: Text(AppLocalizations.of(context).promptsLoadError)),
                data: (prompts) {
                  final available =
                      prompts.where((p) => !chosenIds.contains(p.id)).toList();
                  if (available.isEmpty) {
                    return Center(
                      child: Text(AppLocalizations.of(context).promptsCategoryEmpty),
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

/// Maps a thrown prompt-delete error to user-facing copy — same shape as
/// `safetyErrorMessage` (statusCode-keyed, generic fallback), kept local
/// since this is this screen's only mutating error path.
String _promptDeleteErrorMessage(AppLocalizations l10n, Object error) {
  if (error is ApiException) {
    switch (error.statusCode) {
      case null:
        return l10n.promptsDeleteErrorNetwork;
      case 401:
        return l10n.promptsDeleteErrorUnauthorized;
      case 404:
        return l10n.promptsDeleteErrorNotFound;
      default:
        return l10n.promptsDeleteErrorGeneric;
    }
  }
  return l10n.promptsDeleteErrorGeneric;
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
  final VoidCallback? onTap;

  const _PromptCard({required this.prompt, this.onTap});

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
          decoration: AppDecorations.card().copyWith(
            color: onTap == null
                ? AppColors.surfaceVariantLight
                : AppColors.cardLight,
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
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.textTertiaryLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One already-answered prompt in the "Your Prompts" section — same card
/// shell as [_PromptCard] (icon, text, trailing affordance) so the two
/// lists read as one visual language, but not tappable to navigate: the
/// trailing affordance is a delete action instead of a forward arrow, and
/// the answer text is shown as well as the prompt itself, since this is the
/// user's own saved content, not a pickable bank entry.
class _MyPromptCard extends StatelessWidget {
  final PromptAnswer answer;
  final bool isDeleting;
  final VoidCallback onDelete;

  const _MyPromptCard({
    required this.answer,
    required this.isDeleting,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPaddingLarge,
      decoration: AppDecorations.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  answer.promptText,
                  style: AppTypography.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  answer.answerText,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondaryLight),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 32,
            height: 32,
            child: isDeleting
                ? const Padding(
                    padding: EdgeInsets.all(6),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: AppColors.error,
                    ),
                    onPressed: onDelete,
                  ),
          ),
        ],
      ),
    );
  }
}

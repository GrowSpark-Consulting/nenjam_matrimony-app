import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Prompt bank categories (Hinge/Jeevansathi-style). Frontend-only grouping,
/// owned entirely by this independent feature — no coupling to registration
/// or backend enums.
enum PromptCategory { personality, marriageCompatibility, family, career }

extension PromptCategoryDisplay on PromptCategory {
  String get label => switch (this) {
    PromptCategory.personality => 'Personality',
    PromptCategory.marriageCompatibility => 'Marriage & Compatibility',
    PromptCategory.family => 'Family',
    PromptCategory.career => 'Career',
  };

  IconData get icon => switch (this) {
    PromptCategory.personality => Icons.emoji_emotions_rounded,
    PromptCategory.marriageCompatibility => Icons.favorite_rounded,
    PromptCategory.family => Icons.family_restroom_rounded,
    PromptCategory.career => Icons.work_rounded,
  };

  Color get accentColor => switch (this) {
    PromptCategory.personality => AppColors.secondary,
    PromptCategory.marriageCompatibility => AppColors.liked,
    PromptCategory.family => AppColors.info,
    PromptCategory.career => AppColors.primary,
  };
}

/// A single pickable prompt from the bank (unanswered).
class PromptBankItem {
  final String id;
  final PromptCategory category;
  final String promptText;

  const PromptBankItem({
    required this.id,
    required this.category,
    required this.promptText,
  });
}

/// A user's chosen prompt + written answer.
class PromptAnswer {
  final String promptId;
  final String promptText;
  final String answerText;

  const PromptAnswer({
    required this.promptId,
    required this.promptText,
    required this.answerText,
  });
}

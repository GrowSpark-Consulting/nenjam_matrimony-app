import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../theme/tokens/app_animation_tokens.dart';

/// Elegant search bar with filter action.
///
/// Stateful (but with the same external API a plain `StatelessWidget`
/// would have) so it can track focus for the border highlight and text
/// presence for the clear button — both purely visual, no behavior a
/// caller needs to wire up.
class NmSearchBar extends StatefulWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onFilterTap;
  final bool autofocus;

  const NmSearchBar({
    super.key,
    this.controller,
    this.hint = 'Search profiles...',
    this.onChanged,
    this.onSubmitted,
    this.onFilterTap,
    this.autofocus = false,
  });

  @override
  State<NmSearchBar> createState() => _NmSearchBarState();
}

class _NmSearchBarState extends State<NmSearchBar> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    // Only dispose the controller if this widget created it — a
    // caller-supplied controller stays theirs to manage.
    if (widget.controller == null) _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  void _onFocusChanged() => setState(() => _isFocused = _focusNode.hasFocus);

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;

    return AnimatedContainer(
      duration: AppAnimationTokens.fast,
      curve: Curves.easeOut,
      height: 52,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isFocused ? AppColors.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        textInputAction: TextInputAction.search,
        style: AppTypography.bodyMedium,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: AppTypography.bodyMedium.copyWith(color: iconColor),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: _isFocused ? AppColors.primary : iconColor,
            size: 22,
          ),
          suffixIcon: AnimatedSwitcher(
            duration: AppAnimationTokens.fast,
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: _buildSuffix(iconColor),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget? _buildSuffix(Color iconColor) {
    // Clear button takes priority over the filter action when there's text
    // to clear — both permanently visible would crowd the field, and
    // "clear what I typed" is the more relevant action in that moment.
    if (_hasText) {
      return IconButton(
        key: const ValueKey('clear'),
        onPressed: _clear,
        icon: Icon(Icons.close_rounded, color: iconColor, size: 20),
        tooltip: 'Clear',
        splashRadius: 18,
      );
    }
    if (widget.onFilterTap != null) {
      return IconButton(
        key: const ValueKey('filter'),
        onPressed: widget.onFilterTap,
        icon: Icon(Icons.tune_rounded, color: iconColor, size: 22),
        tooltip: 'Filters',
      );
    }
    return const SizedBox.shrink(key: ValueKey('none'));
  }
}

import 'package:flutter/material.dart';

/// Icon + title (+ optional subtitle) + trailing `Switch` row — extracted
/// from the pattern `settings_page.dart` hand-rolled for its Push
/// Notifications row, so the near-identical settings toggles elsewhere
/// (Privacy's visibility switches) reuse it instead of duplicating the
/// `ListTile`+`Switch` composition again.
class NmToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const NmToggleRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

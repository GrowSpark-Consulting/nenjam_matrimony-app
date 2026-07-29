import 'package:flutter/material.dart';

/// Icon + title (+ optional subtitle) + trailing `Switch` row — extracted
/// from the pattern `settings_page.dart` hand-rolled twice already
/// (notifications, dark mode), so a third near-identical settings toggle
/// (Privacy's visibility switches) reuses it instead of duplicating the
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

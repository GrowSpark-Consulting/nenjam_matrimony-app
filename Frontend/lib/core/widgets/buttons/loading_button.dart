import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'primary_button.dart';

/// Convenience wrapper around NmPrimaryButton specifically in loading state.
class NmLoadingButton extends StatelessWidget {
  final double? width;
  final double height;

  const NmLoadingButton({super.key, this.width, this.height = 56});

  @override
  Widget build(BuildContext context) {
    return NmPrimaryButton(
      label: AppLocalizations.of(context).commonLoading,
      isLoading: true,
      width: width,
      height: height,
    );
  }
}

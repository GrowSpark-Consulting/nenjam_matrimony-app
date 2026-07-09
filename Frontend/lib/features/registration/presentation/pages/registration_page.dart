import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';

/// User Registration Page foundation.
class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedGender = 'Male';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onRegister() {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _isLoading = true);
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          setState(() => _isLoading = false);
          context.go(RouteNames.discover);
        }
      });
    }
  }

  String _relationLabel(AppLocalizations l10n, String v) => switch (v) {
        'Self' => l10n.relationSelf,
        'Son' => l10n.authRegForSon,
        'Daughter' => l10n.authRegForDaughter,
        'Brother' => l10n.authRegForBrother,
        'Sister' => l10n.authRegForSister,
        _ => v,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.authCreateAccount)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.registrationProfileCreatedForLabel,
                  style: AppTypography.labelLarge,
                ),
                const SizedBox(height: 12),
                Row(
                  children: ['Self', 'Son', 'Daughter', 'Brother', 'Sister']
                      .map((relation) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_relationLabel(l10n, relation)),
                              selected: relation == 'Self',
                              onSelected: (_) {},
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 24),
                NmTextField(
                  label: l10n.registrationFullNameLabel,
                  hint: l10n.registrationFullNameHint,
                  controller: _nameController,
                  validator: Validators.name,
                ),
                const SizedBox(height: 16),
                NmTextField(
                  label: l10n.authEmailAddress,
                  hint: 'name@example.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                ),
                const SizedBox(height: 16),
                NmTextField(
                  label: l10n.authMobileNumber,
                  hint: '98765 43210',
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  validator: Validators.phone,
                ),
                const SizedBox(height: 24),
                Text(l10n.registrationGenderLabel, style: AppTypography.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: ['Male', 'Female'].map((gender) {
                    final isSelected = _selectedGender == gender;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Center(child: Text(gender == 'Male' ? l10n.genderMale : l10n.genderFemale)),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _selectedGender = gender),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
                NmPrimaryButton(
                  label: l10n.registrationRegisterContinue,
                  onPressed: _onRegister,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

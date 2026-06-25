import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/profile_draft.dart';

/// Step 6 — Physical Details
class StepPhysical extends StatefulWidget {
  final PhysicalDetails details;
  final void Function(PhysicalDetails) onChanged;

  const StepPhysical({super.key, required this.details, required this.onChanged});

  @override
  State<StepPhysical> createState() => _StepPhysicalState();
}

class _StepPhysicalState extends State<StepPhysical> {
  late String _height;
  late String _weight;
  late String _bodyType;
  late String _complexion;
  late String _bloodGroup;
  late String _disability;

  static const _heights = ['4\'6"', '4\'8"', '4\'10"', '5\'0"', '5\'2"', '5\'4"', '5\'5"', '5\'6"', '5\'7"', '5\'8"', '5\'9"', '5\'10"', '5\'11"', '6\'0"', '6\'1"', '6\'2"', '6\'4"'];
  static const _weights = ['40-50 kg', '50-60 kg', '60-70 kg', '70-80 kg', '80-90 kg', '90-100 kg', '100+ kg'];
  static const _bodyTypes = ['Slim', 'Average', 'Athletic', 'Heavy'];
  static const _complexions = ['Very Fair', 'Fair', 'Wheatish', 'Dark'];
  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Not Known'];
  static const _disabilities = ['None', 'Physical', 'Hearing', 'Visual', 'Speech', 'Other'];

  @override
  void initState() {
    super.initState();
    _height = widget.details.height;
    _weight = widget.details.weight;
    _bodyType = widget.details.bodyType;
    _complexion = widget.details.complexion;
    _bloodGroup = widget.details.bloodGroup;
    _disability = widget.details.disability.isEmpty ? 'None' : widget.details.disability;
  }

  void _emit() {
    widget.onChanged(PhysicalDetails(height: _height, weight: _weight, bodyType: _bodyType, complexion: _complexion, bloodGroup: _bloodGroup, disability: _disability));
  }

  Widget _buildChipSection(String title, List<String> options, String selected, void Function(String) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: options.map((o) { final sel = selected == o; return ChoiceChip(label: Text(o), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { onSelect(o); _emit(); }); }).toList()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Physical Details', style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Describe your appearance', style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 24),
          _buildChipSection('Height', _heights, _height, (v) => setState(() => _height = v)),
          const SizedBox(height: 20),
          _buildChipSection('Weight', _weights, _weight, (v) => setState(() => _weight = v)),
          const SizedBox(height: 20),
          _buildChipSection('Body Type', _bodyTypes, _bodyType, (v) => setState(() => _bodyType = v)),
          const SizedBox(height: 20),
          _buildChipSection('Complexion', _complexions, _complexion, (v) => setState(() => _complexion = v)),
          const SizedBox(height: 20),
          _buildChipSection('Blood Group', _bloodGroups, _bloodGroup, (v) => setState(() => _bloodGroup = v)),
          const SizedBox(height: 20),
          _buildChipSection('Disability', _disabilities, _disability, (v) => setState(() => _disability = v)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_dropdown.dart';

/// Reusable Religion Selector.
class NmReligionSelector extends StatelessWidget {
  final String? value;
  final void Function(String?)? onChanged;

  const NmReligionSelector({super.key, this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    const religions = ['Hindu', 'Christian', 'Muslim', 'Jain', 'Sikh', 'Buddhist', 'Inter-Religion'];
    return NmDropdown<String>(
      label: 'Religion',
      hint: 'Select Religion',
      value: value,
      items: religions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}

/// Reusable Caste Selector.
class NmCasteSelector extends StatelessWidget {
  final String? value;
  final void Function(String?)? onChanged;

  const NmCasteSelector({super.key, this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    const castes = ['Iyer', 'Iyengar', 'Mudaliar', 'Pillai', 'Chettiar', 'Gounder', 'Nadar', 'Vanniyar', 'Don\'t Wish to Specify'];
    return NmDropdown<String>(
      label: 'Caste / Division',
      hint: 'Select Caste',
      value: value,
      items: castes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}

/// Reusable Mother Tongue Selector.
class NmMotherTongueSelector extends StatelessWidget {
  final String? value;
  final void Function(String?)? onChanged;

  const NmMotherTongueSelector({super.key, this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    const tongues = ['Tamil', 'Telugu', 'Malayalam', 'Kannada', 'Hindi', 'English'];
    return NmDropdown<String>(
      label: 'Mother Tongue',
      hint: 'Select Tongue',
      value: value,
      items: tongues.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}

/// Reusable Profession Selector.
class NmProfessionSelector extends StatelessWidget {
  final String? value;
  final void Function(String?)? onChanged;

  const NmProfessionSelector({super.key, this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    const professions = ['Software Engineer', 'Doctor', 'IAS / IPS / Govt', 'Business / Entrepreneur', 'Finance / Banking', 'Architect / Design', 'Civil / Mechanical Engg'];
    return NmDropdown<String>(
      label: 'Profession',
      hint: 'Select Profession',
      value: value,
      items: professions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}

/// Reusable Income Selector.
class NmIncomeSelector extends StatelessWidget {
  final String? value;
  final void Function(String?)? onChanged;

  const NmIncomeSelector({super.key, this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    const incomes = ['5 - 10 Lakhs PA', '10 - 20 Lakhs PA', '20 - 50 Lakhs PA', '50 Lakhs - 1 Crore PA', '1 Crore+ PA', 'Prefer not to say'];
    return NmDropdown<String>(
      label: 'Annual Income',
      hint: 'Select Range',
      value: value,
      items: incomes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}

/// Reusable Height Selector.
class NmHeightSelector extends StatelessWidget {
  final String? value;
  final void Function(String?)? onChanged;

  const NmHeightSelector({super.key, this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    const heights = ['5 ft 0 in (152 cm)', '5 ft 2 in (157 cm)', '5 ft 4 in (162 cm)', '5 ft 6 in (167 cm)', '5 ft 8 in (172 cm)', '5 ft 10 in (177 cm)', '6 ft 0 in (183 cm)', '6 ft 2 in+'];
    return NmDropdown<String>(
      label: 'Height',
      hint: 'Select Height',
      value: value,
      items: heights.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}

/// Reusable Weight Selector.
class NmWeightSelector extends StatelessWidget {
  final String? value;
  final void Function(String?)? onChanged;

  const NmWeightSelector({super.key, this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    const weights = ['45 kg', '50 kg', '55 kg', '60 kg', '65 kg', '70 kg', '75 kg', '80 kg', '85 kg+'];
    return NmDropdown<String>(
      label: 'Weight',
      hint: 'Select Weight',
      value: value,
      items: weights.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}

/// Reusable Education Selector.
class NmEducationSelector extends StatelessWidget {
  final String? value;
  final void Function(String?)? onChanged;

  const NmEducationSelector({super.key, this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    const edu = ['B.E / B.Tech / M.Tech', 'MBBS / MD / MS', 'MBA / PGDM', 'CA / CFA', 'B.Sc / M.Sc', 'Ph.D', 'Other Bachelors / Masters'];
    return NmDropdown<String>(
      label: 'Highest Qualification',
      hint: 'Select Degree',
      value: value,
      items: edu.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}

/// Reusable Location Selector.
class NmLocationSelector extends StatelessWidget {
  final String? value;
  final void Function(String?)? onChanged;

  const NmLocationSelector({super.key, this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    const cities = ['Chennai', 'Coimbatore', 'Madurai', 'Trichy', 'Bangalore', 'Hyderabad', 'Mumbai', 'Singapore', 'USA / UK / Abroad'];
    return NmDropdown<String>(
      label: 'Current Location',
      hint: 'Select City / Country',
      value: value,
      items: cities.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}

/// Reusable Country Picker.
class NmCountryPicker extends StatelessWidget {
  final String? value;
  final void Function(String?)? onChanged;

  const NmCountryPicker({super.key, this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    const countries = ['India (+91)', 'United States (+1)', 'United Kingdom (+44)', 'Singapore (+65)', 'UAE (+971)', 'Malaysia (+60)', 'Australia (+61)', 'Canada (+1)'];
    return NmDropdown<String>(
      label: 'Country',
      hint: 'Select Country',
      value: value,
      items: countries.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}

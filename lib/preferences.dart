// User preferences: how much each factor counts toward "Best overall choice".
import 'package:flutter/material.dart';

/// Factor labels, matching the labels used by `_factors` in compare_screen.dart.
const factorLabels = [
  'Low sugar',
  'Low fat',
  'Low cholesterol',
  'High protein',
  'Few risky ingredients',
];

/// Slider steps: 0 = ignore ... 2 = normal (default) ... 4 = most important.
const _stepNames = ['Ignore', 'Low', 'Normal', 'High', 'Highest'];

class Preferences {
  /// Slider level per factor label, 0..4. Missing = 2 (normal).
  final Map<String, double> levels;
  const Preferences([this.levels = const {}]);

  double level(String label) => levels[label] ?? 2;

  /// Multiplier used in the weighted average: 0, 0.5, 1, 1.5, 2.
  /// A weight of 0 removes the factor from the score.
  double weight(String label) => level(label) / 2;

  Preferences with_(String label, double value) =>
      Preferences({...levels, label: value});

  bool get isDefault => factorLabels.every((l) => level(l) == 2);
  bool get allIgnored => factorLabels.every((l) => weight(l) == 0);
}

/// Collapsible card with one slider per factor.
class PreferencesCard extends StatelessWidget {
  final Preferences prefs;
  final ValueChanged<Preferences> onChanged;
  const PreferencesCard({super.key, required this.prefs, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.tune, color: cs.primary),
          title: const Text('Preferences', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            prefs.isDefault
                ? 'All factors count equally'
                : 'Custom weights for the best overall pick',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose how much each factor matters. "Ignore" removes it from the score.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (final label in factorLabels) _slider(context, label),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: prefs.isDefault ? null : () => onChanged(const Preferences()),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(BuildContext context, String label) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final v = prefs.level(label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(_stepNames[v.round()],
                  style: tt.bodySmall?.copyWith(
                      color: v == 0 ? cs.onSurfaceVariant : cs.primary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Slider(
          value: v,
          min: 0,
          max: 4,
          divisions: 4,
          label: _stepNames[v.round()],
          onChanged: (x) => onChanged(prefs.with_(label, x)),
        ),
      ],
    );
  }
}
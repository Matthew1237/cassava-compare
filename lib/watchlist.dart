// Personal watch-list: allergens, diet and nutrients the user cares about.
// Saved on the device. Matching products are flagged in the basket and on the
// compare screen. Missing data is reported as unknown, never as safe.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Allergens as Open Food Facts tags them, with a label for people.
const allergenOptions = [
  ('en:gluten', 'Gluten'),
  ('en:milk', 'Milk'),
  ('en:eggs', 'Eggs'),
  ('en:peanuts', 'Peanuts'),
  ('en:nuts', 'Tree nuts'),
  ('en:soybeans', 'Soy'),
  ('en:fish', 'Fish'),
  ('en:crustaceans', 'Shellfish'),
  ('en:sesame-seeds', 'Sesame'),
  ('en:mustard', 'Mustard'),
  ('en:celery', 'Celery'),
  ('en:sulphur-dioxide-and-sulphites', 'Sulphites'),
];

enum Diet { none, vegetarian, vegan }

class WatchList {
  final Set<String> allergens;
  final Diet diet;

  /// Nutrients to show first, in the order the user picked them.
  final List<Metric> nutrients;

  const WatchList({this.allergens = const {}, this.diet = Diet.none, this.nutrients = const []});

  bool get isEmpty => allergens.isEmpty && diet == Diet.none && nutrients.isEmpty;

  WatchList copyWith({Set<String>? allergens, Diet? diet, List<Metric>? nutrients}) => WatchList(
        allergens: allergens ?? this.allergens,
        diet: diet ?? this.diet,
        nutrients: nutrients ?? this.nutrients,
      );

  Map<String, dynamic> toJson() => {
        'allergens': allergens.toList(),
        'diet': diet.name,
        'nutrients': [for (final m in nutrients) m.name],
      };

  /// Tolerates missing or unknown values, so an old save never crashes the app.
  factory WatchList.fromJson(Map<String, dynamic> j) => WatchList(
        allergens: {...(j['allergens'] as List? ?? const []).whereType<String>()},
        diet: Diet.values.asNameMap()[j['diet']] ?? Diet.none,
        nutrients: [
          for (final n in (j['nutrients'] as List? ?? const []).whereType<String>())
            ?Metric.values.asNameMap()[n]
        ],
      );

  static const _key = 'watchlist.v1';

  static Future<WatchList> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      return raw == null ? const WatchList() : WatchList.fromJson(jsonDecode(raw));
    } catch (_) {
      return const WatchList();
    }
  }

  Future<void> save() async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(toJson()));
}

enum FlagLevel { contains, mayContain, unknown }

class WatchFlag {
  final String text;
  final FlagLevel level;
  const WatchFlag(this.text, this.level);
}

/// What in [p] matches the watch-list [w].
List<WatchFlag> watchFlags(Product p, WatchList w) {
  final out = <WatchFlag>[];
  for (final (tag, label) in allergenOptions) {
    if (!w.allergens.contains(tag)) continue;
    if (p.allergens.contains(tag)) {
      out.add(WatchFlag('Contains ${label.toLowerCase()}', FlagLevel.contains));
    } else if (p.traces.contains(tag)) {
      out.add(WatchFlag('May contain ${label.toLowerCase()}', FlagLevel.mayContain));
    }
  }
  // No allergens listed AND no ingredients means the data is missing, not clean.
  final noIngredientData = p.ingredients == null && p.ingredientItems.isEmpty;
  if (w.allergens.isNotEmpty && p.allergens.isEmpty && noIngredientData) {
    out.add(const WatchFlag('No allergen data', FlagLevel.unknown));
  }
  switch (w.diet) {
    case Diet.vegan:
      if (p.analysis.contains('en:non-vegan')) {
        out.add(const WatchFlag('Not vegan', FlagLevel.contains));
      } else if (!p.analysis.contains('en:vegan')) {
        out.add(const WatchFlag('Vegan status unknown', FlagLevel.unknown));
      }
    case Diet.vegetarian:
      if (p.analysis.contains('en:non-vegetarian')) {
        out.add(const WatchFlag('Not vegetarian', FlagLevel.contains));
      } else if (!p.analysis.contains('en:vegetarian') && !p.analysis.contains('en:vegan')) {
        out.add(const WatchFlag('Vegetarian status unknown', FlagLevel.unknown));
      }
    case Diet.none:
      break;
  }
  return out;
}

/// Small coloured chips for a product's watch-list flags.
class WatchFlagChips extends StatelessWidget {
  final List<WatchFlag> flags;
  const WatchFlagChips(this.flags, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final f in flags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: switch (f.level) {
                FlagLevel.contains => cs.errorContainer,
                FlagLevel.mayContain => const Color(0xFFFFF0C2),
                FlagLevel.unknown => cs.surfaceContainerHighest,
              },
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  switch (f.level) {
                    FlagLevel.contains => Icons.error_outline,
                    FlagLevel.mayContain => Icons.warning_amber_rounded,
                    FlagLevel.unknown => Icons.help_outline,
                  },
                  size: 14,
                  color: f.level == FlagLevel.contains ? cs.onErrorContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(f.text,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: f.level == FlagLevel.contains
                            ? cs.onErrorContainer
                            : cs.onSurface)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Lets the user edit their watch-list. Saves on every change and returns the
/// final list when closed.
class WatchListScreen extends StatefulWidget {
  final WatchList initial;
  const WatchListScreen({super.key, required this.initial});

  @override
  State<WatchListScreen> createState() => _WatchListScreenState();
}

class _WatchListScreenState extends State<WatchListScreen> {
  late WatchList _w = widget.initial;

  void _update(WatchList w) {
    setState(() => _w = w);
    w.save();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    Widget title(String t, String hint) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t, style: tt.titleMedium),
              const SizedBox(height: 2),
              Text(hint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_w);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('My watch-list')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            title('Allergens', 'Products that contain these, or may contain traces, are flagged.'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (tag, label) in allergenOptions)
                  FilterChip(
                    label: Text(label),
                    selected: _w.allergens.contains(tag),
                    onSelected: (on) => _update(_w.copyWith(
                        allergens: on ? {..._w.allergens, tag} : ({..._w.allergens}..remove(tag)))),
                  ),
              ],
            ),
            title('Diet', 'Based on the ingredient analysis in Open Food Facts.'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<Diet>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: Diet.none, label: Text('Any')),
                  ButtonSegment(value: Diet.vegetarian, label: Text('Vegetarian')),
                  ButtonSegment(value: Diet.vegan, label: Text('Vegan')),
                ],
                selected: {_w.diet},
                onSelectionChanged: (s) => _update(_w.copyWith(diet: s.first)),
              ),
            ),
            title('Nutrients I watch', 'Shown first when you compare products.'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final m in Metric.values)
                  FilterChip(
                    showCheckmark: false,
                    avatar: Icon(m.icon, size: 16),
                    label: Text(m.label),
                    selected: _w.nutrients.contains(m),
                    onSelected: (on) => _update(_w.copyWith(
                        nutrients: on ? [..._w.nutrients, m] : ([..._w.nutrients]..remove(m)))),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 20, color: cs.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Open Food Facts is crowd-sourced and can be incomplete. '
                      'If you have an allergy, always check the pack.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Compare screen: nutrition and ingredients tabs, and their widgets.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';
import 'saved.dart';
import 'watchlist.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Compare screen
// ─────────────────────────────────────────────────────────────────────────────

class CompareScreen extends StatefulWidget {
  final List<Product> products;
  final WatchList watch;
  const CompareScreen({
    super.key,
    required this.products,
    this.watch = const WatchList(),
  });

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  final Set<String> _hidden = {};
  bool _perServing = false;

  /// The nutrient shown in the "By nutrient" graph: the first one the user watches.
  late Metric _metric = _metricsInOrder.first;
  static const _tabMetrics = [
    Metric.calories,
    Metric.fat,
    Metric.cholesterol,
    Metric.sodium,
    Metric.carbs,
    Metric.sugar,
    Metric.protein,
  ];

  /// Watched nutrients first, then the usual tabs.
  List<Metric> get _metricsInOrder => [
        ...widget.watch.nutrients,
        ..._tabMetrics.where((m) => !widget.watch.nutrients.contains(m)),
      ];

  List<Product> get _visible =>
      widget.products.where((p) => !_hidden.contains(p.id)).toList();

  Future<void> _share() => SharePlus.instance.share(ShareParams(
        text: comparisonSummary(_visible, perServing: _perServing),
        subject: 'Cassava comparison',
      ));

  Future<void> _save() async {
    final names = widget.products.map((p) => p.name.split(' ').take(2).join(' '));
    final controller = TextEditingController(text: names.take(2).join(' vs '));
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save comparison'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await SavedStore.add(
        SavedComparison(name, [for (final p in widget.products) p.barcode], DateTime.now()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved "$name"')));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // Nutrition + Ingredients
      child: Scaffold(
        appBar: AppBar(
          title: Text('Comparing ${widget.products.length} products'),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined),
              tooltip: 'Save comparison',
              onPressed: _save,
            ),
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Share comparison',
              onPressed: _share,
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Nutrition'),
            Tab(text: 'Ingredients'),
          ]),
        ),
        body: TabBarView(children: [
          _buildNutritionTab(context),
          _buildIngredientsTab(context),
        ]),
      ),
    );
  }

  /// Chips to hide or show products; shared by the nutrition and ingredients tabs.
  Widget _productFilter(List<Product> visible) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final p in widget.products)
          FilterChip(
            showCheckmark: false,
            avatar: CircleAvatar(backgroundColor: p.color, radius: 6),
            label: Text(p.name, overflow: TextOverflow.ellipsis),
            selected: !_hidden.contains(p.id),
            selectedColor: p.color.withValues(alpha: 0.22),
            onSelected: (sel) => setState(() {
              if (sel) {
                _hidden.remove(p.id);
              } else if (visible.length > 1) {
                _hidden.add(p.id);
              }
            }),
          ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _buildNutritionTab(BuildContext context) {
    final visible = _visible;
    final missingServing = visible.any((p) => p.nutrition.servingGrams == null);
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _productFilter(visible),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Per 100 g')),
              ButtonSegment(value: true, label: Text('Per serving')),
            ],
            selected: {_perServing},
            onSelectionChanged: (s) => setState(() => _perServing = s.first),
          ),
        ),
        if (_perServing && missingServing)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Some products have no serving size in the database; they show "–" per serving.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (!widget.watch.isEmpty) ...[
          const SizedBox(height: 20),
          _WatchCard(products: visible, watch: widget.watch),
        ],
        const SizedBox(height: 20),
        _BestOverallCard(
            products: visible, perServing: _perServing, watch: widget.watch),
        _sectionTitle(context, 'By Nutrient'),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final m in _metricsInOrder)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    avatar: Icon(m.icon, size: 16),
                    label: Text(m.label),
                    selected: _metric == m,
                    onSelected: (_) => setState(() => _metric = m),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
          child: Text('Tap a product to compare it with a daily reference.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ),
        _MetricCard(
          key: ValueKey(_metric), // restarts the bar animation on each tab
          metric: _metric,
          products: visible,
          perServing: _perServing,
        ),
        _sectionTitle(context, 'Side by side'),
        _SideBySideTable(products: visible, perServing: _perServing),
        const SizedBox(height: 14),
        const _NeutralityNote(),
      ],
    );
  }

  Widget _buildIngredientsTab(BuildContext context) {
    final visible = _visible;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _productFilter(visible),
        const SizedBox(height: 16),
        _IngredientsCard(products: visible),
        const SizedBox(height: 14),
        const _NeutralityNote(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nutrition widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Numbers that line up in columns when products are compared.
const _tabular = [FontFeature.tabularFigures()];

double _maxOf(Iterable<double?> vs) => vs.whereType<double>().fold<double>(0, math.max);

// ─────────────────────────────────────────────────────────────────────────────
// Best overall choice
// ─────────────────────────────────────────────────────────────────────────────

class _Factor {
  final String label;
  final bool higherIsBetter;
  final double? Function(Product p, bool perServing) value;

  /// Nutrient scored against its daily reference amount. Null = no daily
  /// value exists (ingredient risk), so the factor is scaled against the
  /// highest value in the group instead.
  final Metric? metric;
  const _Factor(this.label, this.higherIsBetter, this.value, {this.metric});
}

/// Weighted count of classified ingredients: high risk = 3, limited risk = 2,
/// very low risk = 1. Unclassified ingredients count 0.
/// Null when the product has no ingredient data.
double? _riskLoad(Product p) => p.ingredientItems.isEmpty
    ? null
    : (p.countRisk(RiskLevel.high) * 3 +
            p.countRisk(RiskLevel.limited) * 2 +
            p.countRisk(RiskLevel.veryLow))
        .toDouble();

/// The base factors, all counted equally unless the nutrient is watched.
final _factors = <_Factor>[
  _Factor('Low sugar', false, (p, s) => p.nutrition.value(Metric.sugar, perServing: s),
      metric: Metric.sugar),
  _Factor('Low fat', false, (p, s) => p.nutrition.value(Metric.fat, perServing: s),
      metric: Metric.fat),
  _Factor('Low cholesterol', false,
      (p, s) => p.nutrition.value(Metric.cholesterol, perServing: s),
      metric: Metric.cholesterol),
  _Factor('High protein', true, (p, s) => p.nutrition.value(Metric.protein, perServing: s),
      metric: Metric.protein),
  _Factor('Few risky ingredients', false, (p, s) => _riskLoad(p)),
];

/// The factor label used for each nutrient someone can watch.
const _watchFactorLabels = {
  Metric.sugar: 'Low sugar',
  Metric.fat: 'Low fat',
  Metric.cholesterol: 'Low cholesterol',
  Metric.protein: 'High protein',
  Metric.sodium: 'Low sodium',
  Metric.calories: 'Low calories',
  Metric.carbs: 'Low carbohydrates',
};

/// The base factors plus one for each watched nutrient that isn't scored yet,
/// so watching sodium makes sodium count.
List<_Factor> _factorsFor(WatchList w) => [
      ..._factors,
      for (final m in w.nutrients)
        if (!_factors.any((f) => f.label == _watchFactorLabels[m]))
          _Factor(_watchFactorLabels[m]!, m == Metric.protein,
              (p, s) => p.nutrition.value(m, perServing: s),
              metric: m),
    ];

bool _isWatched(String label, WatchList w) =>
    w.nutrients.any((m) => _watchFactorLabels[m] == label);

/// Every factor counts 1, and 2 when its nutrient is on the watch-list.
double _weight(String label, WatchList w) => _isWatched(label, w) ? 2 : 1;

/// Score multiplier when a product may contain traces of a watched allergen.
const _mayContainPenalty = 0.9;

class OverallScore {
  final Product product;
  final double? score; // 0..1, null when no factor had data
  final Map<String, double?> parts; // per factor, 0..1, null = skipped
  final int used; // factors that counted toward the score

  /// Watch-list "contains" matches (allergen or diet): ranked last, never best.
  final List<WatchFlag> conflicts;

  /// Watch-list "may contain" matches: the score is lowered a little.
  final List<WatchFlag> traces;
  OverallScore(this.product, this.score, this.parts, this.used,
      {this.conflicts = const [], this.traces = const []});
}

/// Every factor becomes a part from 0 to 1 (1 = best).
///
/// Nutrient factors are measured against the daily reference amount of the
/// nutrient ([Metric.dailyReference]): the fraction of the daily value in the
/// amount (capped at 100%), flipped for "low" factors (1 - fraction). So a
/// product's nutrient parts don't depend on what it is compared with.
/// Ingredient risk has no daily value, so it is still scaled against the
/// highest value in the group (1 = best in the group), and skipped when fewer
/// than two products have data or when the highest value is 0.
///
/// The overall score is the weighted average of the parts. A product with
/// missing data is averaged over the factors it does have.
///
/// The watch-list sets the weights and adjusts the ranking: watched nutrients
/// count double (and become factors if they weren't), "may contain" traces
/// lower the score by 10%, and products that contain a watched allergen or
/// break the chosen diet are ranked after all others.
List<OverallScore> computeOverall(
  List<Product> ps, {
  required bool perServing,
  WatchList watch = const WatchList(),
}) {
  final factors = _factorsFor(watch);
  final parts = {for (final p in ps) p.id: <String, double?>{}};
  for (final f in factors) {
    final vals = {for (final p in ps) p.id: f.value(p, perServing)};

    // Nutrients: measured against the daily reference amount, capped at 100%.
    final metric = f.metric;
    if (metric != null) {
      for (final p in ps) {
        final v = vals[p.id];
        if (v == null) {
          parts[p.id]![f.label] = null;
          continue;
        }
        final frac = (v / metric.dailyReference).clamp(0.0, 1.0).toDouble();
        parts[p.id]![f.label] = f.higherIsBetter ? frac : 1 - frac;
      }
      continue;
    }

    // No daily value (ingredient risk): scale against the group.
    final known = vals.values.whereType<double>().length;
    final maxV = _maxOf(vals.values);
    for (final p in ps) {
      final v = vals[p.id];
      parts[p.id]![f.label] = (v == null || known < 2 || maxV == 0)
          ? null
          : (f.higherIsBetter ? v / maxV : 1 - v / maxV);
    }
  }
  final out = <OverallScore>[];
  for (final p in ps) {
    final m = parts[p.id]!;
    var sum = 0.0, weightSum = 0.0;
    var used = 0;
    for (final f in factors) {
      final v = m[f.label];
      if (v == null) continue;
      final w = _weight(f.label, watch);
      sum += v * w;
      weightSum += w;
      used++;
    }
    final flags = watchFlags(p, watch);
    final conflicts = [for (final f in flags) if (f.level == FlagLevel.contains) f];
    final traces = [for (final f in flags) if (f.level == FlagLevel.mayContain) f];
    var score = weightSum == 0 ? null : sum / weightSum;
    if (score != null && traces.isNotEmpty) score *= _mayContainPenalty;
    out.add(OverallScore(p, score, m, used, conflicts: conflicts, traces: traces));
  }
  // Conflicts go last; within each group, highest score first.
  out.sort((a, b) {
    final c = (a.conflicts.isEmpty ? 0 : 1).compareTo(b.conflicts.isEmpty ? 0 : 1);
    return c != 0 ? c : (b.score ?? -1).compareTo(a.score ?? -1);
  });
  return out;
}

class _BestOverallCard extends StatelessWidget {
  final List<Product> products;
  final bool perServing;
  final WatchList watch;
  const _BestOverallCard({
    required this.products,
    required this.perServing,
    required this.watch,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scores = products.length < 2
        ? <OverallScore>[]
        : computeOverall(products, perServing: perServing, watch: watch);
    final allConflict = scores.isNotEmpty && scores.every((s) => s.conflicts.isNotEmpty);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.emoji_events_outlined, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Best overall choice',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ]),
            const SizedBox(height: 2),
            Text(
              'Low sugar, low fat, low cholesterol, high protein and few '
              'risk-classified ingredients (high counts most). Nutrients are '
              'measured against general daily reference amounts; ingredient '
              'risk is compared within this group.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (!watch.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.health_and_safety_outlined, size: 14, color: cs.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Adjusted for your watch-list: watched nutrients count double (×2), '
                        'and products with your allergens or outside your diet are ranked last.',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
                      ),
                    ),
                  ],
                ),
              ),
            if (scores.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Select at least two products to compare.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              )
            else ...[
              if (allConflict)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('Every product here conflicts with your watch-list.',
                      style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
                ),
              for (var i = 0; i < scores.length; i++)
                _row(context, scores[i], i == 0 && scores[i].conflicts.isEmpty),
            ],
            const SizedBox(height: 8),
            Text(
              'Nutrient scores use general daily reference amounts (2,000 kcal '
              'diet), not an absolute health rating, and individual needs vary. '
              'All factors count equally, except nutrients on your watch-list, '
              'which count double (×2). Missing data is skipped. Ingredient risk '
              'counts high = 3, limited = 2, very low = 1.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, OverallScore s, bool best) {
    final cs = Theme.of(context).colorScheme;
    final p = s.product;
    final factors = _factorsFor(watch);
    final active = factors.length;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: best ? p.color.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: best ? p.color : cs.outlineVariant, width: best ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(backgroundColor: p.color, radius: 6),
            const SizedBox(width: 8),
            Expanded(
              child: Text(p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (best && s.score != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('Best',
                    style: TextStyle(
                        color: cs.primary, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            Text(s.score == null ? 'n/a' : '${(s.score! * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: _tabular)),
          ]),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: s.score ?? 0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 10,
                color: p.color,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: -4,
            children: [
              for (final f in factors)
                Chip(
                  label: Text(
                    '${f.label} ${_pct(s.parts[f.label])}'
                    '${_isWatched(f.label, watch) ? ' ×2' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: p.color.withValues(alpha: 0.12),
                  side: BorderSide.none,
                ),
            ],
          ),
          if (s.conflicts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Not for you: ${s.conflicts.map((f) => f.text).join(', ')}',
                  style: TextStyle(color: cs.error, fontWeight: FontWeight.w600, fontSize: 13)),
            )
          else if (s.traces.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  '${s.traces.map((f) => f.text).join(', ')}: score lowered 10%',
                  style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          if (s.used < active)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                s.score == null
                    ? 'Not enough data in the database to score this product.'
                    : 'Based on ${s.used} of $active factors (others had no data).',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  String _pct(double? v) => v == null ? '–' : '${(v * 100).round()}%';
}

// ─────────────────────────────────────────────────────────────────────────────
// Metric graph (one nutrient at a time)
// ─────────────────────────────────────────────────────────────────────────────

class _MetricCard extends StatefulWidget {
  final Metric metric;
  final List<Product> products;
  final bool perServing;
  const _MetricCard(
      {super.key,
      required this.metric,
      required this.products,
      required this.perServing});

  @override
  State<_MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<_MetricCard> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final m = widget.metric;
    final cs = Theme.of(context).colorScheme;
    final values = {
      for (final p in widget.products)
        p.id: p.nutrition.value(m, perServing: widget.perServing)
    };
    final maxV = _maxOf(values.values);
    final denom = maxV == 0 ? 1.0 : maxV;
    final selected = widget.products.where((p) => p.id == _selected).toList();
    final selValue = selected.isEmpty ? null : values[selected.first.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(m.icon, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(m.label,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(widget.perServing ? 'per serving' : 'per 100 g',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 10),
            for (final p in widget.products)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selected = _selected == p.id ? null : p.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(backgroundColor: p.color, radius: 5),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                      _selected == p.id ? FontWeight.w700 : FontWeight.w500,
                                )),
                          ),
                          const SizedBox(width: 8),
                          Text(
                              values[p.id] == null ? 'n/a' : '${fmt(values[p.id])} ${m.unit}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: values[p.id] == null ? cs.onSurfaceVariant : null,
                                  fontFeatures: _tabular)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: (values[p.id] ?? 0) / denom),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (_, f, _) => Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            if (values[p.id] != null)
                              FractionallySizedBox(
                                widthFactor: f.clamp(0.02, 1.0),
                                child: Container(
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: p.color,
                                    borderRadius: BorderRadius.circular(5),
                                    border: _selected == p.id
                                        ? Border.all(color: cs.onSurface, width: 1.5)
                                        : null,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: selected.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: selected.first.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        selValue == null
                            ? '${selected.first.name}: no ${m.label.toLowerCase()} data in the database.'
                            : '${selected.first.name}: ${fmt(selValue)} ${m.unit} '
                                '≈ ${(selValue / m.dailyReference * 100).round()}% of the '
                                '${fmt(m.dailyReference)} ${m.unit} general daily reference. '
                                'Individual needs vary.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideBySideTable extends StatelessWidget {
  final List<Product> products;
  final bool perServing;
  const _SideBySideTable({required this.products, required this.perServing});

  static const _labelWidth = 112.0;

  TableRow _row(String label, List<String> cells) => TableRow(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ),
        for (final c in cells)
          Text(c, textAlign: TextAlign.center, style: const TextStyle(fontFeatures: _tabular)),
      ]);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (context, box) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                // Fill the card when the columns fit; scroll sideways when they don't.
                defaultColumnWidth: FixedColumnWidth(math.max(
                    80, (box.maxWidth - _labelWidth) / math.max(1, products.length))),
                columnWidths: const {0: FixedColumnWidth(_labelWidth)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder(
                  horizontalInside:
                      BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                children: [
                  TableRow(children: [
                    const SizedBox(),
                    for (final p in products)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                        child: Column(
                          children: [
                            CircleAvatar(backgroundColor: p.color, radius: 5),
                            const SizedBox(height: 4),
                            Text(p.name,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelSmall),
                          ],
                        ),
                      ),
                  ]),
                  for (final m in Metric.values)
                    TableRow(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text('${m.label} (${m.unit})',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      ),
                      for (final p in products)
                        Text(fmt(p.nutrition.value(m, perServing: perServing)),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontFeatures: _tabular)),
                    ]),
                  TableRow(children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('Serving size',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                    for (final p in products)
                      Text(
                          p.nutrition.servingGrams == null
                              ? '–'
                              : '${fmt(p.nutrition.servingGrams)} g',
                          textAlign: TextAlign.center),
                  ]),
                  if (products.any((p) => p.price != null)) ...[
                    _row('Price', [
                      for (final p in products) p.price?.toStringAsFixed(2) ?? '–',
                    ]),
                    _row('Price / 100 g', [
                      for (final p in products) p.pricePer100g?.toStringAsFixed(2) ?? '–',
                    ]),
                  ],
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _IngredientsCard extends StatelessWidget {
  final List<Product> products;
  const _IngredientsCard({required this.products});

  static const _order = [
    RiskLevel.high,
    RiskLevel.limited,
    RiskLevel.veryLow,
    RiskLevel.unclassified,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tap a product to see which ingredients fall in each group.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            for (final p in products) _productTile(context, p),
            const SizedBox(height: 6),
            Text(
              'Groups come from Open Food Facts\' additive data: the risk of '
              'exceeding acceptable intake, not proof of harm. Ordinary '
              'ingredients (flour, sugar, milk...) have no class and are shown '
              'as "Not classified". Ingredient lists may be incomplete.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productTile(BuildContext context, Product p) {
    final hasItems = p.ingredientItems.isNotEmpty;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: CircleAvatar(backgroundColor: p.color, radius: 6),
        title: Text(p.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: !hasItems
            ? Text(p.ingredients ?? 'No ingredient list in the database.',
                maxLines: 2, overflow: TextOverflow.ellipsis)
            : Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final r in _order)
                      if (r != RiskLevel.unclassified || p.countRisk(r) > 0)
                        _CountPill(level: r, count: p.countRisk(r)),
                  ],
                ),
              ),
        children: [
          if (!hasItems)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(p.ingredients ?? 'No ingredient list in the database.',
                  style: Theme.of(context).textTheme.bodySmall),
            )
          else
            for (final r in _order)
              if (p.countRisk(r) > 0) _group(context, p, r),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, Product p, RiskLevel r) {
    final items = p.ingredientItems.where((i) => i.risk == r).toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: r.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: r.color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${r.label} (${items.length})',
              style: TextStyle(fontWeight: FontWeight.w700, color: r.color)),
          const SizedBox(height: 4),
          Wrap(
            runSpacing: 2,
            children: [
              for (final (n, i) in items.indexed)
                _ingredientText(context, i, last: n == items.length - 1),
            ],
          ),
        ],
      ),
    );
  }

  /// Additives (with an E-number) are tappable and open a short explainer.
  Widget _ingredientText(BuildContext context, Ingredient i, {required bool last}) {
    final label = i.code == null || i.name.toUpperCase().contains(i.code!)
        ? i.name
        : '${i.name} (${i.code})';
    final sep = last ? '' : ', ';
    if (i.code == null) return Text('$label$sep', style: const TextStyle(fontSize: 13));
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => showIngredientInfo(context, i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(TextSpan(children: [
          TextSpan(
            text: label,
            style: const TextStyle(
                fontSize: 13,
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted),
          ),
          TextSpan(text: sep, style: const TextStyle(fontSize: 13)),
        ])),
      ),
    );
  }
}

/// What an additive is, what it's used for, and its over-exposure class.
void showIngredientInfo(BuildContext context, Ingredient i) {
  final tt = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  final risk = switch (i.risk) {
    RiskLevel.high => 'Open Food Facts rates the risk of going over the acceptable '
        'daily intake as high.',
    RiskLevel.limited => 'Open Food Facts rates the risk of going over the acceptable '
        'daily intake as moderate.',
    RiskLevel.veryLow => 'Open Food Facts rates the risk of going over the acceptable '
        'daily intake as very low.',
    RiskLevel.unclassified => 'Open Food Facts has no over-exposure risk class for it.',
  };
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i.name, style: tt.titleLarge),
            if (i.code != null)
              Text(i.code!, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            Text(
              i.uses.isEmpty
                  ? 'An additive. Open Food Facts doesn\'t list what it is used for.'
                  : 'Used as: ${i.uses.join(', ')}.',
              style: tt.bodyLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                CircleAvatar(backgroundColor: i.risk.color, radius: 5),
                const SizedBox(width: 8),
                Expanded(child: Text(risk, style: tt.bodyMedium)),
              ],
            ),
            const SizedBox(height: 4),
            Text('This is about intake limits, not proof of harm.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            if (i.code != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('More on Open Food Facts'),
                onPressed: () => launchUrl(
                  Uri.https('world.openfoodfacts.org', '/facets/additives/${i.code!.toLowerCase()}'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Watch-list matches for each product being compared.
class _WatchCard extends StatelessWidget {
  final List<Product> products;
  final WatchList watch;
  const _WatchCard({required this.products, required this.watch});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.health_and_safety_outlined, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Your watch-list', style: tt.titleMedium)),
            ]),
            for (final p in products) ...[
              const SizedBox(height: 12),
              Row(children: [
                CircleAvatar(backgroundColor: p.color, radius: 5),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 6),
              if (watchFlags(p, watch) case final flags when flags.isNotEmpty)
                WatchFlagChips(flags)
              else
                Text('Nothing on your watch-list found',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final RiskLevel level;
  final int count;
  const _CountPill({required this.level, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: level.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: level.color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(backgroundColor: level.color, radius: 4),
          const SizedBox(width: 5),
          Text('$count ${level.label.toLowerCase()}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _NeutralityNote extends StatelessWidget {
  const _NeutralityNote();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.balance, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'The overall score measures nutrients against daily reference '
              'amounts. Factors count equally, except nutrients on your '
              'watch-list, which count double. Which trade-offs matter depends '
              'on your needs, so you decide what fits.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
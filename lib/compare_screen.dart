// Compare screen: nutrition, ingredients and reviews tabs, and their widgets.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Compare screen
// ─────────────────────────────────────────────────────────────────────────────

class CompareScreen extends StatefulWidget {
  final List<Product> products;
  const CompareScreen({super.key, required this.products});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  final Set<String> _hidden = {};
  bool _perServing = false;
  String? _themeFilter;

  /// The nutrient shown in the "By nutrient" graph.
  Metric _metric = Metric.calories;
  static const _tabMetrics = [
    Metric.calories,
    Metric.fat,
    Metric.cholesterol,
    Metric.sodium,
    Metric.carbs,
    Metric.protein,
  ];

  List<Product> get _visible =>
      widget.products.where((p) => !_hidden.contains(p.id)).toList();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Comparing ${widget.products.length} products'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Nutrition'),
            Tab(text: 'Ingredients'),
            Tab(text: 'Reviews'),
          ]),
        ),
        body: TabBarView(children: [
          _buildNutritionTab(context),
          _buildIngredientsTab(context),
          _buildReviewsTab(context),
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
        const SizedBox(height: 20),
        _BestOverallCard(products: visible, perServing: _perServing),
        _sectionTitle(context, 'By nutrient'),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final m in _tabMetrics)
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

  Widget _buildReviewsTab(BuildContext context) {
    final products = widget.products;
    final cs = Theme.of(context).colorScheme;
    final hasReviews = products.any((p) => p.reviews.isNotEmpty);

    if (!hasReviews) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.rate_review_outlined, color: cs.primary, size: 32),
                  const SizedBox(height: 10),
                  Text('No review source connected',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text(
                    'Open Food Facts covers nutrition, not customer reviews. '
                    'To show critical reviews, connect a licensed review source '
                    'through the ReviewProvider in the code.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _NeutralityNote(),
        ],
      );
    }

    final themes = ReviewAnalyzer.allThemes(products);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Recurring complaints across products',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Share of each product\'s critical reviews (3★ or lower) that mention the topic.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _themeMatrix(products, themes.take(8).toList()),
          ),
        ),
        const SizedBox(height: 14),
        Text('Filter reviews by topic', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: _themeFilter == null,
                  onSelected: (_) => setState(() => _themeFilter = null),
                ),
              ),
              for (final t in themes)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t),
                    selected: _themeFilter == t,
                    onSelected: (sel) => setState(() => _themeFilter = sel ? t : null),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final p in products) _ProductReviewCard(product: p, themeFilter: _themeFilter),
        const SizedBox(height: 4),
        const _NeutralityNote(),
      ],
    );
  }

  Widget _themeMatrix(List<Product> ps, List<String> themes) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(86),
        columnWidths: const {0: FixedColumnWidth(136)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(children: [
            const SizedBox(),
            for (final p in ps)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall),
              ),
          ]),
          for (final t in themes)
            TableRow(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                child: Text(t, style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              for (final p in ps)
                Builder(builder: (_) {
                  final s = ReviewAnalyzer.share(p, t);
                  return Container(
                    margin: const EdgeInsets.all(3),
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s == 0
                          ? Colors.black.withValues(alpha: 0.03)
                          : p.color.withValues(alpha: 0.15 + s * 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(s == 0 ? '–' : '${(s * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  );
                }),
            ]),
        ],
      ),
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
  const _Factor(this.label, this.higherIsBetter, this.value);
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

final _factors = <_Factor>[
  _Factor('Low sugar', false, (p, s) => p.nutrition.value(Metric.sugar, perServing: s)),
  _Factor('Low fat', false, (p, s) => p.nutrition.value(Metric.fat, perServing: s)),
  _Factor('Low cholesterol', false,
      (p, s) => p.nutrition.value(Metric.cholesterol, perServing: s)),
  _Factor('High protein', true, (p, s) => p.nutrition.value(Metric.protein, perServing: s)),
  _Factor('Few risky ingredients', false, (p, s) => _riskLoad(p)),
];

class OverallScore {
  final Product product;
  final double? score; // 0..1, null when no factor had data
  final Map<String, double?> parts; // per factor, 0..1, null = skipped
  final int used;
  OverallScore(this.product, this.score, this.parts, this.used);
}

/// Each factor is scaled against the highest value in the group, so every
/// part is 0..1 (1 = best in the group). "Low" factors are flipped
/// (1 - value/max). The overall score is the plain average of the parts.
///
/// A factor is skipped for everyone when fewer than two products have data
/// for it, or when the highest value is 0 (it can't tell products apart).
/// A product with missing data is averaged over the factors it does have.
List<OverallScore> computeOverall(List<Product> ps, {required bool perServing}) {
  final parts = {for (final p in ps) p.id: <String, double?>{}};
  for (final f in _factors) {
    final vals = {for (final p in ps) p.id: f.value(p, perServing)};
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
    final used = m.values.whereType<double>().toList();
    final score = used.isEmpty ? null : used.reduce((a, b) => a + b) / used.length;
    out.add(OverallScore(p, score, m, used.length));
  }
  out.sort((a, b) => (b.score ?? -1).compareTo(a.score ?? -1));
  return out;
}

class _BestOverallCard extends StatelessWidget {
  final List<Product> products;
  final bool perServing;
  const _BestOverallCard({required this.products, required this.perServing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scores = products.length < 2
        ? <OverallScore>[]
        : computeOverall(products, perServing: perServing);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.emoji_events_outlined, color: cs.primary),
              const SizedBox(width: 8),
              Text('Best overall choice',
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 2),
            Text(
              'Low sugar, low fat, low cholesterol, high protein and few '
              'risk-classified ingredients (high counts most), each scaled to '
              'the best and worst in this group.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (scores.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Select at least two products to compare.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              )
            else
              for (var i = 0; i < scores.length; i++) _row(context, scores[i], i == 0),
            const SizedBox(height: 8),
            Text(
              'Scores are relative to the products you are comparing, not an '
              'absolute health rating. All five factors count equally, and '
              'missing data is skipped. Ingredient risk counts high = 3, '
              'limited = 2, very low = 1.',
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
              for (final f in _factors)
                Chip(
                  label: Text(
                    '${f.label} ${_pct(s.parts[f.label])}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: p.color.withValues(alpha: 0.12),
                  side: BorderSide.none,
                ),
            ],
          ),
          if (s.used < _factors.length)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                s.score == null
                    ? 'Not enough data in the database to score this product.'
                    : 'Based on ${s.used} of ${_factors.length} factors (others had no data).',
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
          Text(
            items
                .map((i) => i.code == null || i.name.toUpperCase().contains(i.code!)
                    ? i.name
                    : '${i.name} (${i.code})')
                .join(', '),
            style: const TextStyle(fontSize: 13),
          ),
        ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Review widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ProductReviewCard extends StatelessWidget {
  final Product product;
  final String? themeFilter;
  const _ProductReviewCard({required this.product, required this.themeFilter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stats = ReviewAnalyzer.themes(product);
    final reviews = ReviewAnalyzer.helpful(product, theme: themeFilter);
    final rating = product.avgRating == null
        ? ''
        : ' · ${product.avgRating}★ avg · ${product.ratingCount ?? 0} ratings';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProductThumb(product, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('${product.brand}$rating',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (product.reviews.isEmpty)
              Text('No reviews available for this product.',
                  style: TextStyle(color: cs.onSurfaceVariant))
            else ...[
              Text(ReviewAnalyzer.summary(product)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: -4,
                children: [
                  for (final s in stats)
                    Chip(
                      label: Text('${s.theme} · ${s.count}'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: themeFilter == s.theme
                          ? product.color.withValues(alpha: 0.35)
                          : product.color.withValues(alpha: 0.12),
                      side: BorderSide.none,
                    ),
                ],
              ),
              const Divider(height: 24),
              Text(
                themeFilter == null
                    ? 'Most helpful critical reviews'
                    : 'Most helpful reviews mentioning "$themeFilter"',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              if (reviews.isEmpty)
                Text('No critical reviews mention this topic.',
                    style: TextStyle(color: cs.onSurfaceVariant))
              else
                for (final r in reviews.take(3)) _ReviewTile(review: r, accent: product.color),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final Review review;
  final Color accent;
  const _ReviewTile({required this.review, required this.accent});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Stars(review.stars),
            const SizedBox(width: 8),
            Expanded(
              child: Text(review.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 4),
          Text(review.body),
          const SizedBox(height: 6),
          Text('👍 ${review.helpful} found this helpful',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
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
              'The overall score is relative to this group and weighs five factors '
              'equally. Which trade-offs matter depends on your needs, so you decide '
              'what fits.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
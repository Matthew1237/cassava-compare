// Compare screen: nutrition tab, critical-reviews tab, and their widgets.
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

  List<Product> get _visible =>
      widget.products.where((p) => !_hidden.contains(p.id)).toList();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Comparing ${widget.products.length} products'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.bar_chart), text: 'Nutrition'),
            Tab(icon: Icon(Icons.report_gmailerrorred_outlined), text: 'Critical reviews'),
          ]),
        ),
        body: TabBarView(children: [
          _buildNutritionTab(context),
          _buildReviewsTab(context),
        ]),
      ),
    );
  }

  Widget _buildNutritionTab(BuildContext context) {
    final visible = _visible;
    final missingServing = visible.any((p) => p.nutrition.servingGrams == null);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final p in widget.products)
              FilterChip(
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
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Per 100 g')),
            ButtonSegment(value: true, label: Text('Per serving')),
          ],
          selected: {_perServing},
          onSelectionChanged: (s) => setState(() => _perServing = s.first),
        ),
        if (_perServing && missingServing)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Some products have no serving size in the database; they show "–" per serving.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 14),
        _GroupedOverview(products: visible, perServing: _perServing),
        const SizedBox(height: 12),
        for (final m in Metric.values)
          _MetricCard(metric: m, products: visible, perServing: _perServing),
        const SizedBox(height: 4),
        _SideBySideTable(products: visible, perServing: _perServing),
        const SizedBox(height: 12),
        _IngredientsCard(products: visible),
        const SizedBox(height: 12),
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

double _maxOf(Iterable<double?> vs) => vs.whereType<double>().fold<double>(0, math.max);

class _GroupedOverview extends StatelessWidget {
  final List<Product> products;
  final bool perServing;
  const _GroupedOverview({required this.products, required this.perServing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Overview',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text('Columns are scaled within each nutrient.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [for (final m in Metric.values) Expanded(child: _group(context, m))],
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(BuildContext context, Metric m) {
    final values = {
      for (final p in products) p.id: p.nutrition.value(m, perServing: perServing)
    };
    final maxV = _maxOf(values.values);
    final denom = maxV == 0 ? 1.0 : maxV;
    return Column(
      children: [
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final p in products)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (values[p.id] ?? 0) / denom),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, f, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(fmt(values[p.id]), style: const TextStyle(fontSize: 9)),
                      const SizedBox(height: 2),
                      Container(
                        width: 12,
                        height: math.max(3, 104 * f),
                        decoration: BoxDecoration(
                          color: values[p.id] == null
                              ? Colors.grey.withValues(alpha: 0.3)
                              : p.color,
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Icon(m.icon, size: 16),
        Text(m.label, style: Theme.of(context).textTheme.labelSmall),
        Text(m.unit,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
      ],
    );
  }
}

class _MetricCard extends StatefulWidget {
  final Metric metric;
  final List<Product> products;
  final bool perServing;
  const _MetricCard(
      {required this.metric, required this.products, required this.perServing});

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
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _selected = _selected == p.id ? null : p.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 104,
                        child: Text(p.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  _selected == p.id ? FontWeight.w700 : FontWeight.w500,
                            )),
                      ),
                      Expanded(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: (values[p.id] ?? 0) / denom),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (_, f, _) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              Container(
                                height: 18,
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              if (values[p.id] != null)
                                FractionallySizedBox(
                                  widthFactor: f.clamp(0.02, 1.0),
                                  child: Container(
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: p.color,
                                      borderRadius: BorderRadius.circular(6),
                                      border: _selected == p.id
                                          ? Border.all(color: cs.onSurface, width: 1.5)
                                          : null,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: Text(
                            values[p.id] == null ? 'n/a' : '${fmt(values[p.id])} ${m.unit}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12)),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Side by side',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(94),
                columnWidths: const {0: FixedColumnWidth(92)},
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
                        child: Text(p.name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall),
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
                            textAlign: TextAlign.center),
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
            ),
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
            Text('Ingredients',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
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
              'No scores, no rankings. Which trade-offs matter depends on your needs — '
              'you decide what fits.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
// Product details sheet, opened from the basket: watch-list flags, shelf
// price, and similar products from the same category with plain differences.
import 'package:flutter/material.dart';

import 'models.dart';
import 'services.dart';
import 'watchlist.dart';

/// Up to three plain differences of [other] against [base], per 100 g,
/// biggest first: "35% less sugar", "2.1× the protein".
/// Differences under 10% are left out; an empty list means "similar".
List<String> differences(Product base, Product other) {
  const metrics = [Metric.sugar, Metric.fat, Metric.sodium, Metric.calories, Metric.protein];
  final found = <(double, String)>[];
  for (final m in metrics) {
    final b = base.nutrition.per100(m), o = other.nutrition.per100(m);
    if (b == null || o == null || b <= 0) continue;
    final change = (o - b) / b;
    if (change.abs() < 0.1) continue;
    final what = m.label.toLowerCase();
    final less = m == Metric.calories ? 'fewer' : 'less'; // calories are countable
    final text = change >= 1
        ? '${(o / b).toStringAsFixed(1)}× the $what'
        : '${(change.abs() * 100).round()}% ${change < 0 ? less : 'more'} $what';
    found.add((change.abs(), text));
  }
  found.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final f in found.take(3)) f.$2];
}

/// Asks for a shelf price and the package size. Returns null when cancelled,
/// or (null, null) when the user clears the price.
Future<(double?, double?)?> askPrice(BuildContext context, Product p) {
  final price = TextEditingController(text: p.price?.toStringAsFixed(2) ?? '');
  final grams = TextEditingController(text: p.quantityGrams == null ? '' : fmt(p.quantityGrams));
  double? parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
  return showDialog<(double?, double?)>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Shelf price'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: price,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Price', hintText: 'e.g. 2.49'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: grams,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Package size (g or ml)',
              helperText: 'Filled in from the database when known.',
            ),
          ),
        ],
      ),
      actions: [
        if (p.price != null)
          TextButton(onPressed: () => Navigator.pop(ctx, (null, null)), child: const Text('Clear')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final v = parse(price.text);
            if (v == null || v < 0) return; // keep the dialog open until it's a number
            Navigator.pop(ctx, (v, parse(grams.text)));
          },
          child: const Text('Save price'),
        ),
      ],
    ),
  );
}

/// Bottom sheet for one basket product.
class ProductSheet extends StatefulWidget {
  final Product product;
  final OpenFoodFactsService service;
  final WatchList watch;
  final Future<void> Function(String barcode) onAdd;
  final Future<void> Function(Product p) onEditPrice;
  final bool Function(String barcode) inBasket;

  const ProductSheet({
    super.key,
    required this.product,
    required this.service,
    required this.watch,
    required this.onAdd,
    required this.onEditPrice,
    required this.inBasket,
  });

  @override
  State<ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<ProductSheet> {
  late final Future<List<Product>> _similar = widget.service.similar(widget.product);
  final Set<String> _adding = {};

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final flags = watchFlags(p, widget.watch);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            children: [
              ProductThumb(p, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: tt.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(p.category, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          if (flags.isNotEmpty) ...[
            const SizedBox(height: 12),
            WatchFlagChips(flags),
          ],
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: Text(p.price == null ? 'Add shelf price' : 'Price ${p.price!.toStringAsFixed(2)}'),
              subtitle: Text(p.pricePer100g != null
                  ? '${p.pricePer100g!.toStringAsFixed(2)} per 100 g'
                  : p.price != null
                      ? 'Add the package size to see the price per 100 g'
                      : 'Compare cost per 100 g across your basket'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                await widget.onEditPrice(p);
                if (mounted) setState(() {});
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 24, 4, 4),
            child: Text('Similar products', style: tt.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text('Same category, compared per 100 g with this product.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          FutureBuilder<List<Product>>(
            future: _similar,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                final e = snap.error;
                return Text(e is LookupException ? e.message : 'Could not load similar products.',
                    style: TextStyle(color: cs.onSurfaceVariant));
              }
              final items = snap.data!;
              if (items.isEmpty) {
                return Text('No similar products found for this category.',
                    style: TextStyle(color: cs.onSurfaceVariant));
              }
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, s) in items.indexed) ...[
                      if (i > 0) Divider(height: 1, indent: 72, color: cs.outlineVariant.withValues(alpha: 0.5)),
                      _similarTile(s),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _similarTile(Product s) {
    final diffs = differences(widget.product, s);
    final added = widget.inBasket(s.barcode);
    final busy = _adding.contains(s.barcode);
    return ListTile(
      leading: ProductThumb(s, size: 44),
      title: Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(diffs.isEmpty ? 'Similar nutrition' : diffs.join(' · ')),
      trailing: busy
          ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
          : IconButton(
              icon: Icon(added ? Icons.check_circle : Icons.add_circle_outline),
              tooltip: added ? 'In your basket' : 'Add ${s.name} to basket',
              onPressed: added
                  ? null
                  : () async {
                      setState(() => _adding.add(s.barcode));
                      await widget.onAdd(s.barcode);
                      if (mounted) setState(() => _adding.remove(s.barcode));
                    },
            ),
    );
  }
}

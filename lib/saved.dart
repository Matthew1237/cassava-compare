// Saved comparisons, remembered shelf prices, and the text summary used when
// sharing a comparison. Everything is stored on the device only.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class SavedComparison {
  final String name;
  final List<String> barcodes;
  final DateTime savedAt;
  const SavedComparison(this.name, this.barcodes, this.savedAt);

  Map<String, dynamic> toJson() =>
      {'name': name, 'barcodes': barcodes, 'savedAt': savedAt.toIso8601String()};

  static SavedComparison? fromJson(dynamic j) {
    if (j is! Map) return null;
    final codes = (j['barcodes'] as List? ?? const []).whereType<String>().toList();
    final at = DateTime.tryParse('${j['savedAt']}');
    if (codes.isEmpty || at == null) return null;
    return SavedComparison('${j['name'] ?? 'Comparison'}', codes, at);
  }
}

class SavedStore {
  static const _key = 'saved.v1';

  static Future<List<SavedComparison>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map(SavedComparison.fromJson).whereType<SavedComparison>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<SavedComparison> all) async =>
      (await SharedPreferences.getInstance())
          .setString(_key, jsonEncode([for (final c in all) c.toJson()]));

  /// Newest first. A comparison with the same name replaces the old one.
  static Future<void> add(SavedComparison c) async {
    final all = await load()..removeWhere((o) => o.name == c.name);
    await _write([c, ...all]);
  }

  static Future<void> remove(SavedComparison c) async {
    final all = await load()..removeWhere((o) => o.name == c.name && o.savedAt == c.savedAt);
    await _write(all);
  }
}

/// Shelf prices (and corrected package sizes) remembered per barcode.
class PriceStore {
  static const _key = 'prices.v1';

  static Future<Map<String, (double, double?)>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return {};
      return {
        for (final MapEntry(:key, :value) in (jsonDecode(raw) as Map).entries)
          if (value is Map && value['price'] is num)
            '$key': ((value['price'] as num).toDouble(), (value['grams'] as num?)?.toDouble()),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> set(String barcode, double? price, double? grams) async {
    final all = await load();
    if (price == null) {
      all.remove(barcode);
    } else {
      all[barcode] = (price, grams);
    }
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode({
      for (final MapEntry(:key, :value) in all.entries) key: {'price': value.$1, 'grams': value.$2},
    }));
  }
}

String _money(double v) => v.toStringAsFixed(2);

/// Plain-text summary of a comparison, for sharing in a chat.
String comparisonSummary(List<Product> ps, {bool perServing = false}) {
  final b = StringBuffer('Cassava comparison (${perServing ? 'per serving' : 'per 100 g'})\n');
  for (final p in ps) {
    final parts = [
      for (final m in Metric.values)
        if (p.nutrition.value(m, perServing: perServing) case final v?)
          '${m.label.toLowerCase()} ${fmt(v)} ${m.unit}',
      if (p.price case final price?)
        'price ${_money(price)}${p.pricePer100g == null ? '' : ' (${_money(p.pricePer100g!)} per 100 g)'}',
    ];
    b.write('\n${p.name}\n');
    b.write(parts.isEmpty ? '  no nutrition data\n' : '  ${parts.join(', ')}\n');
  }
  b.write('\nData: Open Food Facts');
  return b.toString();
}

/// Lists saved comparisons. Returns the one the user taps.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  List<SavedComparison>? _all;

  @override
  void initState() {
    super.initState();
    SavedStore.load().then((v) {
      if (mounted) setState(() => _all = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final all = _all;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved comparisons')),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bookmarks_outlined, size: 40, color: cs.onSurfaceVariant),
                        const SizedBox(height: 10),
                        Text('Nothing saved yet', style: tt.titleMedium),
                        const SizedBox(height: 4),
                        Text('Open a comparison and tap Save to keep it here.',
                            textAlign: TextAlign.center,
                            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final c in all)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            leading: const Icon(Icons.compare_arrows),
                            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${c.barcodes.length} products · '
                                '${MaterialLocalizations.of(context).formatMediumDate(c.savedAt)}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete ${c.name}',
                              onPressed: () async {
                                await SavedStore.remove(c);
                                setState(() => all.remove(c));
                              },
                            ),
                            onTap: () => Navigator.of(context).pop(c),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

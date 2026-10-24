// Product lookup (Open Food Facts) and review providers/analysis.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Product lookup (Open Food Facts)
// ─────────────────────────────────────────────────────────────────────────────

class LookupException implements Exception {
  final String message;
  LookupException(this.message);
  @override
  String toString() => message;
}

class OpenFoodFactsService {
  static const _fields =
      'code,product_name,brands,categories,image_front_small_url,ingredients_text,'
      'ingredients,additives_tags,nutriments,serving_quantity';

  final AdditiveRiskService risks = AdditiveRiskService();

  /// Returns null when the barcode is not in the database.
  Future<Product?> lookup(String barcode) async {
    final uri = Uri.https(
        'world.openfoodfacts.org', '/api/v2/product/$barcode.json', {'fields': _fields});
    final http.Response res;
    try {
      res = await http
          .get(uri, headers: {'User-Agent': 'NutriCompare/1.0 (flutter app)'})
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw LookupException('The lookup timed out. Check your connection.');
    } catch (_) {
      throw LookupException('Could not reach the product database. Are you online?');
    }
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw LookupException('Product database error (${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['status'] != 1) return null;
    final p = json['product'] as Map<String, dynamic>;
    final n = (p['nutriments'] as Map<String, dynamic>?) ?? {};

    double? num_(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');

    double? kcal = num_(n['energy-kcal_100g']);
    kcal ??= num_(n['energy_100g']) == null ? null : num_(n['energy_100g'])! / 4.184;

    // Sodium is reported in grams; fall back to salt (sodium = salt / 2.5).
    double? sodiumMg;
    final sodiumG = num_(n['sodium_100g']);
    final saltG = num_(n['salt_100g']);
    if (sodiumG != null) {
      sodiumMg = sodiumG * 1000;
    } else if (saltG != null) {
      sodiumMg = saltG * 400;
    }

    // Cholesterol is reported in grams; the app shows mg.
    final cholG = num_(n['cholesterol_100g']);

    String clean(dynamic v) => (v as String?)?.trim() ?? '';
    final name = clean(p['product_name']);
    final cats = clean(p['categories']);

    // Risk data is a nice-to-have; never fail the lookup because of it.
    try {
      await risks.ensureLoaded();
    } catch (_) {}

    final brand = clean(p['brands']).split(',').first.trim();
    final product = Product(
      barcode: barcode,
      name: name.isEmpty ? 'Unnamed product ($barcode)' : withBrand(brand, name),
      brand: brand,
      category: cats.isEmpty ? 'Food' : cats.split(',').last.trim(),
      imageUrl: p['image_front_small_url'] as String?,
      ingredients: clean(p['ingredients_text']).isEmpty ? null : clean(p['ingredients_text']),
      nutrition: Nutrition(
        calories: kcal,
        sugar: num_(n['sugars_100g']),
        fat: num_(n['fat_100g']),
        cholesterol: cholG == null ? null : cholG * 1000,
        sodium: sodiumMg,
        carbs: num_(n['carbohydrates_100g']),
        protein: num_(n['proteins_100g']),
        servingGrams: num_(p['serving_quantity']),
      ),
    );
    product.ingredientItems = risks.buildIngredients(
      ingredients: p['ingredients'],
      additiveTags: p['additives_tags'],
      fallbackText: product.ingredients,
    );
    return product;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ingredient risk (Open Food Facts additives taxonomy)
// ─────────────────────────────────────────────────────────────────────────────

/// Loads the Open Food Facts additives taxonomy once and classifies
/// ingredients by its "risk of over exposure" property (high / moderate /
/// no or very low). Additives with no class, and ordinary ingredients, are
/// reported as [RiskLevel.unclassified] rather than guessed.
class AdditiveRiskService {
  static const _url = '/data/taxonomies/additives.json';

  final Map<String, RiskLevel?> _risk = {};
  final Map<String, String> _names = {};
  bool _loaded = false;
  Future<void>? _loading;

  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final res = await http
          .get(Uri.https('static.openfoodfacts.org', _url),
              headers: {'User-Agent': 'NutriCompare/1.0 (flutter app)'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw LookupException('Risk data unavailable.');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      for (final e in data.entries) {
        final v = e.value;
        if (v is! Map) continue;
        _risk[e.key] = _parseRisk(v['efsa_evaluation_overexposure_risk']);
        final n = v['name'];
        final en = n is Map ? n['en'] : null;
        if (en is String && en.isNotEmpty) _names[e.key] = en;
      }
      _loaded = _risk.isNotEmpty;
    } catch (_) {
      _loading = null; // allow a retry on the next lookup
      rethrow;
    }
  }

  static RiskLevel? _parseRisk(dynamic raw) {
    String? s;
    if (raw is String) {
      s = raw;
    } else if (raw is Map && raw.isNotEmpty) {
      s = (raw['en'] ?? raw.values.first).toString();
    }
    if (s == null) return null;
    s = s.toLowerCase();
    if (s.contains('high')) return RiskLevel.high;
    if (s.contains('moderate')) return RiskLevel.limited;
    if (s.contains('no') || s.contains('low')) return RiskLevel.veryLow;
    return null;
  }

  /// "en:e330" style tag from an ingredient id or its printed text.
  static String? _additiveTag(String? id, String text) {
    final fromId = RegExp(r'^en:(e\d{3,4}[a-z]*)').firstMatch(id ?? '');
    if (fromId != null) return 'en:${fromId.group(1)}';
    final fromText =
        RegExp(r'\bE\s?(\d{3,4}[a-z]?)\b', caseSensitive: false).firstMatch(text);
    if (fromText != null) return 'en:e${fromText.group(1)!.toLowerCase()}';
    return null;
  }

  static String _codeOf(String tag) => tag.replaceFirst('en:', '').toUpperCase();

  List<Ingredient> buildIngredients({
    required dynamic ingredients,
    required dynamic additiveTags,
    String? fallbackText,
  }) {
    final out = <Ingredient>[];
    final seenTags = <String>{};
    final seenNames = <String>{};

    void add(String name, String? id) {
      final label = name.trim();
      if (label.isEmpty || !seenNames.add(label.toLowerCase())) return;
      final tag = _additiveTag(id, label);
      if (tag != null && _risk.containsKey(tag)) {
        seenTags.add(tag);
        out.add(Ingredient(label, _risk[tag] ?? RiskLevel.unclassified,
            code: _codeOf(tag)));
      } else {
        out.add(Ingredient(label, RiskLevel.unclassified));
      }
    }

    void walk(dynamic list) {
      if (list is! List) return;
      for (final i in list) {
        if (i is! Map) continue;
        final nested = i['ingredients'];
        if (nested is List && nested.isNotEmpty) {
          walk(nested); // keep the leaf ingredients only
        } else {
          add((i['text'] ?? i['id'] ?? '').toString(), i['id'] as String?);
        }
      }
    }

    walk(ingredients);

    if (out.isEmpty && fallbackText != null) {
      for (final part in fallbackText.split(RegExp(r'[,;]'))) {
        add(part.replaceAll(RegExp(r'[()\[\]_*]'), ' '), null);
      }
    }

    // Additives the database found that we did not match above.
    if (additiveTags is List) {
      for (final t in additiveTags.whereType<String>()) {
        if (seenTags.contains(t) || !_risk.containsKey(t)) continue;
        final name = _names[t] ?? _codeOf(t);
        if (seenNames.add(name.toLowerCase())) {
          out.add(Ingredient(name, _risk[t] ?? RiskLevel.unclassified,
              code: _codeOf(t)));
        }
      }
    }
    return out;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reviews (plug in a licensed source here)
// ─────────────────────────────────────────────────────────────────────────────

abstract class ReviewProvider {
  Future<List<Review>> reviewsFor(Product p);
}

class NoReviewProvider implements ReviewProvider {
  @override
  Future<List<Review>> reviewsFor(Product p) async => const [];
}

class ThemeStat {
  final String theme;
  final int count;
  final double share;
  const ThemeStat(this.theme, this.count, this.share);
}

class ReviewAnalyzer {
  /// Critical = 3 stars or fewer.
  static List<Review> critical(Product p) =>
      p.reviews.where((r) => r.stars <= 3).toList();

  static List<Review> helpful(Product p, {String? theme}) {
    final list = critical(p)
        .where((r) => theme == null || r.themes.contains(theme))
        .toList()
      ..sort((a, b) => b.helpful.compareTo(a.helpful));
    return list;
  }

  static List<ThemeStat> themes(Product p) {
    final crit = critical(p);
    final counts = <String, int>{};
    for (final r in crit) {
      for (final t in r.themes) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts.entries
        .map((e) => ThemeStat(e.key, e.value, e.value / crit.length))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  static double share(Product p, String theme) {
    final crit = critical(p);
    if (crit.isEmpty) return 0;
    return crit.where((r) => r.themes.contains(theme)).length / crit.length;
  }

  static List<String> allThemes(List<Product> ps) {
    final counts = <String, int>{};
    for (final p in ps) {
      for (final s in themes(p)) {
        counts[s.theme] = (counts[s.theme] ?? 0) + s.count;
      }
    }
    return counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  static String summary(Product p) {
    final t = themes(p);
    final n = critical(p).length;
    if (t.isEmpty) return 'No recurring complaints found.';
    final base =
        'Among $n critical reviews, "${t.first.theme}" comes up most (${t.first.count}).';
    if (t.length > 1 && t[1].count > 1) {
      return '$base "${t[1].theme}" is also mentioned repeatedly (${t[1].count}).';
    }
    return base;
  }
}
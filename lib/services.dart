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
      'ingredients,additives_tags,nutriments,serving_quantity,allergens_tags,traces_tags,'
      'ingredients_analysis_tags,categories_tags,product_quantity,quantity';

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

    String clean(dynamic v) => (v as String?)?.trim() ?? '';
    final name = clean(p['product_name']);
    final cats = clean(p['categories']);

    // Risk data is a nice-to-have; never fail the lookup because of it.
    try {
      await risks.ensureLoaded();
    } catch (_) {}

    List<String> tags(dynamic v) => v is List ? v.whereType<String>().toList() : <String>[];
    final categoryTags = englishCategories(tags(p['categories_tags']));

    final brand = clean(p['brands']).split(',').first.trim();
    final product = Product(
      barcode: barcode,
      name: name.isEmpty ? 'Unnamed product ($barcode)' : withBrand(brand, name),
      brand: brand,
      // The most specific real category reads best ("Colas", not "pt:bebidas cafeína").
      category: categoryTags.isNotEmpty
          ? _capitalize(tagLabel(categoryTags.last))
          : cats.isEmpty
              ? 'Food'
              : cats.split(',').last.trim(),
      imageUrl: p['image_front_small_url'] as String?,
      ingredients: clean(p['ingredients_text']).isEmpty ? null : clean(p['ingredients_text']),
      nutrition: nutritionFromOff(p['nutriments'], p['serving_quantity']),
    );
    product.ingredientItems = risks.buildIngredients(
      ingredients: p['ingredients'],
      additiveTags: p['additives_tags'],
      fallbackText: product.ingredients,
    );
    product
      ..allergens = tags(p['allergens_tags'])
      ..traces = tags(p['traces_tags'])
      ..analysis = tags(p['ingredients_analysis_tags'])
      ..categoryTags = categoryTags
      // OFF drops product_quantity unless "quantity" is also requested; read the
      // text ("400 g") as a fallback.
      ..quantityGrams = _num(p['product_quantity']) ?? _gramsFromText(clean(p['quantity']));
    return product;
  }

  /// Other products in the same category, most scanned first. Uses the
  /// search.openfoodfacts.org service, which supports category queries.
  /// Some specific categories have no products in the search index, so it
  /// widens to broader categories (up to 3 requests) until it finds some.
  Future<List<Product>> similar(Product of, {int limit = 12}) async {
    var found = <Product>[];
    for (final tag in of.categoryTags.reversed.take(3)) {
      found = await _similarIn(tag, of, limit);
      if (found.length >= 3) break;
    }
    return found;
  }

  Future<List<Product>> _similarIn(String tag, Product of, int limit) async {
    final uri = Uri.https('search.openfoodfacts.org', '/search', {
      'q': 'categories_tags:"$tag"',
      'page_size': '${limit + 4}',
      'sort_by': '-unique_scans_n',
      'fields': 'code,product_name,brands,image_front_small_url,nutriments,serving_quantity',
    });
    final http.Response res;
    try {
      res = await http
          .get(uri, headers: {'User-Agent': 'NutriCompare/1.0 (flutter app)'})
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw LookupException('The search timed out. Check your connection.');
    } catch (_) {
      throw LookupException('Could not reach the product database. Are you online?');
    }
    if (res.statusCode != 200) {
      throw LookupException('Product search is unavailable right now (${res.statusCode}).');
    }
    return parseSimilar(jsonDecode(res.body), of, limit: limit);
  }
}

/// Turns a search.openfoodfacts.org response into products, skipping [of]
/// itself, duplicates and unnamed entries.
List<Product> parseSimilar(dynamic json, Product of, {int limit = 12}) {
  final hits = (json is Map ? json['hits'] : null) as List? ?? const [];
  final out = <Product>[];
  for (final h in hits.whereType<Map<String, dynamic>>()) {
    final code = '${h['code'] ?? ''}';
    final rawName = h['product_name'];
    final name = (rawName is String ? rawName : '').trim();
    if (code.isEmpty || name.isEmpty || code == of.barcode) continue;
    if (out.any((o) => o.barcode == code)) continue;
    final b = h['brands'];
    final brand = (b is List ? b.whereType<String>().firstOrNull : b is String ? b.split(',').first : null)
            ?.trim() ??
        '';
    out.add(Product(
      barcode: code,
      name: withBrand(brand, name),
      brand: brand,
      category: of.category,
      imageUrl: h['image_front_small_url'] as String?,
      nutrition: nutritionFromOff(h['nutriments'], h['serving_quantity']),
    ));
    if (out.length == limit) break;
  }
  return out;
}

double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');

/// "400 g" or "330 ml" -> 400 / 330. Null for other units or no number.
double? _gramsFromText(String s) {
  final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(g|ml)', caseSensitive: false).firstMatch(s.trim());
  return m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', '.'));
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Category tags that are real taxonomy entries, in the order given (broad to
/// specific). Free-text entries such as "en:Pâtes à tartiner" are left out.
List<String> englishCategories(List<String> tags) =>
    [for (final t in tags) if (RegExp(r'^en:[a-z0-9-]+$').hasMatch(t)) t];

/// Reads Open Food Facts "nutriments" (per 100 g) into [Nutrition].
Nutrition nutritionFromOff(dynamic nutriments, dynamic servingQuantity) {
  final n = nutriments is Map ? nutriments : const {};

  double? kcal = _num(n['energy-kcal_100g']);
  kcal ??= _num(n['energy_100g']) == null ? null : _num(n['energy_100g'])! / 4.184;

  // Sodium is reported in grams; fall back to salt (sodium = salt / 2.5).
  double? sodiumMg;
  final sodiumG = _num(n['sodium_100g']);
  final saltG = _num(n['salt_100g']);
  if (sodiumG != null) {
    sodiumMg = sodiumG * 1000;
  } else if (saltG != null) {
    sodiumMg = saltG * 400;
  }

  // Cholesterol is reported in grams; the app shows mg.
  final cholG = _num(n['cholesterol_100g']);

  return Nutrition(
    calories: kcal,
    sugar: _num(n['sugars_100g']),
    fat: _num(n['fat_100g']),
    cholesterol: cholG == null ? null : cholG * 1000,
    sodium: sodiumMg,
    carbs: _num(n['carbohydrates_100g']),
    protein: _num(n['proteins_100g']),
    servingGrams: _num(servingQuantity),
  );
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
  final Map<String, List<String>> _uses = {};
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
        final uses = additiveUses(v['additives_classes']);
        if (uses.isNotEmpty) _uses[e.key] = uses;
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

  /// {"en": "en:acidity-regulator,en:antioxidant"} -> ["acidity regulator", "antioxidant"].
  static List<String> additiveUses(dynamic raw) {
    final s = raw is Map ? raw['en'] : raw;
    if (s is! String) return const [];
    return [
      for (final t in s.split(','))
        if (t.trim().isNotEmpty) tagLabel(t.trim())
    ];
  }

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
            code: _codeOf(tag), uses: _uses[tag] ?? const []));
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
              code: _codeOf(t), uses: _uses[t] ?? const []));
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
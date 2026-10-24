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
      'nutriments,serving_quantity';

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

    String clean(dynamic v) => (v as String?)?.trim() ?? '';
    final name = clean(p['product_name']);
    final cats = clean(p['categories']);

    return Product(
      barcode: barcode,
      name: name.isEmpty ? 'Unnamed product ($barcode)' : name,
      brand: clean(p['brands']).split(',').first.trim(),
      category: cats.isEmpty ? 'Food' : cats.split(',').last.trim(),
      imageUrl: p['image_front_small_url'] as String?,
      ingredients: clean(p['ingredients_text']).isEmpty ? null : clean(p['ingredients_text']),
      nutrition: Nutrition(
        calories: kcal,
        sugar: num_(n['sugars_100g']),
        fat: num_(n['fat_100g']),
        sodium: sodiumMg,
        servingGrams: num_(p['serving_quantity']),
      ),
    );
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
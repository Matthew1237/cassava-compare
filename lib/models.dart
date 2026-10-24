// Data models and small shared helpers/widgets.
import 'package:flutter/material.dart';

enum Metric { calories, sugar, fat, cholesterol, sodium, carbs, protein }

extension MetricInfo on Metric {
  String get label => switch (this) {
        Metric.calories => 'Calories',
        Metric.sugar => 'Sugar',
        Metric.fat => 'Total fat',
        Metric.cholesterol => 'Cholesterol',
        Metric.sodium => 'Sodium',
        Metric.carbs => 'Carbohydrates',
        Metric.protein => 'Protein',
      };

  String get unit => switch (this) {
        Metric.calories => 'kcal',
        Metric.sugar => 'g',
        Metric.fat => 'g',
        Metric.cholesterol => 'mg',
        Metric.sodium => 'mg',
        Metric.carbs => 'g',
        Metric.protein => 'g',
      };

  IconData get icon => switch (this) {
        Metric.calories => Icons.local_fire_department_outlined,
        Metric.sugar => Icons.cookie_outlined,
        Metric.fat => Icons.opacity_outlined,
        Metric.cholesterol => Icons.water_drop_outlined,
        Metric.sodium => Icons.grain,
        Metric.carbs => Icons.bakery_dining_outlined,
        Metric.protein => Icons.fitness_center,
      };

  /// General daily reference amounts (adult, 2,000 kcal diet). Shown only as
  /// context, never as a verdict.
  double get dailyReference => switch (this) {
        Metric.calories => 2000,
        Metric.sugar => 50,
        Metric.fat => 78,
        Metric.cholesterol => 300,
        Metric.sodium => 2300,
        Metric.carbs => 275,
        Metric.protein => 50,
      };
}

class Nutrition {
  /// Values per 100 g. Null = not available in the database.
  final double? calories, sugar, fat, cholesterol, sodium, carbs, protein;
  final double? servingGrams;

  const Nutrition({
    this.calories,
    this.sugar,
    this.fat,
    this.cholesterol,
    this.sodium,
    this.carbs,
    this.protein,
    this.servingGrams,
  });

  double? per100(Metric m) => switch (m) {
        Metric.calories => calories,
        Metric.sugar => sugar,
        Metric.fat => fat,
        Metric.cholesterol => cholesterol,
        Metric.sodium => sodium,
        Metric.carbs => carbs,
        Metric.protein => protein,
      };

  double? value(Metric m, {required bool perServing}) {
    final v = per100(m);
    if (v == null) return null;
    if (!perServing) return v;
    final s = servingGrams;
    return s == null ? null : v * s / 100;
  }
}

class Review {
  final int stars;
  final String title;
  final String body;
  final int helpful;
  final List<String> themes;

  const Review({
    required this.stars,
    required this.title,
    required this.body,
    required this.helpful,
    required this.themes,
  });
}

class Product {
  final String barcode, name, brand, category;
  final String? imageUrl, ingredients;
  final Nutrition nutrition;
  Color color = Colors.teal;
  double? avgRating;
  int? ratingCount;
  List<Review> reviews = [];

  /// Ingredients with their over-exposure risk class (see [RiskLevel]).
  List<Ingredient> ingredientItems = [];

  /// Open Food Facts tags: allergens and traces ("en:milk"), and the
  /// ingredients analysis ("en:non-vegan", "en:vegetarian"). Empty = unknown.
  List<String> allergens = [], traces = [], analysis = [];

  /// Real English category tags, broad to specific ("en:spreads",
  /// "en:sweet-spreads"). Used to find similar products.
  List<String> categoryTags = [];

  /// Package size in g (or ml) from the database, or as the user corrected it.
  double? quantityGrams;

  /// Shelf price the user entered, in their own currency.
  double? price;

  /// Price per 100 g, when both the price and the package size are known.
  double? get pricePer100g {
    final q = quantityGrams;
    return price == null || q == null || q <= 0 ? null : price! / q * 100;
  }

  Product({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.category,
    required this.nutrition,
    this.imageUrl,
    this.ingredients,
  });

  String get id => barcode;

  int countRisk(RiskLevel r) => ingredientItems.where((i) => i.risk == r).length;
}

// ─────────────────────────────────────────────────────────────────────────────
// Ingredient risk
// ─────────────────────────────────────────────────────────────────────────────

/// Based on Open Food Facts' "risk of over exposure" class for additives.
/// Ordinary ingredients (flour, sugar, milk...) have no class: [unclassified].
enum RiskLevel { high, limited, veryLow, unclassified }

extension RiskInfo on RiskLevel {
  String get label => switch (this) {
        RiskLevel.high => 'High risk',
        RiskLevel.limited => 'Limited risk',
        RiskLevel.veryLow => 'Very low risk',
        RiskLevel.unclassified => 'Not classified',
      };

  Color get color => switch (this) {
        RiskLevel.high => const Color(0xFFD32F2F),
        RiskLevel.limited => const Color(0xFFF9A825),
        RiskLevel.veryLow => const Color(0xFF388E3C),
        RiskLevel.unclassified => const Color(0xFF757575),
      };
}

class Ingredient {
  final String name;
  final String? code; // e.g. "E330" for additives
  final RiskLevel risk;

  /// What an additive is used for, e.g. ["flavour enhancer"]. Empty if unknown.
  final List<String> uses;
  const Ingredient(this.name, this.risk, {this.code, this.uses = const []});
}

/// "en:sesame-seeds" -> "sesame seeds".
String tagLabel(String tag) => tag.replaceFirst(RegExp(r'^[a-z]{2}:'), '').replaceAll('-', ' ');

/// Colors assigned to products in the order they are added.
const productPalette = [
  Color(0xFFE0A526),
  Color(0xFF3F6FD1),
  Color(0xFFD9692B),
  Color(0xFF6BAA75),
  Color(0xFF8D5A3B),
  Color(0xFF9B59B6),
];

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// "Cheetos" + "Crunchy" -> "Cheetos Crunchy". Skips the brand when the
/// product name already contains it.
String withBrand(String brand, String name) {
  final b = brand.trim(), n = name.trim();
  if (b.isEmpty) return n;
  if (n.isEmpty) return b;
  return n.toLowerCase().contains(b.toLowerCase()) ? n : '$b $n';
}

String fmt(double? v) {
  if (v == null) return '–';
  if (v >= 100) return v.round().toString();
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

class Stars extends StatelessWidget {
  final int count;
  const Stars(this.count, {super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Icon(i < count ? Icons.star : Icons.star_border,
                size: 16, color: Colors.amber.shade700),
        ],
      );
}

class ProductThumb extends StatelessWidget {
  final Product product;
  final double size;
  const ProductThumb(this.product, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final url = product.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: product.color.withValues(alpha: 0.2),
        child: url == null
            ? Icon(Icons.shopping_bag_outlined, color: product.color)
            : Image.network(url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.shopping_bag_outlined, color: product.color)),
      ),
    );
  }
}
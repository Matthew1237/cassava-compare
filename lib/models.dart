// Data models and small shared helpers/widgets.
import 'package:flutter/material.dart';

enum Metric { calories, sugar, fat, sodium }

extension MetricInfo on Metric {
  String get label => switch (this) {
        Metric.calories => 'Calories',
        Metric.sugar => 'Sugar',
        Metric.fat => 'Fat',
        Metric.sodium => 'Sodium',
      };

  String get unit => switch (this) {
        Metric.calories => 'kcal',
        Metric.sugar => 'g',
        Metric.fat => 'g',
        Metric.sodium => 'mg',
      };

  IconData get icon => switch (this) {
        Metric.calories => Icons.local_fire_department_outlined,
        Metric.sugar => Icons.cookie_outlined,
        Metric.fat => Icons.opacity_outlined,
        Metric.sodium => Icons.grain,
      };

  /// General daily reference amounts (adult, 2,000 kcal diet). Shown only as
  /// context, never as a verdict.
  double get dailyReference => switch (this) {
        Metric.calories => 2000,
        Metric.sugar => 50,
        Metric.fat => 78,
        Metric.sodium => 2300,
      };
}

class Nutrition {
  /// Values per 100 g. Null = not available in the database.
  final double? calories, sugar, fat, sodium;
  final double? servingGrams;

  const Nutrition({
    this.calories,
    this.sugar,
    this.fat,
    this.sodium,
    this.servingGrams,
  });

  double? per100(Metric m) => switch (m) {
        Metric.calories => calories,
        Metric.sugar => sugar,
        Metric.fat => fat,
        Metric.sodium => sodium,
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
}

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
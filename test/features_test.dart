import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_app/compare_screen.dart';
import 'package:my_app/main.dart';
import 'package:my_app/models.dart';
import 'package:my_app/product_sheet.dart';
import 'package:my_app/saved.dart';
import 'package:my_app/services.dart';
import 'package:my_app/watchlist.dart';

Product _p(String code, String name,
        {double? kcal, double? sugar, double? fat, double? sodium, double? protein}) =>
    Product(
      barcode: code,
      name: name,
      brand: '',
      category: 'Snacks',
      ingredients: 'potatoes, oil, salt',
      nutrition: Nutrition(
          calories: kcal, sugar: sugar, fat: fat, sodium: sodium, protein: protein, servingGrams: 30),
    );

/// Returns canned similar products instead of calling the network.
class _FakeService extends OpenFoodFactsService {
  final List<Product> items;
  _FakeService(this.items);
  @override
  Future<List<Product>> similar(Product of, {int limit = 12}) async => items;
}

/// Looks every barcode up as "Product <code>".
class _FakeLookup extends OpenFoodFactsService {
  @override
  Future<Product?> lookup(String barcode) async => _p(barcode, 'Product $barcode');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('watch-list flags', () {
    test('contains, may contain, and diet', () {
      final p = _p('1', 'Choc bar')
        ..allergens = ['en:milk']
        ..traces = ['en:peanuts']
        ..analysis = ['en:non-vegan', 'en:vegetarian'];
      const w = WatchList(allergens: {'en:milk', 'en:peanuts', 'en:gluten'}, diet: Diet.vegan);
      final texts = watchFlags(p, w).map((f) => f.text).toList();
      expect(texts, ['Contains milk', 'May contain peanuts', 'Not vegan']);
      expect(watchFlags(p, w).first.level, FlagLevel.contains);
    });

    test('missing data is reported as unknown, never as safe', () {
      final p = Product(
          barcode: '2', name: 'Mystery', brand: '', category: '', nutrition: const Nutrition());
      const w = WatchList(allergens: {'en:milk'}, diet: Diet.vegetarian);
      final flags = watchFlags(p, w);
      expect(flags.map((f) => f.text), ['No allergen data', 'Vegetarian status unknown']);
      expect(flags.every((f) => f.level == FlagLevel.unknown), isTrue);
    });

    test('vegan products count as vegetarian', () {
      final p = _p('3', 'Oat drink')..analysis = ['en:vegan'];
      expect(watchFlags(p, const WatchList(diet: Diet.vegetarian)), isEmpty);
    });

    test('saves and loads, ignoring unknown values', () async {
      const w = WatchList(allergens: {'en:eggs'}, diet: Diet.vegan, nutrients: [Metric.sodium]);
      await w.save();
      final back = await WatchList.load();
      expect(back.allergens, {'en:eggs'});
      expect(back.diet, Diet.vegan);
      expect(back.nutrients, [Metric.sodium]);
      expect(
          WatchList.fromJson({'diet': 'paleo', 'nutrients': ['sodium', 'vitamins']}).nutrients,
          [Metric.sodium]);
    });
  });

  group('similar products', () {
    test('differences: biggest first, small ones left out', () {
      final base = _p('1', 'A', sugar: 10, fat: 20, sodium: 500, protein: 5, kcal: 500);
      final other = _p('2', 'B', sugar: 6.5, fat: 19, sodium: 500, protein: 12, kcal: 480);
      expect(differences(base, other), ['2.4× the protein', '35% less sugar']);
      expect(differences(base, base), isEmpty);
    });

    test('parses search results, skipping itself, duplicates and unnamed', () {
      final of = _p('111', 'Cola')..categoryTags = ['en:colas'];
      final json = {
        'hits': [
          {'code': '111', 'product_name': 'Cola'},
          {
            'code': '222',
            'product_name': 'Zero',
            'brands': ['Fizz', 'Other'],
            'nutriments': {'sugars_100g': 0, 'salt_100g': 0.1, 'energy-kcal_100g': 1},
          },
          {'code': '222', 'product_name': 'Zero again'},
          {'code': '333', 'product_name': ''},
          {'code': '444', 'product_name': 'Lemon', 'brands': 'Brand X, Y'},
        ],
      };
      final out = parseSimilar(json, of);
      expect(out.map((p) => p.barcode), ['222', '444']);
      expect(out.first.name, 'Fizz Zero');
      expect(out.first.nutrition.sodium, closeTo(40, 0.001)); // salt 0.1 g -> 40 mg sodium
      expect(out.last.brand, 'Brand X');
    });
  });

  test('only real category tags are used, free text is skipped', () {
    expect(
        englishCategories([
          'en:spreads',
          'en:sweet-spreads',
          'en:Pâtes à tartiner',
          'fr:Nutella',
        ]),
        ['en:spreads', 'en:sweet-spreads']);
  });

  test('additive uses from the taxonomy', () {
    expect(AdditiveRiskService.additiveUses({'en': 'en:acidity-regulator,en:antioxidant'}),
        ['acidity regulator', 'antioxidant']);
    expect(AdditiveRiskService.additiveUses(null), isEmpty);
  });

  group('prices and saving', () {
    test('price per 100 g needs both price and package size', () {
      final p = _p('1', 'A')..price = 2.5;
      expect(p.pricePer100g, isNull);
      p.quantityGrams = 200;
      expect(p.pricePer100g, closeTo(1.25, 1e-9));
    });

    test('prices are remembered per barcode and can be cleared', () async {
      await PriceStore.set('123', 1.99, 150);
      expect((await PriceStore.load())['123'], (1.99, 150.0));
      await PriceStore.set('123', null, null);
      expect(await PriceStore.load(), isEmpty);
    });

    test('saved comparisons: newest first, same name replaces', () async {
      await SavedStore.add(SavedComparison('Crisps', ['1', '2'], DateTime(2026, 1, 1)));
      await SavedStore.add(SavedComparison('Cola', ['3', '4'], DateTime(2026, 1, 2)));
      await SavedStore.add(SavedComparison('Crisps', ['5', '6'], DateTime(2026, 1, 3)));
      final all = await SavedStore.load();
      expect(all.map((c) => c.name), ['Crisps', 'Cola']);
      expect(all.first.barcodes, ['5', '6']);
    });

    test('summary text lists each product with its values', () {
      final a = _p('1', 'Sea Salt Crisps', kcal: 532, sodium: 520)
        ..price = 2
        ..quantityGrams = 150;
      final text = comparisonSummary([a, _p('2', 'Empty')]);
      expect(text, contains('Sea Salt Crisps\n  calories 532 kcal, sodium 520 mg, price 2.00 (1.33 per 100 g)'));
      expect(text, contains('Empty\n  no nutrition data'));
    });
  });

  group('screens', () {
    testWidgets('watch-list screen saves choices', (t) async {
      await t.pumpWidget(const MaterialApp(home: WatchListScreen(initial: WatchList())));
      await t.tap(find.text('Peanuts'));
      await t.tap(find.text('Vegan'));
      await t.pumpAndSettle();
      final saved = await WatchList.load();
      expect(saved.allergens, {'en:peanuts'});
      expect(saved.diet, Diet.vegan);
    });

    testWidgets('home has watch-list and saved buttons', (t) async {
      await t.pumpWidget(const NutriCompareApp());
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Saved comparisons'));
      await t.pumpAndSettle();
      expect(find.text('Nothing saved yet'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('My watch-list'));
      await t.pumpAndSettle();
      expect(find.text('Allergens'), findsOneWidget);
    });

    testWidgets('compare screen: watch-list card, price rows, save', (t) async {
      final a = _p('1', 'Crisps A', kcal: 520, sodium: 400)
        ..allergens = ['en:milk']
        ..price = 2
        ..quantityGrams = 200;
      final b = _p('2', 'Crisps B', kcal: 480, sodium: 300);
      await t.pumpWidget(MaterialApp(
        home: CompareScreen(
            products: [a, b],
            watch: const WatchList(allergens: {'en:milk'}, nutrients: [Metric.sodium])),
      ));
      await t.pumpAndSettle();
      expect(find.text('Your watch-list'), findsOneWidget);
      expect(find.text('Contains milk'), findsOneWidget);
      // Watched nutrient is the first one shown.
      final list = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
      await t.scrollUntilVisible(find.widgetWithText(ChoiceChip, 'Sodium'), 200, scrollable: list);
      expect(find.widgetWithText(ChoiceChip, 'Sodium'), findsOneWidget);
      final chips = t.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      expect((chips.first.label as Text).data, 'Sodium');
      expect(chips.first.selected, isTrue);

      await t.scrollUntilVisible(find.text('Price / 100 g'), 300, scrollable: list);
      expect(find.text('1.00'), findsOneWidget);

      await t.tap(find.byTooltip('Save comparison'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Crisps run');
      await t.tap(find.widgetWithText(FilledButton, 'Save'));
      await t.pumpAndSettle();
      expect(find.text('Saved "Crisps run"'), findsOneWidget);
      expect((await SavedStore.load()).single.barcodes, ['1', '2']);
    });

    testWidgets('tapping an additive opens the explainer', (t) async {
      final a = _p('1', 'Noodles')
        ..ingredientItems = [
          const Ingredient('Monosodium glutamate', RiskLevel.high,
              code: 'E621', uses: ['flavour enhancer']),
        ];
      await t.pumpWidget(MaterialApp(home: CompareScreen(products: [a, _p('2', 'Rice')])));
      await t.tap(find.text('Ingredients'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ExpansionTile, 'Noodles'));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Monosodium glutamate'));
      await t.pumpAndSettle();
      expect(find.text('Used as: flavour enhancer.'), findsOneWidget);
      expect(find.textContaining('as high'), findsOneWidget);
    });

    testWidgets('scanner: typed barcode lands in the tray and the counter', (t) async {
      final codes = <String>[];
      await t.pumpWidget(MaterialApp(
        home: ScannerScreen(onCode: (code) async {
          codes.add(code);
          return ('Added Cola · Contains milk', _p(code, 'Cola'));
        }),
      ));
      await t.pump();
      expect(find.text('Nothing scanned yet'), findsOneWidget);

      await t.tap(find.byTooltip('Type number'));
      // The scan line animates forever, so advance time instead of settling.
      await t.pump(const Duration(milliseconds: 500));
      // Pasted text with spaces and letters keeps only the digits.
      await t.enterText(find.byType(TextField), 'EAN 5449 0000 00996');
      await t.tap(find.widgetWithText(FilledButton, 'Look up'));
      await t.pump(); // lookup runs
      await t.pump(const Duration(milliseconds: 800)); // highlight time passes
      expect(codes, ['5449000000996']);
      expect(find.text('Cola'), findsOneWidget);
      expect(find.text('Added Cola · Contains milk'), findsOneWidget);
      expect(find.text('Done · 1 added'), findsOneWidget);
      expect(find.text('1 added'), findsOneWidget);

      // After 8 s without a read, a tip appears.
      await t.pump(const Duration(seconds: 9));
      expect(find.textContaining('Having trouble?'), findsOneWidget);
    });

    testWidgets('loading a saved comparison can be undone', (t) async {
      await SavedStore.add(SavedComparison('Colas', ['2', '3'], DateTime(2026, 10, 24)));
      await t.pumpWidget(MaterialApp(home: HomeScreen(service: _FakeLookup())));
      await t.pumpAndSettle();

      // Build a basket by hand first.
      await t.tap(find.text('Type number'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '1');
      await t.tap(find.text('Look up'));
      await t.pumpAndSettle();
      expect(find.text('Product 1'), findsOneWidget);

      await t.tap(find.byTooltip('Saved comparisons'));
      await t.pumpAndSettle();
      await t.tap(find.text('Colas'));
      await t.pumpAndSettle();
      expect(find.text('Product 1'), findsNothing);
      expect(find.text('Product 2'), findsOneWidget);

      await t.tap(find.text('Undo'));
      await t.pumpAndSettle();
      expect(find.text('Product 1'), findsOneWidget);
      expect(find.text('Product 2'), findsNothing);
    });

    testWidgets('product sheet: similar products with differences, add one', (t) async {
      final base = _p('1', 'Cola', sugar: 10, kcal: 42)..categoryTags = ['en:colas'];
      final zero = _p('2', 'Cola Zero', sugar: 0, kcal: 1);
      final added = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProductSheet(
            product: base,
            service: _FakeService([zero]),
            watch: const WatchList(),
            onAdd: (code) async => added.add(code),
            onEditPrice: (_) async {},
            inBasket: (code) => added.contains(code),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Cola Zero'), findsOneWidget);
      expect(find.text('100% less sugar · 98% fewer calories'), findsOneWidget);
      await t.tap(find.byTooltip('Add Cola Zero to basket'));
      await t.pumpAndSettle();
      expect(added, ['2']);
      expect(find.byTooltip('In your basket'), findsOneWidget);
    });
  });
}

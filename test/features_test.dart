import 'dart:convert';

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

    /// Advances [ms] milliseconds in 50 ms frames (route animations need frames).
    Future<void> frames(WidgetTester t, int ms) async {
      for (var i = 0; i < ms ~/ 50; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    /// Opens the scanner from a button and records what it returns.
    Future<List<String?>> openScanner(
        WidgetTester t, Future<(String, Product?)> Function(String) onCode) async {
      final results = <String?>[];
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => ScannerScreen(onCode: onCode)))),
            child: const Text('open'),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      // The scan line animates forever, so advance time in frames instead of settling.
      await frames(t, 600);
      return results;
    }

    Future<void> typeCode(WidgetTester t, String text) async {
      await t.tap(find.byTooltip('Type number'));
      await frames(t, 400);
      await t.enterText(find.byType(TextField), text);
      await t.tap(find.widgetWithText(FilledButton, 'Look up'));
      await frames(t, 300); // dialog closes, lookup runs
    }

    testWidgets('scanner: one product is added, then it closes', (t) async {
      final codes = <String>[];
      final results = await openScanner(t, (code) async {
        codes.add(code);
        return ('Added Cola · Contains milk', _p(code, 'Cola'));
      });
      expect(find.text('Nothing scanned yet'), findsOneWidget);

      // Pasted text with spaces and letters keeps only the digits.
      await typeCode(t, 'EAN 5449 0000 00996');
      expect(codes, ['5449000000996']);
      expect(find.text('Added Cola · Contains milk'), findsOneWidget); // shown before closing

      await frames(t, 1200); // highlight time passes, page closes
      expect(find.byType(ScannerScreen), findsNothing);
      expect(results, ['Added Cola · Contains milk']);
    });

    testWidgets('scanner: a failed lookup stays open so you can retry', (t) async {
      final results = await openScanner(t, (code) async => ('Barcode $code is not a valid food product.', null));
      await typeCode(t, '123');
      await frames(t, 800);
      expect(find.byType(ScannerScreen), findsOneWidget);
      expect(find.text('Barcode 123 is not a valid food product.'), findsOneWidget);
      expect(results, isEmpty);

      // After 8 s without a read, a tip appears.
      await t.pump(const Duration(seconds: 9));
      expect(find.textContaining('Having trouble?'), findsOneWidget);

      await t.tap(find.text('Cancel'));
      await frames(t, 600);
      expect(results, [null]);
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

  group('small phone, large text (no overflow)', () {
    // 340 dp wide at 1.3× text: any overflow fails the test.
    Widget small(Widget home) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: home,
        );
    void phone(WidgetTester t) {
      t.view.physicalSize = const Size(340, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
    }

    final nuts = _p('1', 'Nutella hazelnut spread with cocoa', sugar: 56, kcal: 539)
      ..allergens = ['en:milk', 'en:nuts']
      ..price = 3.49
      ..quantityGrams = 400;
    const watch = WatchList(allergens: {'en:milk', 'en:nuts'}, diet: Diet.vegetarian);

    testWidgets('watch-list screen', (t) async {
      phone(t);
      await t.pumpWidget(small(const WatchListScreen(initial: watch)));
      await t.pumpAndSettle();
      expect(find.text('Allergens'), findsOneWidget);
      // The Diet buttons are further down; scroll so they are built and laid out.
      await t.scrollUntilVisible(find.text('Vegetarian'), 200);
      expect(find.text('Vegetarian'), findsOneWidget);
    });

    testWidgets('home with a flagged product in the basket', (t) async {
      phone(t);
      SharedPreferences.setMockInitialValues({'watchlist.v1': jsonEncode(watch.toJson())});
      await t.pumpWidget(small(HomeScreen(service: _FakeLookup())));
      await t.pumpAndSettle();
      // On a short screen with big text the buttons start below the fold.
      await t.scrollUntilVisible(find.text('Type number'), 200);
      await t.tap(find.text('Type number'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '1');
      await t.tap(find.text('Look up'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('Vegetarian status unknown'), 200);
      expect(find.text('Tap for details · swipe to remove'), findsOneWidget);
    });

    testWidgets('compare screen and product sheet', (t) async {
      phone(t);
      await t.pumpWidget(small(CompareScreen(
          products: [nuts, _p('2', 'Strawberry jam extra fruit', sugar: 59, kcal: 241)],
          watch: watch)));
      await t.pumpAndSettle();
      expect(find.text('Contains tree nuts'), findsOneWidget);

      await t.pumpWidget(small(Scaffold(
        body: ProductSheet(
          product: nuts,
          service: _FakeService([_p('3', 'Peanut butter smooth crunchy', protein: 25, sugar: 5)]),
          watch: watch,
          onAdd: (_) async {},
          onEditPrice: (_) async {},
          inBasket: (_) => false,
        ),
      )));
      await t.pumpAndSettle();
      expect(find.text('Similar products'), findsOneWidget);
    });
  });
}

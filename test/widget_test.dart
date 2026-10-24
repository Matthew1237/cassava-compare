import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/compare_screen.dart';
import 'package:my_app/main.dart';
import 'package:my_app/models.dart';

Product _product(String code, String name, double kcal) => Product(
      barcode: code,
      name: name,
      brand: '',
      category: 'Snacks',
      nutrition: Nutrition(calories: kcal, sugar: 5, fat: 10, sodium: 300, servingGrams: 30),
    );

void main() {
  testWidgets('Home shows scan action and empty basket', (tester) async {
    await tester.pumpWidget(const NutriCompareApp());

    expect(find.text('Cassava'), findsOneWidget);
    expect(find.text('Scan a barcode'), findsOneWidget);
    expect(find.text('Type number'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Your basket is empty'), findsOneWidget);
    // Compare bar only appears once something is in the basket.
    expect(find.text('Compare'), findsNothing);
  });

  testWidgets('Compare screen splits into three tabs', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CompareScreen(products: [_product('1', 'Crisps A', 520), _product('2', 'Crisps B', 480)]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Nutrition'), findsOneWidget);
    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.text('Reviews'), findsOneWidget);
    // The list builds lazily, so scroll the section into view first.
    await tester.scrollUntilVisible(find.text('Side by side'), 300,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
    expect(find.text('Side by side'), findsOneWidget);

    await tester.tap(find.text('Ingredients'));
    await tester.pumpAndSettle();
    expect(find.text('Tap a product to see which ingredients fall in each group.'), findsOneWidget);
  });
}

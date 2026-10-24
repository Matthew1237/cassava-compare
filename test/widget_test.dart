import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/main.dart';

void main() {
  testWidgets('Home shows scan action and empty basket', (tester) async {
    await tester.pumpWidget(const NutriCompareApp());

    expect(find.text('Scan a barcode'), findsOneWidget);
    expect(find.text('Type number'), findsOneWidget);
    expect(find.text('Front label'), findsOneWidget);
    expect(find.text('Your basket is empty'), findsOneWidget);
    // Compare bar only appears once something is in the basket.
    expect(find.text('Compare'), findsNothing);
  });
}

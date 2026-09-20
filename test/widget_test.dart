import 'package:flutter_test/flutter_test.dart';

import 'package:oregonetservice/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const OregonetServiceApp());
    expect(find.byType(OregonetServiceApp), findsOneWidget);
  });
}

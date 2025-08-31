import 'package:flutter_test/flutter_test.dart';

import 'package:insession_flutter/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const InSessionApp());

    // Verify that our counter starts at 0.
    expect(find.text('InSession'), findsOneWidget);
  });
}

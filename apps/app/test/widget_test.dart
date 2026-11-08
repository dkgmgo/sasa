import 'package:flutter_test/flutter_test.dart';
import 'package:sasa/main.dart';
import 'package:sasa_core/sasa_core.dart';

void main() {
  testWidgets('placeholder screen shows the greeting', (tester) async {
    await tester.pumpWidget(const SasaApp());
    expect(find.text(sasaGreeting), findsOneWidget);
    expect(find.text(placeholderMessage()), findsOneWidget);
  });
}

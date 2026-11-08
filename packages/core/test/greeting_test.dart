import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

void main() {
  test('placeholder message starts with the greeting', () {
    expect(placeholderMessage(), startsWith(sasaGreeting));
  });
}

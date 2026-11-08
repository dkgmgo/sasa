import 'package:sasa_cli/sasa_cli.dart';
import 'package:test/test.dart';

void main() {
  test('stub command reports not implemented', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runSasa(['brief'], out, err);
    expect(code, exitNotImplemented);
    expect(out.toString(), contains('not implemented'));
    expect(err.toString(), isEmpty);
  });

  test('unknown command is a usage error', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runSasa(['nope'], out, err);
    expect(code, exitUsage);
    expect(err.toString(), contains('Could not find a command'));
  });

  test('no arguments prints help and succeeds', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    expect(await runSasa([], out, err), 0);
  });
}

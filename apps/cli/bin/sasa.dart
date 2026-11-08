import 'dart:io';

import 'package:sasa_cli/sasa_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runSasa(arguments, stdout, stderr);
}

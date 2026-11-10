import 'dart:io';

import 'package:sasa_cli/sasa_cli.dart';

Future<void> main(List<String> arguments) async {
  final code = await runSasa(arguments, stdout, stderr);
  // Kept-alive CalDAV connections would otherwise hold the process open.
  closeHttp();
  await Future.wait([stdout.flush(), stderr.flush()]);
  exit(code);
}

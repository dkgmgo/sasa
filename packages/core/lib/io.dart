/// Parts of Sasa's core that need `dart:io` (a plain directory as the
/// synced folder). Import alongside `sasa_core.dart` on Linux, in the CLI
/// and in tests.
library;

export 'src/device_file.dart';
export 'src/log/io_sync_folder.dart';

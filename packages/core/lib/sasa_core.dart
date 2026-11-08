/// Pure-Dart domain logic for Sasa.
///
/// This library must never import Flutter, so it can be tested on the plain
/// Dart VM and reused by the command-line tool.
library;

export 'src/categoriser.dart';
export 'src/clock.dart';
export 'src/config/app_config.dart';
export 'src/config/defaults.dart';
export 'src/config/suggester_weights.dart';
export 'src/free_blocks.dart';
export 'src/greeting.dart';
export 'src/models/activity.dart';
export 'src/models/cal_event.dart';
export 'src/models/category.dart';
export 'src/models/energy.dart';
export 'src/models/focus_session.dart';
export 'src/models/free_block.dart';
export 'src/models/local_time.dart';
export 'src/models/mapping_rule.dart';
export 'src/models/nudge.dart';
export 'src/models/task_item.dart';
export 'src/sources/calendar_source.dart';
export 'src/time_zones.dart';

/// Reads calendars and tasks that DAVx⁵ synced onto an Android device.
///
/// - [DavxBridge]: method-channel access to `CalendarContract` and the
///   OpenTasks-compatible task provider of Tasks.org.
/// - [DavxProviderSource]: core's `CalendarSource` on top of it.
library;

export 'src/davx_provider_source.dart';
export 'src/mapping.dart';
export 'src/method_channel_bridge.dart';
export 'src/provider_rows.dart';

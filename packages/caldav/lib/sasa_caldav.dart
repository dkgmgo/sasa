/// CalDAV client and iCalendar parsing for Sasa (pure Dart).
///
/// - [CalDavClient]: discovery, collection listing, `calendar-query`.
/// - [CalDavSource]: core's `CalendarSource` on top of it, with client-side
///   recurrence expansion.
/// - iCalendar helpers: [parseIcal], [expandEvents], [eventsFromIcal],
///   [tasksFromIcal].
library;

export 'src/caldav_source.dart';
export 'src/dav/caldav_client.dart';
export 'src/dav/multistatus.dart' show DavResponse, parseMultistatus;
export 'src/ical/expand.dart';
export 'src/ical/ical_parser.dart';
export 'src/ical/ical_values.dart';
export 'src/ical/mapping.dart';

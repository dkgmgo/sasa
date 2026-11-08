# davx_bridge

Android-only Flutter plugin for Sasa. It reads, never writes:

- calendar instances from `CalendarContract.Instances` (recurrences already expanded), and
- tasks from the OpenTasks-compatible provider that DAVx⁵ syncs into: Tasks.org
  (`org.tasks.opentasks`, permission `org.tasks.permission.READ_TASKS`) or the OpenTasks app
  (`org.dmfs.tasks`).

Dart API:

- `DavxBridge`: method channel `fr.dkgmgo.davx_bridge` with `status`, `requestPermissions`,
  `calendars`, `instances(start, end)` and `tasks`. A missing permission or provider (and
  non-Android platforms) surface as core's `SourceUnavailable`.
- `DavxProviderSource`: core's `CalendarSource` on top of it. Only DAVx⁵ calendars and lists
  (`bitfire.at.davdroid`, `com.davdroid`) are used unless `includeAllCalendars` is set.

The Kotlin side only returns raw rows; mapping to `CalEvent`/`TaskItem` happens in Dart.
Reads need no activity and run off the main thread, so the plugin also works in the engine a
WorkManager background job starts. Permission prompts need the app in the foreground.

Tests:

```sh
flutter test # Dart: rows, mapping, source, channel
cd ../../apps/app && flutter build apk --debug
cd android && ./gradlew :davx_bridge:testDebugUnitTest
```

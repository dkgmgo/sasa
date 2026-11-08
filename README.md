# Sasa

A local-first day organiser. It reads the calendars and tasks you already keep in a CalDAV server (such as Radicale, directly or through DAVx⁵ on Android) and helps you use your free time: a morning brief, "I'm free, what now?" suggestions, and more. It is not meant to become another calendar.

## Development

Requirements: Flutter (stable), Android SDK with JDK 21, Linux desktop build
tools (clang, cmake, ninja, GTK 3 headers), podman and podman-compose.

```bash
flutter pub get
tools/check.sh # format, analyze, all tests
(cd apps/app && flutter run -d linux)
(cd apps/app && flutter run -d android)
dart run sasa_cli:sasa --help
tools/radicale-test/up.sh # test CalDAV server on 127.0.0.1:5232
(cd packages/caldav && dart test -P integration) # needs the test server
```

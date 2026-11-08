# sasa_caldav

Pure-Dart CalDAV client and iCalendar parsing for Sasa.

- `CalDavClient`: discovery (`/.well-known/caldav` -> `current-user-principal` ->
  `calendar-home-set`), collection listing with supported components, and
  `calendar-query` REPORTs (VEVENT by time range, open or all VTODOs). It only
  sends PROPFIND and REPORT, follows redirects by hand and sends credentials only
  to the configured origin.
- iCalendar: a small content-line parser, TZID resolution against the IANA
  database, and client-side expansion of RRULE (via the `rrule` package), RDATE,
  EXDATE and RECURRENCE-ID overrides. Server-side `expand` is not used.
- `CalDavSource`: core's `CalendarSource` on top of both, mapping to `CalEvent`
  and `TaskItem`. `openTasks()` fetches only open tasks.

Known limitations: custom `VTIMEZONE` definitions are not interpreted (unknown
TZIDs use the default zone), `RANGE=THISANDFUTURE` overrides are treated as
single-instance overrides, and `WKST` other than `MO` is ignored.

```bash
dart test # unit tests (recorded Radicale responses)
dart test -P integration # also against tools/radicale-test (must be up)
```

Fixtures in `test/fixtures/radicale/` were recorded from `tools/radicale-test`
after seeding.

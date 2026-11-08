# radicale-test

A disposable [Radicale](https://radicale.org) CalDAV server for Sasa's integration tests. It runs with rootless **podman**, listens on `127.0.0.1:5232` and keeps no data after `down.sh`.

```bash
tools/radicale-test/up.sh     # build image, start, wait, seed
tools/radicale-test/seed.sh   # re-seed a running server
tools/radicale-test/down.sh   # stop and delete everything
```

Requires `podman` and `podman-compose`. Set `SASA_RADICALE_PORT` to use another port.

- User: `test`, password: `test`
- `/test/sasa-calendar/` (VEVENT) and `/test/sasa-tasks/` (VTODO)

## Seed data (week of Monday 2026-11-02, Europe/Paris)

| File | What it exercises |
|---|---|
| `supervisor-meeting.ics` | Plain timed event with TZID and location |
| `lab-networks-weekly.ics` | Weekly RRULE from 2026-09-07 across the 2026-10-25 DST change, EXDATE on 2026-11-09, RECURRENCE-ID override moving 2026-11-16 to 14:00 |
| `optional-seminar.ics` | Timed event with `TRANSP:TRANSPARENT` (free) |
| `collaborator-call-utc.ics` | UTC times, no TZID |
| `allday-free.ics` | All-day, transparent |
| `allday-busy.ics` | All-day, opaque (busy) |
| `review-paper.ics` | VTODO, priority 1, due with time, categories |
| `prepare-lab-sockets.ics` | VTODO, due as a date |
| `read-openalex-docs.ics` | VTODO without due date |
| `expense-report-done.ics` | Completed VTODO (should be filtered out as not open) |

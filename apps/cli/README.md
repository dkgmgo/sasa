# sasa_cli

Command-line companion for Sasa (`sasa brief|tick|install-timers|suggest|report|status`), used for
background jobs on Linux.

```
dart run sasa_cli:sasa --help
dart run sasa_cli:sasa status # folder, device, event log, conflicts, CalDAV account
dart run sasa_cli:sasa brief # print today's brief and show it as a notification
dart run sasa_cli:sasa brief --no-notify # print only
```

- `sasa brief` reads today's events and the tasks from CalDAV and sends the brief to the desktop notification server over D-Bus (`org.freedesktop.Notifications`). With `--scheduled` (used by the timer) it only sends on a brief day, from the brief time until 3 hours later.
- `sasa install-timers` writes `sasa-brief.{service,timer}` and `sasa-tick.{service,timer}` to `~/.config/systemd/user/` (`--unit-dir`, `--dry-run`) and prints the `systemctl --user` commands to enable them. It needs a compiled executable (`dart compile exe bin/sasa.dart -o ~/.local/bin/sasa`, or pass `--exec`). `--folder`, `--device-file` and `--secrets-file` given to it are written into the units.
- `sasa tick` (every 15 minutes) rewrites the brief timer when the brief settings in `config.json` changed, then runs `systemctl --user daemon-reload` and restarts the timer if it is active.

The synced folder and device id come from `~/.config/sasa/device.json`, which the Linux app writes
when you choose a folder (override with `--folder` or `SASA_FOLDER`). The CLI writes as the same
device as the app on this machine.

The CalDAV account is looked up, in order, in:

1. the environment: `SASA_CALDAV_URL`, `SASA_CALDAV_USER`, `SASA_CALDAV_PASSWORD`;
2. an env file with the same variables, `~/.config/sasa/secrets.env` by default (`--secrets-file`).
   Keep it `chmod 600`; a file inside the synced folder is refused;
3. the app's keyring entry (libsecret, read with `secret-tool`), so nothing needs configuring when
   the Linux app is set up.

Passwords are never printed.

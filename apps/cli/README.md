# sasa_cli

Command-line companion for Sasa (`sasa brief|tick|suggest|report|status`), used for background jobs on Linux.

```
dart run sasa_cli:sasa --help
dart run sasa_cli:sasa status # folder, device, event log, conflicts, CalDAV account
```

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

# sasa_core

Pure-Dart domain logic for Sasa: models, free blocks, categoriser, suggester, nudges, stats and the event log.

## Event log

`EventLog` stores app history as append-only JSON lines in the synced folder:

```
Sasa/
├── config.json # AppConfig, newest updatedAt wins
└── devices/<deviceId>/log-YYYY-MM.jsonl
```

Each line is `{id, ts, device, type, v, data}`. `load()` reads every device's files, skips lines it
cannot parse (e.g. one torn by a crash), de-duplicates by `id` (so sync-conflict copies are
harmless), sorts by `ts`, device, id, and folds the events into an `AppState`. Events from a newer
schema version are counted, not applied. `SasaFolder` also finds and resolves conflict copies of
`config.json`.

Storage goes through the `SyncFolder` interface: `MemorySyncFolder` for tests, `IoSyncFolder`
(`package:sasa_core/io.dart`) for a plain directory, and the `saf_folder` plugin on Android.

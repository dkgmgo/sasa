# saf_folder

Android-only Flutter plugin for Sasa: file access inside a folder the user picks with the Storage
Access Framework (the folder Syncthing or Nextcloud keeps in sync).

- `SafFolder.pickTree()` shows the system folder picker and persists read+write access to the
  chosen tree, so it survives restarts.
- `list`, `read`, `append`, `write` and `delete` take the tree URI and a relative path
  (`Sasa/devices/<id>/log-2026-11.jsonl`). Missing directories are created on write.
- `SafSyncFolder` implements core's `SyncFolder` on top of it, so the event log and `config.json`
  code is the same as on Linux.

Every call except the picker only needs the application context, so the plugin also works in a
WorkManager background engine. All document work runs on one thread shared by every engine of the
process, so the UI and a background job never interleave a create or an append. A revoked grant
surfaces as `SafAccessLost`; the app then asks for the folder again. No permissions are declared.

Tests:

```sh
flutter test # Dart: channel mapping, SafSyncFolder
cd ../../apps/app && flutter build apk --debug
cd android && ./gradlew :saf_folder:testDebugUnitTest # Kotlin: path resolution (SafTree)
```

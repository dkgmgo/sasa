import 'package:davx_bridge/davx_bridge.dart';
import 'package:flutter/material.dart';
import 'package:sasa_core/sasa_core.dart';

import 'data_controller.dart';
import 'source_controller.dart';
import 'theme_controller.dart';

/// Settings: the synced folder and where calendars and tasks come from.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    this.data,
    this.theme,
    this.onEditSetup,
  });

  final SourceController controller;

  /// Shows the synced folder when given.
  final DataController? data;

  /// Shows the light/dark choice when given.
  final ThemeController? theme;

  /// Opens the folder and account setup.
  final VoidCallback? onEditSetup;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SourceController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (_c.setup == null) _c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final setup = _c.setup;
          final status = setup?.status;
          final folder = widget.data?.location;
          return ListView(
            children: [
              if (widget.theme case final theme?) ...[
                const _Header('Appearance'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: ValueListenableBuilder<ThemeMode>(
                    valueListenable: theme,
                    builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined),
                          label: Text('System'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {mode},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => theme.choose(s.first),
                    ),
                  ),
                ),
              ],
              if (widget.onEditSetup != null) ...[
                const _Header('Data'),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Synced folder'),
                  subtitle: Text(folder?.name ?? 'Not chosen'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onEditSetup,
                ),
                if (widget.data case final data? when data.isOpen)
                  ListenableBuilder(
                    listenable: data,
                    builder: (context, _) => FolderStatus(data: data),
                  ),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('CalDAV account'),
                  subtitle: const Text('Server, user name and password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onEditSetup,
                ),
              ],
              const _Header('Calendar and tasks'),
              ListTile(
                leading: const Icon(Icons.event_note),
                title: Text(switch (setup?.decision.kind) {
                  SourceKind.davxProvider => 'Source: DAVx⁵ on this device',
                  SourceKind.calDav => 'Source: CalDAV',
                  null => 'Source: checking…',
                }),
                subtitle: setup == null
                    ? null
                    : Text(setup.decision.reason.description),
                trailing: _c.busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.cloud_sync_outlined),
                title: const Text('Always use CalDAV'),
                subtitle: Text(
                  _c.isAndroid
                      ? 'Read the server directly instead of the calendars '
                            'and tasks DAVx⁵ synced to this phone.'
                      : 'CalDAV is the only source on this platform.',
                ),
                value: _c.isAndroid ? _c.forceCalDav : true,
                onChanged: _c.isAndroid && !_c.busy ? _c.setForceCalDav : null,
              ),
              if (_c.isAndroid && status != null) ...[
                ListTile(
                  leading: Icon(
                    status.calendarPermission
                        ? Icons.check_circle_outline
                        : Icons.block,
                  ),
                  title: const Text('Calendar access'),
                  subtitle: Text(
                    status.calendarPermission ? 'Granted' : 'Not granted',
                  ),
                ),
                ListTile(
                  leading: Icon(
                    status.taskPermission
                        ? Icons.check_circle_outline
                        : Icons.block,
                  ),
                  title: const Text('Task access'),
                  subtitle: Text(switch (status) {
                    BridgeStatus(taskAuthority: null) =>
                      'Tasks.org is not installed; tasks come from CalDAV.',
                    BridgeStatus(taskPermission: true) =>
                      'Granted (${status.taskAuthority})',
                    _ => 'Not granted; tasks come from CalDAV.',
                  }),
                ),
              ],
              if (_c.canRequestAccess)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: _c.busy ? null : _c.requestAccess,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Grant calendar and task access'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// One line about the merged logs in the synced folder.
class FolderStatus extends StatelessWidget {
  const FolderStatus({super.key, required this.data});

  final DataController data;

  @override
  Widget build(BuildContext context) {
    final snap = data.snapshot;
    final devices = snap?.devices.length ?? 0;
    final events = snap?.events.length ?? 0;
    return ListTile(
      leading: const Icon(Icons.history),
      title: const Text('Activity logs'),
      subtitle: Text(
        '$events event${events == 1 ? '' : 's'} from $devices '
        'device${devices == 1 ? '' : 's'}'
        '${(snap?.newerVersionEvents ?? 0) > 0 ? ' · some need a newer Sasa' : ''}',
      ),
      trailing: IconButton(
        tooltip: 'Reload',
        icon: const Icon(Icons.refresh),
        onPressed: data.busy ? null : data.reload,
      ),
    );
  }
}

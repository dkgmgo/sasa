import 'package:davx_bridge/davx_bridge.dart';
import 'package:flutter/material.dart';
import 'package:sasa_core/sasa_core.dart';

import 'source_controller.dart';

/// Settings: where calendars and tasks come from.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final SourceController controller;

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
          return ListView(
            children: [
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

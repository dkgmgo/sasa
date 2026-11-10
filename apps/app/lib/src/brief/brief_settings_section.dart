import 'package:flutter/material.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data_controller.dart';
import 'brief_scheduler.dart';

/// Settings for the morning brief: on/off, time and days (shared by all
/// devices through `config.json`), plus this phone's notification state.
class BriefSettingsSection extends StatelessWidget {
  const BriefSettingsSection({
    super.key,
    required this.data,
    this.brief,
    this.isLinux = false,
  });

  final DataController data;

  /// The phone's scheduler; null where the app does not schedule briefs.
  final BriefController? brief;

  /// Shows how the brief is sent on Linux (the `sasa` timers).
  final bool isLinux;

  Future<void> _save(BuildContext context, BriefSettings b) async {
    final error = await data.updateConfig(ConfigEdits.setBrief(b));
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _pickTime(BuildContext context, BriefSettings b) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: b.time.hour, minute: b.time.minute),
      helpText: 'Morning brief time',
    );
    if (picked == null || !context.mounted) return;
    await _save(
      context,
      b.copyWith(time: LocalTime(picked.hour, picked.minute)),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([data, ?brief]),
    builder: (context, _) {
      final config = data.config;
      if (config == null) return const SizedBox.shrink();
      final b = config.brief;
      final busy = data.busy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.wb_twilight),
            title: const Text('Morning brief'),
            subtitle: const Text(
              'Your day in one notification: events, free time, due tasks.',
            ),
            value: b.enabled,
            onChanged: busy
                ? null
                : (v) => _save(context, b.copyWith(enabled: v)),
          ),
          ListTile(
            enabled: b.enabled && !busy,
            leading: const Icon(Icons.schedule),
            title: const Text('Time'),
            subtitle: Text('${b.time} (${config.timeZone})'),
            onTap: () => _pickTime(context, b),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<BriefDays>(
              segments: const [
                ButtonSegment(
                  value: BriefDays.weekdays,
                  label: Text('Weekdays'),
                ),
                ButtonSegment(
                  value: BriefDays.everyDay,
                  label: Text('Every day'),
                ),
              ],
              selected: {b.days},
              showSelectedIcon: false,
              onSelectionChanged: b.enabled && !busy
                  ? (s) => _save(context, b.copyWith(days: s.first))
                  : null,
            ),
          ),
          if (brief case final c?) ..._phone(context, c, config),
          if (isLinux)
            const ListTile(
              leading: Icon(Icons.terminal),
              title: Text('On this computer'),
              subtitle: Text(
                'The brief comes from the sasa command: run '
                '`sasa install-timers` once. It follows '
                'these settings.',
              ),
            ),
        ],
      );
    },
  );

  List<Widget> _phone(BuildContext context, BriefController c, AppConfig cfg) {
    final s = c.status;
    final zone = locationOrDefault(cfg.timeZone);
    return [
      if (s != null && cfg.brief.enabled)
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: Text(
            s.next == null
                ? 'No brief scheduled'
                : 'Next: ${_when(s.next!, zone)}',
          ),
          subtitle: s.kept != null
              ? Text(s.kept!)
              : s.brief == null
              ? null
              : Text(s.brief!.title),
        ),
      if (!c.notificationsAllowed)
        ListTile(
          leading: const Icon(Icons.notifications_off_outlined),
          title: const Text('Notifications are off for Sasa'),
          subtitle: const Text('The brief cannot be shown.'),
          trailing: TextButton(
            onPressed: c.requestNotifications,
            child: const Text('Allow'),
          ),
        ),
      if (c.notificationsAllowed && !c.exactAllowed && cfg.brief.enabled)
        ListTile(
          leading: const Icon(Icons.alarm_off),
          title: const Text('Exact alarms not allowed'),
          subtitle: const Text(
            'Android may deliver the brief some minutes late.',
          ),
          trailing: TextButton(
            onPressed: c.requestExact,
            child: const Text('Allow'),
          ),
        ),
    ];
  }

  static String _when(DateTime at, tz.Location zone) {
    final l = tz.TZDateTime.from(at, zone);
    return '${formatShortDate(DateTime.utc(l.year, l.month, l.day))} '
        '${formatClock(at, zone)}';
  }
}

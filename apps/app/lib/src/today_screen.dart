import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'category_style.dart';
import 'theme/pwani.dart';
import 'theme/shapes.dart';
import 'today_controller.dart';

/// Today: the timeline of events and free blocks, coloured by category, and
/// the open tasks due soon.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.controller, this.onOpenInbox});

  final TodayController controller;

  /// Shows the Unclassified inbox.
  final VoidCallback? onOpenInbox;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Timer? _ticker;
  bool _showAllOverdue = false;

  TodayController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (!_c.loaded && !_c.loading) _c.refresh();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _c.tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) {
      final view = _c.today;
      final zone = _c.zone;
      final unclassified = _c.inbox?.itemCount ?? 0;
      final content = <Widget>[
        if (_c.loading) const LinearProgressIndicator(),
        if (view == null && !_c.loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Nothing loaded yet.')),
          ),
        if (view != null) _Header(view: view),
        for (final (icon, text) in loadErrors(_c))
          _ErrorCard(icon: icon, text: text),
        if (unclassified > 0)
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            elevation: 0,
            child: ListTile(
              // Sand stays light in both themes: keep Deep text on it.
              textColor: Theme.of(context).colorScheme.onTertiaryContainer,
              iconColor: Theme.of(context).colorScheme.onTertiaryContainer,
              leading: const Icon(Icons.inbox_outlined),
              title: Text(
                '$unclassified unclassified '
                'item${unclassified == 1 ? '' : 's'}',
              ),
              subtitle: const Text('Give them a category'),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onOpenInbox,
            ),
          ),
        if (view != null) ...[
          if (view.allDay.isNotEmpty) ...[
            const _SectionTitle('All day'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [for (final e in view.allDay) _AllDayChip(entry: e)],
            ),
          ],
          const _SectionTitle('Schedule'),
          _SectionCard(
            children: [
              if (view.timeline.isEmpty)
                const _Empty('No events and no free working time today.'),
              for (var i = 0; i <= view.timeline.length; i++) ...[
                if (i == view.nowIndex) _NowMarker(clock: _c.clock, zone: zone),
                if (i < view.timeline.length)
                  switch (view.timeline[i]) {
                    final EventEntry e => _EventRow(entry: e, zone: zone),
                    final FreeEntry f => _FreeRow(entry: f, zone: zone),
                  },
              ],
            ],
          ),
          const _SectionTitle('Due soon'),
          _SectionCard(
            children: [
              if (view.dueTasks.isEmpty)
                const _Empty('No open tasks due in the next days.'),
              if (view.visibleDueTasks(showAllOverdue: _showAllOverdue)
                  case final due) ...[
                if (view.visibleDueTasks(showAllOverdue: false).hiddenOverdue >
                    0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _showAllOverdue = !_showAllOverdue),
                      icon: Icon(
                        _showAllOverdue ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: Text(
                        _showAllOverdue
                            ? 'Show recent overdue only'
                            : 'Show ${due.hiddenOverdue} older overdue',
                      ),
                    ),
                  ),
                for (final t in due.tasks)
                  _TaskRow(due: t, now: _c.clock.now(), zone: zone),
              ],
            ],
          ),
        ],
      ];
      return RefreshIndicator(
        onRefresh: _c.refresh,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: content,
              ),
            ),
            // Room for the "I'm free" button above the waves.
            const SizedBox(height: 88),
            const WaveFooter(),
          ],
        ),
      );
    },
  );
}

/// The arch at the top: greeting, date and free time left.
class _Header extends StatelessWidget {
  const _Header({required this.view});
  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onPrimary;
    final events = view.timeline.whereType<EventEntry>().length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Arch(
        color: theme.colorScheme.primary,
        archHeight: 56,
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 20),
        child: Column(
          children: [
            Text(
              sasaGreeting,
              style: theme.textTheme.displaySmall?.copyWith(color: on),
            ),
            Text(
              formatDate(view.window.date),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(color: on),
            ),
            const SizedBox(height: 4),
            Text(
              !view.freeKnown
                  ? 'Free time unknown: the calendar did not load'
                  : view.freeRemaining == Duration.zero
                  ? 'No free working time left today'
                  : '${formatMinutes(view.freeRemaining.inMinutes)} '
                        'free today',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: on),
            ),
            Text(
              '$events event${events == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: on.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A white card holding a list section, closed by a wave line.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [...children, const SizedBox(height: 8), const WaveLine()],
      ),
    ),
  );
}

/// Problems loading events and tasks; one entry when both have the same
/// cause.
List<(IconData, String)> loadErrors(TodayController c) {
  final e = c.eventsError;
  final t = c.tasksError;
  if (e != null && e == t) return [(Icons.sync_problem, e)];
  return [
    if (e != null) (Icons.event_busy, 'Calendar: $e'),
    if (t != null) (Icons.task_alt, 'Tasks: $t'),
  ];
}

/// Placeholder until suggestions exist.
class ImFreeButton extends StatelessWidget {
  const ImFreeButton({super.key});

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    onPressed: () => showMessage(
      context,
      'Suggestions for free time are coming in a later version.',
    ),
    icon: const Icon(Icons.bolt),
    label: const Text("I'm free"),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(icon, color: scheme.onErrorContainer),
        title: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }
}

class _NowMarker extends StatelessWidget {
  const _NowMarker({required this.clock, required this.zone});
  final Clock clock;
  final tz.Location zone;

  @override
  Widget build(BuildContext context) {
    final color = PwaniColors.of(context).now;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            'Now ${formatClock(clock.now(), zone)}',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 2,
              decoration: ShapeDecoration(
                color: color,
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const double _timeWidth = 52;

/// Start (bold) over end (muted), then content; dimmed when past.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.start,
    required this.end,
    required this.status,
    required this.child,
    required this.zone,
    this.highlight,
  });

  final tz.Location zone;
  final DateTime start;
  final DateTime end;
  final TimeStatus status;
  final Widget child;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tabular = [FontFeature.tabularFigures()];
    return Opacity(
      opacity: status == TimeStatus.past ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: highlight == null
            ? null
            : ShapeDecoration(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: highlight!, width: 2),
                ),
              ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _timeWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatClock(start, zone),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: Pwani.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabular,
                    ),
                  ),
                  Text(
                    formatClock(end, zone),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.entry, required this.zone});
  final EventEntry entry;
  final tz.Location zone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry.event;
    final details = [
      e.calendarName,
      if (e.location case final l? when l.isNotEmpty) l,
      if (!e.busy) 'shown as free',
    ];
    return _TimelineRow(
      zone: zone,
      start: e.start,
      end: e.end,
      status: entry.status,
      highlight: entry.status == TimeStatus.current
          ? PwaniColors.of(context).now
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, style: theme.textTheme.bodyLarge),
                Text(
                  details.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: CategoryTag(entry.category)),
        ],
      ),
    );
  }
}

class _FreeRow extends StatelessWidget {
  const _FreeRow({required this.entry, required this.zone});
  final FreeEntry entry;
  final tz.Location zone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = entry.block;
    return _TimelineRow(
      zone: zone,
      start: b.start,
      end: b.end,
      status: entry.status,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: ShapeDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.6),
          shape: const StadiumBorder(),
        ),
        child: Row(
          children: [
            Icon(Icons.wb_sunny_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Free · ${formatMinutes(b.length.inMinutes)}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.entry});
  final EventEntry entry;

  @override
  Widget build(BuildContext context) => Tooltip(
    message:
        '${entry.category?.name ?? 'Unclassified'} · '
        '${entry.event.calendarName}',
    child: Chip(
      avatar: CategoryDot(entry.category),
      label: Text(entry.event.title),
    ),
  );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.due, required this.now, required this.zone});
  final DueTask due;
  final DateTime now;
  final tz.Location zone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = due.task;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CategoryDot(due.category, size: 14),
      minLeadingWidth: 14,
      title: Text(t.title),
      subtitle: Text(
        '${formatDue(t.due!, now: now, zone: zone)} · ${t.listName}',
        style: due.overdue ? TextStyle(color: scheme.error) : null,
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: CategoryTag(due.category),
      ),
    );
  }
}

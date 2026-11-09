import 'package:flutter/material.dart';
import 'package:sasa_core/sasa_core.dart';

import 'category_style.dart';
import 'data_controller.dart';
import 'rule_editor.dart';
import 'today_controller.dart';
import 'today_screen.dart';

/// Events and tasks no rule matches, grouped by calendar or list, with
/// one-tap rule creation.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, required this.today, required this.data});

  final TodayController today;
  final DataController data;

  static const _custom = #custom;

  Future<void> _assignGroup(BuildContext context, InboxGroup g) async {
    final config = data.config;
    if (config == null) return;
    final id = await pickCategory(
      context,
      config,
      title: g.field == MatchField.calendar
          ? 'Everything in calendar “${g.name}” is…'
          : 'Everything in list “${g.name}” is…',
    );
    if (id == null || !context.mounted) return;
    await _add(context, g.ruleFor(id));
  }

  Future<void> _classifyItem(
    BuildContext context, {
    required String title,
    required List<MappingRule> Function(String categoryId) choices,
  }) async {
    final config = data.config;
    if (config == null) return;
    // Placeholder category: only the match part is shown here.
    final options = choices(config.categories.first.id);
    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Classify “$title” by…',
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            for (final r in options)
              ListTile(
                leading: const Icon(Icons.rule),
                title: Text(describeMatch(r)),
                subtitle: Text('Priority ${r.priority}'),
                onTap: () => Navigator.of(sheet).pop(r),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Custom rule…'),
              onTap: () => Navigator.of(sheet).pop(_custom),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || picked == null) return;
    if (picked is! MappingRule) {
      await openRuleEditor(
        context,
        data: data,
        today: today,
        draft: options.last,
      );
      return;
    }
    final id = await pickCategory(
      context,
      config,
      title: '${describeMatch(picked)} →',
    );
    if (id == null || !context.mounted) return;
    await _add(
      context,
      MappingRule(
        field: picked.field,
        pattern: picked.pattern,
        categoryId: id,
        priority: picked.priority,
      ),
    );
  }

  Future<void> _add(BuildContext context, MappingRule rule) async {
    final error = await data.updateConfig(ConfigEdits.addRule(rule));
    if (!context.mounted) return;
    final name = data.config?.categoryById(rule.categoryId)?.name;
    showMessage(context, error ?? 'Rule added: ${describeMatch(rule)} → $name');
  }

  Future<void> _setIgnored(
    BuildContext context,
    InboxGroup g, {
    required bool ignored,
  }) async {
    final error = await data.updateConfig(
      ignored
          ? ConfigEdits.ignoreInInbox(g.ignoreKey)
          : ConfigEdits.unignoreInInbox(g.ignoreKey),
    );
    if (!context.mounted) return;
    showMessage(
      context,
      error ??
          (ignored
              ? '${_label(g)} is ignored for now. Find it at the bottom of '
                    'the inbox.'
              : '${_label(g)} is back in the inbox.'),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: today,
    builder: (context, _) {
      final inbox = today.inbox;
      if (inbox == null) {
        return Center(
          child: today.loading
              ? const CircularProgressIndicator()
              : const Text('Nothing loaded yet.'),
        );
      }
      final errors = loadErrors(today);
      if (inbox.isEmpty && inbox.ignored.isEmpty && errors.isNotEmpty) {
        // Nothing loaded is not the same as everything classified.
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (icon, text) in errors)
                  ListTile(leading: Icon(icon), title: Text(text)),
              ],
            ),
          ),
        );
      }
      if (inbox.isEmpty && inbox.ignored.isEmpty) return const _AllClear();
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (inbox.isEmpty)
            const _AllClear()
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                'Events in the next $inboxLookaheadDays days and open tasks '
                'that no rule matches. Rules stay in Sasa: your calendars '
                'are not changed.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          for (final g in inbox.groups)
            _GroupCard(
              key: ValueKey(g.ignoreKey),
              group: g,
              today: today,
              onAssign: () => _assignGroup(context, g),
              onCustomRule: () => openRuleEditor(
                context,
                data: data,
                today: today,
                draft: g.ruleFor(data.config!.categories.first.id),
              ),
              onIgnore: () => _setIgnored(context, g, ignored: true),
              onClassifyEvent: (e) => _classifyItem(
                context,
                title: e.title,
                choices: (id) => ruleChoicesForEvent(e, categoryId: id),
              ),
              onClassifyTask: (t) => _classifyItem(
                context,
                title: t.title,
                choices: (id) => ruleChoicesForTask(t, categoryId: id),
              ),
            ),
          if (inbox.ignored.isNotEmpty)
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text('Ignored for now (${inbox.ignored.length})'),
                subtitle: const Text('Not counted as unclassified.'),
                shape: const Border(),
                children: [
                  for (final g in inbox.ignored)
                    ListTile(
                      title: Text(_label(g)),
                      subtitle: Text(_countText(g)),
                      trailing: TextButton(
                        onPressed: () =>
                            _setIgnored(context, g, ignored: false),
                        child: const Text('Show again'),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

String _label(InboxGroup g) => g.field == MatchField.calendar
    ? 'Calendar “${g.name}”'
    : 'List “${g.name}”';

String _countText(InboxGroup g) => g.field == MatchField.calendar
    ? '${g.count} event${g.count == 1 ? '' : 's'}'
    : '${g.count} task${g.count == 1 ? '' : 's'}';

enum _GroupAction { customRule, ignore }

/// One inbox group: its items (the first few, or all), and its actions.
class _GroupCard extends StatefulWidget {
  const _GroupCard({
    super.key,
    required this.group,
    required this.today,
    required this.onAssign,
    required this.onCustomRule,
    required this.onIgnore,
    required this.onClassifyEvent,
    required this.onClassifyTask,
  });

  final InboxGroup group;
  final TodayController today;
  final VoidCallback onAssign;
  final VoidCallback onCustomRule;
  final VoidCallback onIgnore;
  final void Function(CalEvent) onClassifyEvent;
  final void Function(TaskItem) onClassifyTask;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  static const _shown = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final zone = widget.today.zone;
    final limit = _expanded ? g.count : _shown;
    final events = g.events.take(limit);
    final tasks = g.tasks.take(limit);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(
                g.field == MatchField.calendar
                    ? Icons.calendar_month_outlined
                    : Icons.checklist,
              ),
              title: Text(_label(g)),
              subtitle: Text(_countText(g)),
              trailing: PopupMenuButton<_GroupAction>(
                tooltip: 'More',
                onSelected: (a) => switch (a) {
                  _GroupAction.customRule => widget.onCustomRule(),
                  _GroupAction.ignore => widget.onIgnore(),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _GroupAction.customRule,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Custom rule…'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _GroupAction.ignore,
                    child: ListTile(
                      leading: Icon(Icons.visibility_off_outlined),
                      title: Text('Ignore for now'),
                    ),
                  ),
                ],
              ),
            ),
            for (final e in events)
              ListTile(
                dense: true,
                title: Text(e.title),
                subtitle: Text(
                  e.allDay
                      ? '${formatShortDate(e.start)} · all day'
                      : '${formatShortDate(TodayWindow.of(e.start, zone).date)}'
                            ' · ${formatTimeRange(e.start, e.end, zone)}',
                ),
                trailing: const Icon(Icons.more_horiz),
                onTap: () => widget.onClassifyEvent(e),
              ),
            for (final t in tasks)
              ListTile(
                dense: true,
                title: Text(t.title),
                subtitle: t.tags.isEmpty
                    ? null
                    : Text(t.tags.map((x) => '#$x').join(' ')),
                trailing: const Icon(Icons.more_horiz),
                onTap: () => widget.onClassifyTask(t),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  if (g.count > _shown)
                    TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(
                        _expanded ? 'Show less' : 'Show all ${g.count}',
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  FilledButton.tonalIcon(
                    onPressed: widget.onAssign,
                    icon: const Icon(Icons.label_outline),
                    label: const Text('Assign category'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Everything has a category',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

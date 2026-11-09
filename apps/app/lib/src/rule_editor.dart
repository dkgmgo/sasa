import 'package:flutter/material.dart';
import 'package:sasa_core/sasa_core.dart';

import 'category_style.dart';
import 'data_controller.dart';
import 'today_controller.dart';

/// Opens the rule editor. With [editing], saving replaces that rule and a
/// delete action is offered; otherwise [draft] (or an empty title rule) is
/// added on save.
Future<void> openRuleEditor(
  BuildContext context, {
  required DataController data,
  required TodayController today,
  MappingRule? editing,
  MappingRule? draft,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => RuleEditor(
      data: data,
      today: today,
      editing: editing,
      initial: editing ?? draft,
    ),
  ),
);

/// Form for one [MappingRule], with a live preview of what it matches.
class RuleEditor extends StatefulWidget {
  const RuleEditor({
    super.key,
    required this.data,
    required this.today,
    this.editing,
    this.initial,
  });

  final DataController data;
  final TodayController today;
  final MappingRule? editing;
  final MappingRule? initial;

  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<RuleEditor> {
  late MatchField _field;
  late String _categoryId;
  late final TextEditingController _pattern;
  late final TextEditingController _priority;
  late final TextEditingController _duration;
  Energy? _energy;
  bool _saving = false;

  AppConfig get _config => widget.data.config!;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _field = r?.field ?? MatchField.titleRegex;
    _categoryId = r?.categoryId ?? _config.categories.first.id;
    _pattern = TextEditingController(text: r?.pattern ?? '');
    _priority = TextEditingController(text: '${r?.priority ?? 0}');
    _duration = TextEditingController(text: r?.durationMin?.toString() ?? '');
    _energy = r?.energy;
  }

  @override
  void dispose() {
    _pattern.dispose();
    _priority.dispose();
    _duration.dispose();
    super.dispose();
  }

  int? get _priorityValue => int.tryParse(_priority.text.trim());

  /// Null when blank (no override); -1 when not a number.
  int? get _durationValue {
    final t = _duration.text.trim();
    return t.isEmpty ? null : int.tryParse(t) ?? -1;
  }

  MappingRule get _rule => MappingRule(
    field: _field,
    pattern: _pattern.text,
    categoryId: _categoryId,
    priority: _priorityValue ?? 0,
    durationMin: _durationValue,
    energy: _energy,
  );

  Future<void> _apply(ConfigEdit edit) async {
    setState(() => _saving = true);
    final error = await widget.data.updateConfig(edit);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      showMessage(context, error);
    }
  }

  void _save() {
    final old = widget.editing;
    _apply(
      old == null
          ? ConfigEdits.addRule(_rule)
          : ConfigEdits.replaceRule(old, _rule),
    );
  }

  @override
  Widget build(BuildContext context) {
    final problems = ruleProblems(_rule, _config);
    final priorityBad = _priorityValue == null;
    final canSave = problems.isEmpty && !priorityBad && !_saving;
    final preview = previewRule(
      _rule,
      events: widget.today.events,
      tasks: widget.today.tasks,
    );
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? 'New rule' : 'Edit rule'),
        actions: [
          if (widget.editing != null)
            IconButton(
              tooltip: 'Delete rule',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving
                  ? null
                  : () => _apply(ConfigEdits.removeRule(widget.editing!)),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: canSave ? _save : null,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<MatchField>(
            isExpanded: true,
            initialValue: _field,
            decoration: const InputDecoration(labelText: 'Match on'),
            items: [
              for (final f in MatchField.values)
                DropdownMenuItem(
                  value: f,
                  child: Text(
                    matchFieldLabel(f),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (f) => setState(() => _field = f ?? _field),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pattern,
            decoration: InputDecoration(
              labelText: _field == MatchField.titleRegex
                  ? 'Regular expression'
                  : 'Name',
              helperText: switch (_field) {
                MatchField.calendar => 'Calendar name, any case.',
                MatchField.list => 'Task list name, any case.',
                MatchField.tag => 'Task tag, any case.',
                MatchField.titleRegex =>
                  'Searched in the title, any case. ^…\$ for the whole title.',
              },
              errorText: problems.contains(RuleProblem.badRegex)
                  ? RuleProblem.badRegex.message
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _config.categoryById(_categoryId) == null
                ? null
                : _categoryId,
            decoration: InputDecoration(
              labelText: 'Category',
              errorText: problems.contains(RuleProblem.unknownCategory)
                  ? RuleProblem.unknownCategory.message
                  : null,
            ),
            items: [
              for (final c in _config.categories)
                DropdownMenuItem(
                  value: c.id,
                  child: Row(
                    children: [
                      CategoryDot(c),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (id) => setState(() => _categoryId = id ?? _categoryId),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _priority,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: InputDecoration(
              labelText: 'Priority',
              helperText: 'Higher priorities are tried first.',
              errorText: priorityBad ? 'Enter a whole number.' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          Text('Overrides (optional)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Duration',
              suffixText: 'min',
              helperText: 'Blank: the category default.',
              errorText: problems.contains(RuleProblem.badDuration)
                  ? RuleProblem.badDuration.message
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text('Energy', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          SegmentedButton<Energy>(
            emptySelectionAllowed: true,
            segments: [
              for (final e in Energy.values)
                ButtonSegment(value: e, label: Text(energyLabel(e))),
            ],
            selected: {?_energy},
            onSelectionChanged: (s) =>
                setState(() => _energy = s.isEmpty ? null : s.first),
          ),
          const SizedBox(height: 24),
          Text('Preview', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            preview.count == 0
                ? 'Matches nothing loaded right now.'
                : 'Matches ${preview.events.length} '
                      'event${preview.events.length == 1 ? '' : 's'} and '
                      '${preview.tasks.length} '
                      'task${preview.tasks.length == 1 ? '' : 's'}.',
          ),
          for (final e in preview.events.take(5))
            ListTile(
              dense: true,
              leading: const Icon(Icons.event, size: 18),
              title: Text(e.title),
              subtitle: Text(e.calendarName),
            ),
          for (final t in preview.tasks.take(5))
            ListTile(
              dense: true,
              leading: const Icon(Icons.check_box_outline_blank, size: 18),
              title: Text(t.title),
              subtitle: Text(t.listName),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:sasa_core/sasa_core.dart';

import 'category_style.dart';
import 'data_controller.dart';
import 'theme/pwani.dart';
import 'theme/shapes.dart';

/// Opens the editor for [editing], or for a new category when null.
Future<void> openCategoryEditor(
  BuildContext context, {
  required DataController data,
  Category? editing,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => CategoryEditor(data: data, editing: editing),
  ),
);

/// Form for one category: name, colour, weekly target, defaults and
/// preferred time of day.
class CategoryEditor extends StatefulWidget {
  const CategoryEditor({super.key, required this.data, this.editing});

  final DataController data;
  final Category? editing;

  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  late final TextEditingController _name;
  late final TextEditingController _targetHours;
  late final TextEditingController _duration;
  late String _color;
  late Energy _energy;
  LocalTime? _windowStart;
  LocalTime? _windowEnd;
  bool _saving = false;

  AppConfig get _config => widget.data.config!;

  @override
  void initState() {
    super.initState();
    final c = widget.editing;
    _name = TextEditingController(text: c?.name ?? '');
    _targetHours = TextEditingController(text: _hours(c?.weeklyTargetMin ?? 0));
    _duration = TextEditingController(text: '${c?.defaultDurationMin ?? 30}');
    _color = c?.color ?? _unusedColor();
    _energy = c?.defaultEnergy ?? Energy.medium;
    _windowStart = c?.preferredWindow?.start;
    _windowEnd = c?.preferredWindow?.end;
  }

  String _unusedColor() {
    final used = {for (final c in _config.categories) c.color.toUpperCase()};
    return categoryPalette.firstWhere(
      (p) => !used.contains(p.toUpperCase()),
      orElse: () => categoryPalette.first,
    );
  }

  static String _hours(int minutes) {
    final h = minutes / 60;
    return h == h.roundToDouble() ? '${h.round()}' : h.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _name.dispose();
    _targetHours.dispose();
    _duration.dispose();
    super.dispose();
  }

  /// Null when not a number.
  int? get _targetMin {
    final h = double.tryParse(_targetHours.text.trim().replaceAll(',', '.'));
    return h == null ? null : (h * 60).round();
  }

  int? get _durationMin => int.tryParse(_duration.text.trim());

  bool get _hasWindow => _windowStart != null && _windowEnd != null;
  bool get _windowBad =>
      _hasWindow && _windowEnd!.compareTo(_windowStart!) <= 0;

  Category get _category => Category(
    id: widget.editing?.id ?? newCategoryId(_config, _name.text),
    name: _name.text.trim(),
    color: _color,
    weeklyTargetMin: _targetMin ?? -1,
    defaultEnergy: _energy,
    defaultDurationMin: _durationMin ?? 0,
    preferredWindow: _hasWindow && !_windowBad
        ? TimeWindow(_windowStart!, _windowEnd!)
        : null,
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

  Future<void> _delete() async {
    final c = widget.editing!;
    final rules = _config.rules.where((r) => r.categoryId == c.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete “${c.name}”?'),
        content: Text(
          rules == 0
              ? 'Items in it become unclassified.'
              : 'Its $rules rule${rules == 1 ? '' : 's'} will be deleted '
                    'too, and their items become unclassified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok ?? false) await _apply(ConfigEdits.removeCategory(c.id));
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _windowStart : _windowEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: current?.hour ?? (start ? 9 : 12),
        minute: current?.minute ?? 0,
      ),
    );
    if (picked == null) return;
    setState(() {
      final t = LocalTime(picked.hour, picked.minute);
      start ? _windowStart = t : _windowEnd = t;
    });
  }

  @override
  Widget build(BuildContext context) {
    final category = _category;
    final problems = categoryProblems(category, _config);
    final canSave = problems.isEmpty && !_windowBad && !_saving;
    final theme = Theme.of(context);
    String? error(CategoryProblem p) => problems.contains(p) ? p.message : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? 'New category' : 'Edit category'),
        actions: [
          if (widget.editing != null)
            IconButton(
              tooltip: 'Delete category',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: canSave
                  ? () => _apply(ConfigEdits.putCategory(category))
                  : null,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText:
                  error(CategoryProblem.duplicateName) ??
                  (_name.text.isEmpty
                      ? null
                      : error(CategoryProblem.emptyName)),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text('Colour', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final hex in {
                ...categoryPalette,
                if (parseHexColor(_color) != null) _color.toUpperCase(),
              })
                _Swatch(
                  hex: hex,
                  selected: hex.toUpperCase() == _color.toUpperCase(),
                  onTap: () => setState(() => _color = hex),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _targetHours,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Weekly target',
              suffixText: 'h',
              helperText: '0 for no target.',
              errorText: _targetMin == null
                  ? 'Enter a number of hours.'
                  : error(CategoryProblem.negativeTarget),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Default block length',
              suffixText: 'min',
              errorText: error(CategoryProblem.badDuration),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text('Default energy', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          SegmentedButton<Energy>(
            segments: [
              for (final e in Energy.values)
                ButtonSegment(value: e, label: Text(energyLabel(e))),
            ],
            selected: {_energy},
            onSelectionChanged: (s) => setState(() => _energy = s.first),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Preferred time of day'),
            subtitle: const Text('When this kind of work fits best.'),
            value: _windowStart != null,
            onChanged: (on) => setState(() {
              _windowStart = on ? const LocalTime(9, 0) : null;
              _windowEnd = on ? const LocalTime(12, 0) : null;
            }),
          ),
          if (_windowStart != null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(start: true),
                    child: Text('From $_windowStart'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(start: false),
                    child: Text('To $_windowEnd'),
                  ),
                ),
              ],
            ),
          if (_windowBad)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'The end must be after the start.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(parseHexColor(hex)!);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Colour $hex',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Stack(
          alignment: const Alignment(0, 0.4),
          children: [
            ArchMark(
              color: color,
              width: 42,
              height: 48,
              border: selected ? scheme.onSurface : scheme.outlineVariant,
            ),
            if (selected) Icon(Icons.check, color: textOn(color), size: 20),
          ],
        ),
      ),
    );
  }
}

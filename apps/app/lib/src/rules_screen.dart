import 'package:flutter/material.dart';
import 'package:sasa_core/sasa_core.dart';

import 'category_style.dart';
import 'data_controller.dart';
import 'rule_editor.dart';
import 'today_controller.dart';

/// The mapping rules, in the order they are tried.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key, required this.data, required this.today});

  final DataController data;
  final TodayController today;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: data,
    builder: (context, _) {
      final config = data.config;
      if (config == null) return const SizedBox.shrink();
      final rules = Categoriser.evaluationOrder(config.rules);
      final scheme = Theme.of(context).colorScheme;
      return ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Rules give events and tasks a category, inside Sasa only. '
              'They are tried from the highest priority down and the first '
              'match wins.',
            ),
          ),
          if (rules.isEmpty)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('No rules yet'),
              subtitle: Text(
                'Add one here, or assign categories from the inbox.',
              ),
            ),
          for (final r in rules)
            Builder(
              builder: (context) {
                final category = config.categoryById(r.categoryId);
                final problems = ruleProblems(r, config);
                final details = [
                  '→ ${category?.name ?? 'missing category'}',
                  'priority ${r.priority}',
                  if (r.durationMin != null) formatMinutes(r.durationMin!),
                  if (r.energy != null) '${energyLabel(r.energy!)} energy',
                ];
                return ListTile(
                  leading: problems.isEmpty
                      ? CategoryDot(category, size: 16)
                      : Icon(Icons.warning_amber, color: scheme.error),
                  title: Text(describeMatch(r)),
                  subtitle: Text(
                    [
                      details.join(' · '),
                      for (final p in problems) p.message,
                    ].join('\n'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openRuleEditor(
                    context,
                    data: data,
                    today: today,
                    editing: r,
                  ),
                );
              },
            ),
        ],
      );
    },
  );
}

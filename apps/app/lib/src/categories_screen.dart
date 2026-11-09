import 'package:flutter/material.dart';
import 'package:sasa_core/sasa_core.dart';

import 'category_editor.dart';
import 'category_style.dart';
import 'data_controller.dart';

/// The categories with their settings.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key, required this.data});

  final DataController data;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: data,
    builder: (context, _) {
      final config = data.config;
      if (config == null) return const SizedBox.shrink();
      return ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final c in config.categories)
            ListTile(
              leading: CategoryDot(c, size: 20),
              title: Text(c.name),
              subtitle: Text(describeCategory(c)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openCategoryEditor(context, data: data, editing: c),
            ),
        ],
      );
    },
  );
}

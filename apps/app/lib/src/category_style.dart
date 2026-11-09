import 'package:flutter/material.dart';
import 'package:sasa_core/sasa_core.dart';

import 'theme/pwani.dart';
import 'theme/shapes.dart';

/// Colour of [category]; the theme's outline for unclassified items.
Color categoryColor(Category? category, ColorScheme scheme) {
  final argb = category == null ? null : parseHexColor(category.color);
  return argb == null ? scheme.outline : Color(argb);
}

/// A small arch in a category's colour (outlined when unclassified).
class CategoryDot extends StatelessWidget {
  const CategoryDot(this.category, {super.key, this.size = 12});

  final Category? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ArchMark(
      color: category == null
          ? Colors.transparent
          : categoryColor(category, scheme),
      border: category == null ? scheme.outline : scheme.outlineVariant,
      width: size,
      height: size * 1.2,
    );
  }
}

/// A pill with the category name on its colour, like "Teaching".
class CategoryTag extends StatelessWidget {
  const CategoryTag(this.category, {super.key});

  final Category? category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = category == null
        ? scheme.surfaceContainerHigh
        : categoryColor(category, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Text(
        category?.name ?? 'Unclassified',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: category == null ? scheme.onSurfaceVariant : textOn(bg),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Shows the categories of [config] in a bottom sheet; returns the chosen id.
Future<String?> pickCategory(
  BuildContext context,
  AppConfig config, {
  required String title,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(title, style: Theme.of(sheet).textTheme.titleMedium),
        ),
        for (final c in config.categories)
          ListTile(
            leading: CategoryDot(c, size: 16),
            title: Text(c.name),
            onTap: () => Navigator.of(sheet).pop(c.id),
          ),
      ],
    ),
  ),
);

/// Shows [message] in a snack bar.
void showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

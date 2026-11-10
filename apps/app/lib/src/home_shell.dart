import 'package:flutter/material.dart';

import 'categories_screen.dart';
import 'category_editor.dart';
import 'data_controller.dart';
import 'inbox_screen.dart';
import 'rule_editor.dart';
import 'rules_screen.dart';
import 'today_controller.dart';
import 'today_screen.dart';

/// The main screens of the app.
enum HomeTab { today, inbox, categories, rules }

/// Navigation between [HomeTab]s (a bottom bar on phones, a rail on wide
/// windows), with folder problems shown above every tab.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.data,
    required this.today,
    required this.onOpenSettings,
    required this.onOpenSetup,
    this.showToday,
  });

  final DataController data;
  final TodayController today;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenSetup;

  /// Notifies when Today must be shown (the brief notification was tapped).
  final Listenable? showToday;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  HomeTab _tab = HomeTab.today;

  void _go(HomeTab tab) => setState(() => _tab = tab);

  void _showToday() => _go(HomeTab.today);

  @override
  void initState() {
    super.initState();
    widget.showToday?.addListener(_showToday);
  }

  @override
  void didUpdateWidget(HomeShell old) {
    super.didUpdateWidget(old);
    if (old.showToday != widget.showToday) {
      old.showToday?.removeListener(_showToday);
      widget.showToday?.addListener(_showToday);
    }
  }

  @override
  void dispose() {
    widget.showToday?.removeListener(_showToday);
    super.dispose();
  }

  static const _titles = {
    HomeTab.today: 'Today',
    HomeTab.inbox: 'Unclassified',
    HomeTab.categories: 'Categories',
    HomeTab.rules: 'Rules',
  };

  List<_Destination> _destinations(int inboxCount) => [
    const _Destination(Icons.today_outlined, Icons.today, 'Today'),
    _Destination(Icons.inbox_outlined, Icons.inbox, 'Inbox', badge: inboxCount),
    const _Destination(Icons.palette_outlined, Icons.palette, 'Categories'),
    const _Destination(Icons.rule_outlined, Icons.rule, 'Rules'),
  ];

  Widget _body() => switch (_tab) {
    HomeTab.today => TodayScreen(
      controller: widget.today,
      onOpenInbox: () => _go(HomeTab.inbox),
    ),
    HomeTab.inbox => InboxScreen(today: widget.today, data: widget.data),
    HomeTab.categories => CategoriesScreen(data: widget.data),
    HomeTab.rules => RulesScreen(data: widget.data, today: widget.today),
  };

  Widget? _fab(BuildContext context) {
    final hasConfig = widget.data.config != null;
    return switch (_tab) {
      HomeTab.today => const ImFreeButton(),
      HomeTab.categories when hasConfig => FloatingActionButton.extended(
        onPressed: () => openCategoryEditor(context, data: widget.data),
        icon: const Icon(Icons.add),
        label: const Text('Category'),
      ),
      HomeTab.rules when hasConfig => FloatingActionButton.extended(
        onPressed: () =>
            openRuleEditor(context, data: widget.data, today: widget.today),
        icon: const Icon(Icons.add),
        label: const Text('Rule'),
      ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.data, widget.today]),
    builder: (context, _) {
      final destinations = _destinations(widget.today.inbox?.itemCount ?? 0);
      final wide = MediaQuery.sizeOf(context).width >= 720;
      final content = Column(
        children: [
          FolderBanners(data: widget.data, onOpenSetup: widget.onOpenSetup),
          Expanded(child: _body()),
        ],
      );
      return Scaffold(
        appBar: AppBar(
          title: Text(_titles[_tab]!),
          actions: [
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: widget.today.loading
                  ? null
                  : () async {
                      await widget.data.reload();
                      await widget.today.refresh();
                    },
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: widget.onOpenSettings,
            ),
          ],
        ),
        floatingActionButton: _fab(context),
        body: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _tab.index,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (i) => _go(HomeTab.values[i]),
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: d.icon(selected: false),
                          selectedIcon: d.icon(selected: true),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              )
            : content,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _tab.index,
                onDestinationSelected: (i) => _go(HomeTab.values[i]),
                destinations: [
                  for (final d in destinations)
                    NavigationDestination(
                      icon: d.icon(selected: false),
                      selectedIcon: d.icon(selected: true),
                      label: d.label,
                    ),
                ],
              ),
      );
    },
  );
}

final class _Destination {
  const _Destination(this.outlined, this.filled, this.label, {this.badge = 0});

  final IconData outlined;
  final IconData filled;
  final String label;
  final int badge;

  Widget icon({required bool selected}) {
    final i = Icon(selected ? filled : outlined);
    return badge > 0 ? Badge.count(count: badge, child: i) : i;
  }
}

/// Problems with the synced folder that need the user.
class FolderBanners extends StatelessWidget {
  const FolderBanners({super.key, required this.data, this.onOpenSetup});

  final DataController data;
  final VoidCallback? onOpenSetup;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (data.accessLost)
        _Banner(
          icon: Icons.folder_off_outlined,
          text:
              'Sasa can no longer open "${data.location?.name ?? 'the '
                      'synced folder'}". Choose it again.',
          action: 'Choose folder',
          onAction: onOpenSetup,
        ),
      if (data.conflicts.isNotEmpty)
        _Banner(
          icon: Icons.call_split,
          text:
              'Your sync app made ${data.conflicts.length} conflicting '
              'cop${data.conflicts.length == 1 ? 'y' : 'ies'} of '
              'config.json. Keep the most recently changed version?',
          action: 'Keep newest',
          onAction: data.busy ? null : data.keepNewestConfig,
        ),
      if (data.error != null)
        _Banner(icon: Icons.error_outline, text: data.error!),
    ],
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    ),
  );
}

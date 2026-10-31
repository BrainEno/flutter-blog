import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Root scaffold hosting four independent navigator stacks. The native tab
/// bar keeps the app's existing navigation while using the no-wave palette.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _icons = [
    Icons.home_outlined,
    Icons.search_outlined,
    Icons.bookmark_border,
    Icons.person_outline,
  ];
  static const _selectedIcons = [
    Icons.home,
    Icons.search,
    Icons.bookmark,
    Icons.person,
  ];

  List<String> _tabLabels(AppLocalizations l10n) => [
    l10n.tabHome,
    l10n.tabSearch,
    l10n.tabSaved,
    l10n.tabProfile,
  ];

  @override
  Widget build(BuildContext context) {
    final labels = _tabLabels(context.l10n);
    return Scaffold(
      body: SafeArea(
        top: false,
        child: _TabFadeTransition(
          index: widget.shell.currentIndex,
          child: widget.shell,
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: widget.shell.currentIndex,
          onDestinationSelected: (index) {
            // Re-tapping the active destination preserves its existing stack.
            if (index != widget.shell.currentIndex) {
              widget.shell.goBranch(index);
            }
          },
          destinations: [
            for (var i = 0; i < _icons.length; i++)
              NavigationDestination(
                icon: Icon(_icons[i]),
                selectedIcon: Icon(_selectedIcons[i]),
                label: labels[i],
              ),
          ],
        ),
      ),
    );
  }
}

class _TabFadeTransition extends StatefulWidget {
  const _TabFadeTransition({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_TabFadeTransition> createState() => _TabFadeTransitionState();
}

class _TabFadeTransitionState extends State<_TabFadeTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _TabFadeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _controller,
        curve: Curves.fastOutSlowIn,
      ),
      child: widget.child,
    );
  }
}

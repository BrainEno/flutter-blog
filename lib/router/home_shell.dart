import 'package:belog/core/theme/app_pallete.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Root scaffold hosting the four-tab [StatefulNavigationShell].
///
/// Each branch owns its navigator, so switching tabs preserves the stack the
/// user built in every tab. The tab-switch fade is driven from
/// [_TabFadeTransitionState.didUpdateWidget] — a lifecycle callback — instead
/// of from [build], which stays free of animation side effects.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const List<(String, IconData)> _tabs = [
    ('首页', Icons.home),
    ('搜索', Icons.search),
    ('收藏', Icons.bookmark),
    ('个人中心', Icons.person),
  ];

  List<NavigationDestination> _destinations(BuildContext context) {
    final iconColor = Theme.of(context).brightness == Brightness.light
        ? AppPallete.greyColorDark
        : AppPallete.whiteColor;
    return [
      for (final (label, icon) in _tabs)
        NavigationDestination(
          icon: Icon(icon, color: iconColor),
          label: label,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: false,
        child: _TabFadeTransition(
          index: widget.shell.currentIndex,
          child: widget.shell,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: (index) {
          // Re-tapping the selected tab keeps its current stack, matching the
          // previous behaviour.
          if (index != widget.shell.currentIndex) {
            widget.shell.goBranch(index);
          }
        },
        destinations: _destinations(context),
      ),
    );
  }
}

/// Fades the newly selected tab in with the same 300ms fastOutSlowIn curve
/// the previous shell used. Controllers are only touched from lifecycle
/// callbacks, never from [build].
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
    if (widget.index != oldWidget.index) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _controller,
        curve: Curves.fastOutSlowIn,
      ),
      child: widget.child,
    );
  }
}

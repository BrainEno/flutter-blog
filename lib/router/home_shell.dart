import 'dart:async';

import 'package:belog/core/design/components/no_wave_fade_transition.dart';
import 'package:belog/core/design/components/no_wave_return_to_top.dart';
import 'package:belog/core/design/components/no_wave_tab_bar.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:belog/router/read_aloud_route_observers.dart';
import 'package:get_it/get_it.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Root scaffold hosting four independent navigator stacks under the app's
/// own [NoWaveTabBar].
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with RouteAware {
  late int _lastTab;

  /// Takes the list on screen back to its top when its tab is tapped again.
  final GlobalKey<NoWaveReturnToTopState> _returnToTop = GlobalKey();

  @override
  void initState() {
    super.initState();
    _lastTab = widget.shell.currentIndex;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      rootReadAloudRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastTab != widget.shell.currentIndex) {
      _lastTab = widget.shell.currentIndex;
      _stopAfterNavigation();
    }
  }

  @override
  void didPushNext() => _stopAfterNavigation();

  void _stopAfterNavigation() {
    if (!GetIt.instance.isRegistered<SpeechCoordinator>()) return;
    final coordinator = GetIt.instance<SpeechCoordinator>();
    final owner = coordinator.owner;
    if (owner == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(coordinator.stopIfCurrent(owner).catchError((Object _) {}));
    });
  }

  @override
  void dispose() {
    rootReadAloudRouteObserver.unsubscribe(this);
    super.dispose();
  }

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
        child: NoWaveFadeTransition(
          index: widget.shell.currentIndex,
          child: NoWaveReturnToTop(
            key: _returnToTop,
            section: widget.shell.currentIndex,
            child: widget.shell,
          ),
        ),
      ),
      // The bar hangs from a hairline and marks the chosen destination with
      // the same ink rule as the in-page tabs, drawn across when it changes.
      bottomNavigationBar: NoWaveTabBar(
        selectedIndex: widget.shell.currentIndex,
        onSelected: (index) {
          // Re-tapping the active destination preserves its existing
          // stack and takes the list on screen back to its top.
          if (index != widget.shell.currentIndex) {
            _stopAfterNavigation();
            widget.shell.goBranch(index);
          } else {
            _returnToTop.currentState?.toTop();
          }
        },
        destinations: [
          for (var i = 0; i < _icons.length; i++)
            NoWaveTabDestination(
              icon: _icons[i],
              selectedIcon: _selectedIcons[i],
              label: labels[i],
            ),
        ],
      ),
    );
  }
}

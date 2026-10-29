import 'package:flutter/material.dart';

/// Root [ScaffoldMessengerState] key, attached to the app's
/// [MaterialApp.router]. It lets code without a [BuildContext] - such as
/// the auth deep-link handler running above the widget tree - show a
/// snackbar above the current route.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Shows a snackbar above any route via [rootScaffoldMessengerKey].
///
/// Prefer `showSnackBar(context, ...)` inside pages; use this only for
/// app-level feedback like auth deep-link results.
void showGlobalSnackBar(String message) {
  rootScaffoldMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

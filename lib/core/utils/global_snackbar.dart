import 'package:flutter/material.dart';

/// Root messenger key attached to [MaterialApp.router]. Page-level feedback
/// uses `showSnackBar(context, ...)` and the enclosing messenger as usual.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

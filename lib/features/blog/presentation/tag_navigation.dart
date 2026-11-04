import 'package:belog/router/shell_branch_location.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Opens the article list for [tag] on the current tab's stack.
///
/// The tag travels as the **name** an article stores, because that is what the
/// client has: the server slug is opaque and has to be resolved. The name is
/// also handed over as `extra` so the page does not have to undo the URL
/// encoding for in-app taps; deep links still work from the path.
void openTagArticles(BuildContext context, String tag) {
  final name = tag.trim();
  if (name.isEmpty) return;
  // Tag routes exist in every tab branch, so the tap has to stay inside the
  // one the reader is in - otherwise it would jump to the feed's stack.
  context.push(
    shellBranchLocation(
      GoRouterState.of(context).uri,
      '/tag/${Uri.encodeComponent(name)}',
    ),
    extra: name,
  );
}

/// The tag a `/tag/:name` route points at.
///
/// [rawPathValue] is whatever the router extracted; it may already be decoded.
/// Tag names are limited to letters, marks, digits, `_` and `-`, so decoding a
/// decoded value is a no-op and cannot corrupt it.
String tagFromRoute(String rawPathValue, Object? extra) {
  if (extra is String && extra.trim().isNotEmpty) return extra.trim();
  return Uri.decodeComponent(rawPathValue).trim();
}

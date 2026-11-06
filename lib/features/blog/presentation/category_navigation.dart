import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/router/shell_branch_location.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Opens the article list for [category] on the current tab's stack.
///
/// The slug is the address and travels in the path; the [CategoryRef] is also
/// handed over as `extra` so the page can show the name it already has instead
/// of waiting for a lookup. Deep links without `extra` resolve the slug.
void openCategoryArticles(BuildContext context, CategoryRef category) {
  final slug = category.slug.trim();
  if (slug.isEmpty) return;
  context.push(
    shellBranchLocation(
      GoRouterState.of(context).uri,
      '/category/${Uri.encodeComponent(slug)}',
    ),
    extra: category,
  );
}

/// Opens the catalog on the current tab's stack.
void openCategories(BuildContext context) {
  context.push(
    shellBranchLocation(GoRouterState.of(context).uri, '/categories'),
  );
}

/// The slug a `/category/:slug` route points at.
///
/// [rawPathValue] is whatever the router extracted; it may already be decoded.
/// Slugs are ASCII, so decoding a decoded value is a no-op.
String categorySlugFromRoute(String rawPathValue) =>
    Uri.decodeComponent(rawPathValue).trim();

/// The category a route carried, when the tap passed one through `extra`.
CategoryRef? categoryFromExtra(Object? extra) =>
    extra is CategoryRef && extra.slug.trim().isNotEmpty ? extra : null;

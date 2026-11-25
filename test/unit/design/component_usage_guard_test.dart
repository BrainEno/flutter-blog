import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_files.dart';

/// Raw Material buttons and dialogs may not grow in `lib/features`.
///
/// `docs/design-system.md` says a business action is a `NoWaveButton`, and
/// that `ElevatedButton`/`FilledButton` exist only as the theme's fallback.
/// That is the one design-system rule with no enforcement behind it: the
/// numeric gate (`no_magic_numbers_test.dart`) proves every spacing literal is
/// gone, yet nothing stops a page from writing `TextButton(onPressed: ...)`
/// again, and the theme makes such a button look correct in a diff. What
/// differs is not colour - it is the contract `NoWaveButton` carries and a
/// hand-rolled button cannot: `isLoading` keeps the label in the layout and
/// reports the press as unavailable, `onPressed: null` keeps the 48pt target
/// instead of reflowing a row, and `semanticLabel` disambiguates a row of
/// identically named actions.
///
/// So this is a freeze, not a migration. The map below is the exact tree state
/// when the gate landed: 75 call sites in 28 files, counted the same way this
/// test counts them. Migrate one and you delete its line in the same commit;
/// a new file, or one more `TextButton` in a listed file, fails `flutter test`
/// with the replacement named. Lowering a number is always welcome - raising
/// one is the thing this gate exists to make expensive.
///
/// Deliberately outside the scan:
///
/// - `IconButton`, because there is no `NoWave` equivalent to reach for. The
///   shared button requires a visible label, and a bare icon plus a tooltip is
///   the documented answer for icon-only affordances, so 42 existing uses are
///   conformant rather than tolerated.
/// - `InputChip`/`ChoiceChip`, which are selection inputs. `NoWaveBadge` covers
///   the read-only status label, and `no_magic_numbers_test.dart` already
///   guards the selected/unselected treatment those pickers must follow.
/// - `SnackBar(`, because features already reach it only through
///   `showSnackBar`; that helper is guarded by `ui_consistency_guard_test.dart`
///   and a second scan would only re-count `showSnackBar(` call sites.
void main() {
  // Paths are relative to `lib/`, which keeps the table readable and matches
  // `no_magic_numbers_test.dart`.
  const budget = <String, int>{
    'features/auth/presentation/pages/email_verification_page.dart': 2,
    'features/auth/presentation/widgets/auth_frame.dart': 2,
    'features/blog/presentation/comments/comment_edit_dialog.dart': 8,
    'features/blog/presentation/comments/comment_tile.dart': 2,
    'features/blog/presentation/editor/cover_crop_page.dart': 2,
    'features/blog/presentation/editor/editor_category_selector.dart': 1,
    'features/blog/presentation/editor/editor_cover_field.dart': 4,
    'features/blog/presentation/editor/editor_form.dart': 1,
    'features/blog/presentation/editor/editor_format_toolbar.dart': 3,
    'features/blog/presentation/editor/notion_export_sheet.dart': 2,
    'features/blog/presentation/editor/notion_import_report_view.dart': 3,
    'features/blog/presentation/editor/notion_import_sheet.dart': 7,
    'features/blog/presentation/pages/publish_queue_page.dart': 4,
    'features/blog/presentation/pages/recycle_bin_page.dart': 1,
    'features/blog/presentation/pages/search_blog_page.dart': 3,
    'features/blog/presentation/read_aloud/read_aloud_controls.dart': 2,
    'features/blog/presentation/read_aloud/read_aloud_dock.dart': 2,
    'features/blog/presentation/search/recent_search_list.dart': 2,
    'features/blog/presentation/widgets/article_category_label.dart': 2,
    'features/blog/presentation/widgets/article_tag_label.dart': 2,
    'features/blog/presentation/widgets/draft_recovery_dialog.dart': 1,
    'features/messages/presentation/pages/message_participants_sheet.dart': 9,
    'features/messages/presentation/pages/message_thread_page.dart': 2,
    'features/user/presentation/pages/about_page.dart': 1,
    'features/user/presentation/pages/account_sessions_page.dart': 1,
    'features/user/presentation/pages/author_page.dart': 2,
    'features/user/presentation/pages/edit_user_info_page.dart': 1,
    'features/user/presentation/widgets/user_media_picker_sheet.dart': 3,
  };

  /// Components with a `NoWave` counterpart, so zero is the only accepted
  /// count for them in `lib/features`.
  const neverAllowed = ['ElevatedButton'];

  /// Everything the scan counts, `neverAllowed` included.
  const scanned = [
    'ElevatedButton',
    'FilledButton',
    'TextButton',
    'OutlinedButton',
    'AlertDialog',
  ];

  final counted = <String, Map<String, int>>{};
  final totals = <String, int>{for (final name in scanned) name: 0};
  for (final file in dartFilesUnder('lib/features')) {
    final path = file.path
        .replaceAll(Platform.pathSeparator, '/')
        .replaceFirst('lib/', '');
    final found = _usageByComponent(file.readAsStringSync(), scanned);
    if (found.isEmpty) continue;
    counted[path] = found;
    for (final entry in found.entries) {
      totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
    }
  }

  test('no feature file gained a raw Material action component', () {
    final grown = <String>[];
    for (final entry in counted.entries) {
      final allowed = budget[entry.key] ?? 0;
      final total = entry.value.values.fold<int>(0, (sum, n) => sum + n);
      if (total > allowed) {
        grown.add('${entry.key}: $total (budget $allowed)');
      }
    }
    expect(
      grown,
      isEmpty,
      reason:
          'a business action is a NoWaveButton: primary / secondary / quiet / '
          'destructive via NoWaveButtonVariant, with `icon:` for the leading '
          'glyph and `isLoading` for the pending state; a confirmation is '
          'showNoWaveConfirmDialog. These files exceeded their frozen budget, '
          'so either migrate the call site or explain the exception in the '
          'pull request - do not raise a number here.\n'
          '${grown.join('\n')}',
    );
  });

  test('the budget is the tree, so migrations are recorded', () {
    final stale = <String>[];
    for (final entry in budget.entries) {
      final actual = counted[entry.key];
      final total = actual == null
          ? 0
          : actual.values.fold<int>(0, (s, n) => s + n);
      if (total != entry.value) {
        stale.add('${entry.key}: budget ${entry.value}, now $total');
      }
    }
    for (final path in counted.keys) {
      if (!budget.containsKey(path)) stale.add('$path: not in the budget');
    }
    expect(
      stale,
      isEmpty,
      reason:
          'this table is a freeze, so it has to say what is actually there. '
          'After migrating a call site, delete its file from the budget or '
          'lower the number in the same commit; never raise one.\n'
          '${stale.join('\n')}',
    );
  });

  test('ElevatedButton stays unused in features', () {
    final hits = <String>[];
    for (final name in neverAllowed) {
      if (totals[name] == 0) continue;
      for (final entry in counted.entries) {
        final n = entry.value[name];
        if (n != null && n > 0) hits.add('${entry.key}: $n $name()');
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          'ElevatedButton is theme fallback only (docs/design-system.md); a '
          'filled business action is NoWaveButton with the default primary '
          'variant. Found:\n${hits.join('\n')}',
    );
  });

  test('the scan still finds what it claims to guard', () {
    // A typo in a pattern would turn this whole gate off silently: the counts
    // would go to zero, the budget check would pass on an empty tree, and the
    // suite would stay green. So every scanned component must be doing real
    // work today, except the ones fenced at zero on purpose.
    final dead = <String>[];
    for (final name in scanned) {
      final found = totals[name] ?? 0;
      final fenced = neverAllowed.contains(name);
      if (fenced && found != 0) {
        dead.add('$name: fenced at zero, but found $found');
      }
      if (!fenced && found == 0) {
        dead.add('$name: 0 hits, so the pattern matches nothing');
      }
    }
    expect(
      dead,
      isEmpty,
      reason:
          'the guard only works if its patterns still match the tree; a '
          'component with no hits is a typo, not a clean codebase.\n'
          '${dead.join('\n')}',
    );
  });

  test('the budget does not point at deleted files', () {
    final missing = budget.keys.where(
      (path) => !File('lib/$path').existsSync(),
    );
    expect(missing, isEmpty, reason: 'Drop these from the budget: $missing');
  });
}

/// Occurrences of each [scanned] component in one file's [source].
///
/// Textual, on purpose, like the other source-scan guards: it reads a line the
/// way a reviewer does. Requiring a non-word character before the name keeps
/// `showSnackBar(` out of a `SnackBar(` scan and `_StatusChip(` out of a chip
/// scan without a second whitelist, and `(?:\.\w+)?` still counts the named
/// constructors a call site really writes (`TextButton.icon(`). Comment lines
/// are dropped so a doc snippet showing the forbidden shape is not a use of it.
///
/// One blind spot to know before extending [scanned]: the pattern needs `(` or
/// `.name` right after the identifier, so an explicit type argument
/// (`Foo<T>(...)`) would not match. Every scanned component is non-generic
/// today; add the type-argument case in the same commit as any generic one.
Map<String, int> _usageByComponent(String source, List<String> scanned) {
  final patterns = <String, RegExp>{};
  for (final name in scanned) {
    patterns[name] = RegExp(r'(?:^|[^\w$])' + name + r'(?:\.\w+)?\s*\(');
  }
  final result = <String, int>{};
  for (final line in source.split('\n')) {
    final text = line.trimLeft();
    if (text.startsWith('//') || text.startsWith('*')) continue;
    for (final entry in patterns.entries) {
      final count = entry.value.allMatches(line).length;
      if (count > 0) result[entry.key] = (result[entry.key] ?? 0) + count;
    }
  }
  return result;
}

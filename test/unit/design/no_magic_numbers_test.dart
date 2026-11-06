import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Numbers a screen should have taken from `NoWaveSpacing` / `NoWaveSizes`.
///
/// The design system only holds if pages stop re-deciding their own gaps. The
/// token file is easy to write and easy to ignore, so this test turns the rule
/// into a gate: spacing literals may only go away, never appear. It scans for
/// the shapes screens actually write - `SizedBox(height: 8)`,
/// `EdgeInsets.all(16)`, `Wrap(spacing: 12)`, a hard-coded `BorderSide` width -
/// and ignores `0`, which is a reset rather than a measurement.
///
/// The budget below is the state of the tree when the gate landed. Removing
/// literals is welcome and needs no bookkeeping; adding one in a file that is
/// already at its budget fails, and the fix is to use a token, not to raise the
/// number. A genuine exception (an optical offset, a one-off glyph size) is
/// allowed on the line itself:
///
/// ```dart
/// const SizedBox(height: 2) // design-token-ok: optical baseline nudge
/// ```
///
/// Regenerate the budget with the counts this test prints when it fails; do
/// not hand-edit a number upwards without the `design-token-ok` marker on the
/// line that needs it.
void main() {
  /// Files whose whole job is the design system must not contain any.
  const strict = ['core/design/', 'core/common/widgets/', 'core/theme/'];

  /// The frozen state of everything else.
  const budget = <String, int>{
    'core/startup/startup_failure_app.dart': 5,
    'features/auth/presentation/pages/change_email_page.dart': 9,
    'features/auth/presentation/pages/change_password_page.dart': 8,
    'features/auth/presentation/pages/email_verification_page.dart': 14,
    'features/auth/presentation/pages/login_page.dart': 10,
    'features/auth/presentation/pages/signup_page.dart': 9,
    'features/blog/presentation/comments/comment_composer.dart': 3,
    'features/blog/presentation/comments/comment_login_prompt.dart': 3,
    'features/blog/presentation/comments/comment_tile.dart': 8,
    'features/blog/presentation/editor/editor_app_bar.dart': 2,
    'features/blog/presentation/editor/editor_body_field.dart': 2,
    'features/blog/presentation/editor/editor_cover_field.dart': 4,
    'features/blog/presentation/editor/editor_form.dart': 8,
    'features/blog/presentation/editor/editor_tag_selector.dart': 4,
    'features/blog/presentation/markdown/markdown_renderer.dart': 21,
    'features/blog/presentation/pages/blog_editor_page.dart': 1,
    'features/blog/presentation/pages/blog_page.dart': 11,
    'features/blog/presentation/pages/blog_viewer_page.dart': 1,
    'features/blog/presentation/pages/categories_page.dart': 7,
    'features/blog/presentation/pages/category_articles_page.dart': 5,
    'features/blog/presentation/pages/publish_queue_page.dart': 16,
    'features/blog/presentation/pages/recycle_bin_page.dart': 3,
    'features/blog/presentation/pages/saved_blogs_page.dart': 1,
    'features/blog/presentation/pages/search_blog_page.dart': 8,
    'features/blog/presentation/pages/tag_articles_page.dart': 5,
    'features/blog/presentation/pages/user_blogs_page.dart': 1,
    'features/blog/presentation/read_aloud/read_aloud_controls.dart': 6,
    'features/blog/presentation/viewer/viewer_article_body.dart': 5,
    'features/blog/presentation/widgets/article_reader_header.dart': 11,
    'features/blog/presentation/widgets/article_tag_label.dart': 2,
    'features/blog/presentation/widgets/blog_card.dart': 11,
    'features/blog/presentation/widgets/comments_section.dart': 6,
    'features/blog/presentation/widgets/editor_field.dart': 6,
    'features/blog/presentation/widgets/related_articles_section.dart': 1,
    'features/messages/presentation/pages/message_inbox_page.dart': 22,
    'features/messages/presentation/pages/message_thread_page.dart': 25,
    'features/notifications/presentation/pages/notification_inbox_page.dart':
        21,
    'features/user/presentation/pages/about_page.dart': 9,
    'features/user/presentation/pages/account_sessions_page.dart': 11,
    'features/user/presentation/pages/author_page.dart': 17,
    'features/user/presentation/pages/author_relationships_page.dart': 9,
    'features/user/presentation/pages/author_search_page.dart': 10,
    'features/user/presentation/pages/edit_user_info_page.dart': 8,
    'features/user/presentation/pages/profile_page.dart': 8,
    'features/user/presentation/pages/reading_history_page.dart': 6,
    'router/app_router.dart': 2,
  };

  // Paths are relative to `lib/`, which keeps the budget readable.
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path.replaceAll(Platform.pathSeparator, '/'))
      .map((path) => path.replaceFirst('lib/', ''))
      .where((path) => path.endsWith('.dart'))
      .toList()
    ..sort();

  test('the design system itself has no spacing literals', () {
    final offenders = <String>[];
    for (final path in files) {
      if (!strict.any(path.startsWith)) continue;
      final count = _spacingLiterals(File('lib/$path').readAsStringSync());
      if (count > 0) offenders.add('$path ($count)');
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Design-system files must read every number from design_tokens.dart; '
          'found spacing literals in: ${offenders.join(', ')}',
    );
  });

  test('no file gained spacing literals', () {
    final grown = <String>[];
    final current = <String, int>{};
    for (final path in files) {
      final count = _spacingLiterals(File('lib/$path').readAsStringSync());
      if (count == 0) continue;
      current[path] = count;
      final allowed = budget[path] ?? 0;
      if (count > allowed) grown.add('$path: $count (budget $allowed)');
    }
    expect(
      grown,
      isEmpty,
      reason:
          'Spacing literals may only be replaced by tokens, never added. '
          'These files grew: ${grown.join(', ')}',
    );
  });

  test('the remaining literals only shrink', () {
    var total = 0;
    for (final path in files) {
      total += _spacingLiterals(File('lib/$path').readAsStringSync());
    }
    // Lower this when a page is migrated; never raise it.
    const ceiling = 365;
    expect(
      total,
      lessThanOrEqualTo(ceiling),
      reason:
          'The tree has $total spacing literals, more than the $ceiling it had '
          'when the gate landed. Use NoWaveSpacing or mark the line with '
          '`design-token-ok`.',
    );
  });

  test('the budget does not point at deleted files', () {
    final missing = budget.keys.where(
      (path) => !File('lib/$path').existsSync(),
    );
    expect(missing, isEmpty, reason: 'Drop these from the budget: $missing');
  });
}

/// Counts non-zero numbers used as spacing, insets, gaps or border widths.
///
/// Deliberately textual: it reads the source the way a reviewer does, so a
/// widget that hides its padding behind a private constant still counts.
int _spacingLiterals(String source) {
  final lines = source
      .split('\n')
      .where(
        (line) =>
            !line.trimLeft().startsWith('//') &&
            !line.contains('design-token-ok'),
      )
      .join('\n');
  var total = 0;
  for (final pattern in _patterns) {
    for (final match in pattern.allMatches(lines)) {
      for (final number in _number.allMatches(match.group(1)!)) {
        if (double.parse(number.group(0)!) != 0) total++;
      }
    }
  }
  return total;
}

final _number = RegExp(r'[0-9]+(?:\.[0-9]+)?');

final _patterns = <RegExp>[
  RegExp(r'SizedBox\s*\(\s*(?:width|height):\s*([0-9]+(?:\.[0-9]+)?)'),
  RegExp(r'SizedBox\.square\s*\(\s*size:\s*([0-9]+(?:\.[0-9]+)?)'),
  RegExp(
    r'EdgeInsets(?:Geometry)?\.(?:all|only|symmetric|fromLTRB)\(([^)]*)\)',
  ),
  RegExp(
    r'\b(?:gap|spacing|runSpacing|crossAxisSpacing|mainAxisSpacing|space):'
    r'\s*([0-9]+(?:\.[0-9]+)?)',
  ),
  RegExp(r'BorderSide\([^)]*\bwidth:\s*([0-9]+(?:\.[0-9]+)?)'),
];

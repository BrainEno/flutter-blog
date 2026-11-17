import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the public editor route is a small composition root', () {
    final page = File(
      'lib/features/blog/presentation/pages/blog_editor_page.dart',
    ).readAsStringSync();
    expect('\n'.allMatches(page).length, lessThanOrEqualTo(400));
    expect(page, contains('EditorSessionCoordinator('));
    expect(page, contains('EditorSessionConfig('));
    expect(page, isNot(contains('Timer(')));
    expect(page, isNot(contains('showModalBottomSheet')));
  });

  test('editor view delegates effects and does not own a session', () {
    final screen = File(
      'lib/features/blog/presentation/editor/editor_screen.dart',
    ).readAsStringSync();
    expect(screen, contains('class EditorScreen extends StatelessWidget'));
    expect(screen, contains('listener: onUploadState'));
    expect(screen, isNot(contains('GetIt')));
    expect(screen, isNot(contains('EditorSessionCoordinator')));
    expect(screen, isNot(contains('BlogDraftStore')));
    expect(screen, isNot(contains('PublishQueueStore')));
  });
}

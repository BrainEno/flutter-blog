import 'package:belog/router/shell_branch_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('author and viewer paths stay in the current shell branch', () {
    final sources = <String, String>{
      '/': '',
      '/view/a': '',
      '/search/author/writer?ref=reader': '/search',
      '/saved/view/a': '/saved',
      '/profile/my-articles/recycle-bin': '/profile',
      '/searching': '',
    };
    for (final entry in sources.entries) {
      expect(
        shellBranchLocation(Uri.parse(entry.key), '/author/writer'),
        '${entry.value}/author/writer',
      );
      expect(
        shellBranchLocation(Uri.parse(entry.key), '/view/article'),
        '${entry.value}/view/article',
      );
    }
  });
}

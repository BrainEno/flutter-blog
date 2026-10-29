import 'dart:io';

import 'package:isar/isar.dart';
import 'package:legacy_isar_fixture/blog.dart';
import 'package:legacy_isar_fixture/blog_draft.dart';
import 'package:legacy_isar_fixture/theme_preference.dart';

/// Writes an old-format Isar database using the abandoned `isar 3.1.0+1`
/// package and the original generator's schemas, so the committed fixture is
/// exactly what a pre-migration app version would have written.
///
/// Usage: dart run bin/create.dart OUTPUT_DEFAULT_ISAR
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run bin/create.dart OUTPUT_DEFAULT_ISAR');
    exitCode = 2;
    return;
  }
  final output = File(args.single);
  await output.parent.create(recursive: true);
  final directory = await Directory.systemTemp.createTemp('legacy-fixture-');
  try {
    await Isar.initializeIsarCore(download: true);
    final isar = await Isar.open(
      [ThemePreferenceSchema, BlogSchema, BlogDraftSchema],
      directory: directory.path,
      inspector: false,
    );
    await isar.writeTxn(() async {
      await isar.themePreferences.put(
        ThemePreference(themeMode: ThemeMode.light)..id = 2,
      );
      await isar.themePreferences.put(
        ThemePreference(themeMode: ThemeMode.dark)..id = 9,
      );
      await isar.blogDrafts.put(
        BlogDraft(
          blogId: 'a',
          title: 'keep',
          content: 'unsent',
          tags: ['x'],
          updatedAt: DateTime.utc(2024),
        )..id = 7,
      );
      await isar.blogDrafts.put(
        BlogDraft(
          blogId: null,
          title: 'new article',
          content: 'scratch pad',
          tags: [],
          updatedAt: DateTime.utc(2024, 5),
        )..id = 8,
      );
      await isar.blogs.put(
        Blog(
          iid: Isar.autoIncrement,
          id: '1',
          title: 'legacy',
          content: 'body',
          posterId: 'author',
          imageUrl: 'cover',
          tags: ['one'],
          updatedAt: DateTime.utc(2025),
          posterName: 'Alice',
          posterAvatar: 'avatar',
        ),
      );
    });
    await isar.close();
    await File('${directory.path}/default.isar').copy(output.path);
    print('Wrote ${output.path}');
  } finally {
    await directory.delete(recursive: true);
  }
}

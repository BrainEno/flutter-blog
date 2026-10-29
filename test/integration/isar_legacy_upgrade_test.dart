import 'dart:io';

import 'package:belog/core/theme/theme_preference.dart';
import 'package:belog/core/theme/theme_preference_store.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

void main() {
  final directory = Platform.environment['ISAR_FIXTURE_DIR'];

  test(
    'upgrade a real legacy database and retain its data',
    () async {
      await Isar.initializeIsarCore(download: true);
      final isar = await Isar.open(
        [ThemePreferenceSchema, BlogSchema, BlogDraftSchema],
        directory: directory!,
        inspector: false,
      );
      try {
        final store = IsarThemePreferenceStore(isar);
        expect(await store.load(), ThemeMode.dark);
        final draft = await isar.blogDrafts.get(24);
        expect(draft?.blogId, 'article-1');
        expect(draft?.title, 'legacy draft');
        expect(draft?.content, 'unsent content');
        expect(draft?.tags, ['legacy']);
        final blog = await isar.blogs.get(31);
        expect(blog?.id, 'cached-1');
        expect(blog?.content, 'cached body');
        expect(blog?.posterName, 'Author');
        expect(blog?.posterAvatar, 'https://example.invalid/avatar');
        await store.save(ThemeMode.light);
        await isar.writeTxn(() async {
          await isar.blogDrafts.put(
            BlogDraft(
              blogId: draft!.blogId,
              title: 'community draft',
              content: draft.content,
              tags: draft.tags,
              updatedAt: draft.updatedAt,
            )..id = draft.id,
          );
        });
      } finally {
        await isar.close();
      }
    },
    skip: directory == null ? 'Requires the CI legacy database fixture' : false,
  );
}

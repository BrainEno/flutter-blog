import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../../support/structured_article_fixtures.dart';

final backend = Uri.parse('https://api.example.invalid/v1');
final instant = DateTime.utc(2026, 10, 29, 1, 2, 3, 4, 5);

StructuredBodyKey key({
  String user = 'alice',
  String article = 'article-id',
  String locale = 'en',
}) => StructuredBodyKey(userId: user, articleId: article, locale: locale);

StructuredArticleDraft base() {
  final article = structuredArticle();
  return StructuredArticleDraft.parse(
    version: article['contentBlocksVersion'],
    blocks: article['contentBlocks'],
  );
}

StructuredArticleDraft body(String text) =>
    base().replacePlainText('paragraph', text);

StructuredSessionMetadata session({
  String? title = 'Edited title',
  String? summary = 'Exact summary',
  String? status = 'draft',
  StructuredCoverSelection? cover,
}) => StructuredSessionMetadata(
  slug: 'original-slug',
  title: title,
  summary: summary,
  workType: 'essay',
  publicationState: status,
  tags: StructuredTaxonomySelection(values: ['first', 'second'], touched: true),
  categories: StructuredTaxonomySelection(
    values: ['category-id'],
    touched: false,
  ),
  cover: cover,
);

StructuredSessionMetadata unknown() => StructuredSessionMetadata(
  slug: null,
  title: null,
  summary: null,
  workType: null,
  publicationState: null,
  tags: null,
  categories: null,
  cover: null,
);

SqliteStructuredBodyRecoveryStore store(AppDatabase db, {Uri? url}) =>
    SqliteStructuredBodyRecoveryStore(db, apiBaseUrl: url ?? backend);

Future<StructuredBodyRecovery> create(
  SqliteStructuredBodyRecoveryStore target, {
  StructuredBodyKey? forKey,
  StructuredSessionMetadata? original,
  StructuredSessionMetadata? edited,
}) async => (await target.create(
  key: forKey ?? key(),
  base: base(),
  body: body('Edited body'),
  updatedAt: instant,
  baseMetadata:
      original ??
      session(
        title: 'Original title',
        cover: StructuredCoverSelection.unchanged(),
      ),
  sessionMetadata:
      edited ??
      session(
        cover: StructuredCoverSelection.local(
          mimeType: 'image/png',
          bytes: [0, 1, 2, 255],
        ),
      ),
))!;

void expectSession(
  StructuredSessionMetadata? actual,
  StructuredSessionMetadata expected,
) {
  expect(actual, isNotNull);
  expect(actual!.toJson(), expected.toJson());
}

void main() {
  group('complete local session recovery', () {
    test(
      'base and current metadata round-trip together with rich bodies',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final target = store(db);
        final original = session(
          title: 'Original title',
          cover: StructuredCoverSelection.unchanged(),
        );
        final edited = session(
          title: 'New title',
          cover: StructuredCoverSelection.local(
            mimeType: 'image/png',
            bytes: [0, 1, 2, 255],
          ),
        );
        final saved = await create(target, original: original, edited: edited);
        final restored = (await target.load(key()))!;
        expect(restored.rowId, saved.rowId);
        expect(restored.revision, 1);
        expect(restored.base.toJsonBlocks(), base().toJsonBlocks());
        expect(
          restored.body.toJsonBlocks(),
          body('Edited body').toJsonBlocks(),
        );
        expectSession(restored.baseMetadata, original);
        expectSession(restored.sessionMetadata, edited);
        expect(restored.sessionMetadata?.cover?.bytes, [0, 1, 2, 255]);
        expect(restored.updatedAt, instant);
      },
    );

    test('local cover bytes and metadata survive database restart', () async {
      final dir = await Directory.systemTemp.createTemp(
        'rich-session-restart-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/db.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      final bytes = Uint8List.fromList([9, 8, 7, 0, 255]);
      final edited = session(
        cover: StructuredCoverSelection.local(
          mimeType: 'image/webp',
          bytes: bytes,
        ),
      );
      final initial = await create(store(db), edited: edited);
      bytes[0] = 0;
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final restored = (await store(db).load(key()))!;
      expect(restored.rowId, initial.rowId);
      expect(restored.sessionMetadata?.cover?.mimeType, 'image/webp');
      expect(restored.sessionMetadata?.cover?.bytes, [9, 8, 7, 0, 255]);
      expectSession(restored.sessionMetadata, edited);
      expect(restored.body.toJsonBlocks(), body('Edited body').toJsonBlocks());
    });

    test(
      'untouched, removed, remote and local covers all round-trip',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final target = store(db);
        final covers = <StructuredCoverSelection?>[
          null,
          StructuredCoverSelection.unchanged(),
          StructuredCoverSelection.removed(),
          StructuredCoverSelection.remote('/media/image'),
          StructuredCoverSelection.local(
            mimeType: 'image/jpeg',
            bytes: [1, 2, 3],
          ),
        ];
        for (var i = 0; i < covers.length; i++) {
          final targetKey = key(article: 'article-$i');
          final edited = session(cover: covers[i]);
          await create(target, forKey: targetKey, edited: edited);
          expectSession(
            (await target.load(targetKey))!.sessionMetadata,
            edited,
          );
        }
      },
    );

    test(
      'unknown, empty and explicitly cleared fields remain distinguishable',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final target = store(db);
        final empty = StructuredSessionMetadata(
          slug: '',
          title: '',
          summary: '',
          workType: '',
          publicationState: null,
          tags: StructuredTaxonomySelection(values: [], touched: true),
          categories: StructuredTaxonomySelection(values: [], touched: false),
          cover: StructuredCoverSelection.removed(),
        );
        await create(target, original: unknown(), edited: empty);
        final loaded = (await target.load(key()))!;
        expectSession(loaded.baseMetadata, unknown());
        expectSession(loaded.sessionMetadata, empty);
        expect(loaded.baseMetadata?.summary, isNull);
        expect(loaded.sessionMetadata?.summary, '');
        expect(loaded.baseMetadata?.tags, isNull);
        expect(loaded.sessionMetadata?.tags?.values, isEmpty);
        expect(loaded.sessionMetadata?.tags?.touched, isTrue);
        expect(loaded.sessionMetadata?.categories?.touched, isFalse);
        expect(loaded.baseMetadata?.publicationState, isNull);
      },
    );

    test(
      'body-only replace preserves both metadata snapshots exactly',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final target = store(db);
        final original = await create(target);
        final changed = (await target.replace(
          expected: original,
          body: body('body only'),
          updatedAt: instant,
        ))!;
        expect(changed.revision, 2);
        expect(
          changed.baseMetadataStorageJson,
          original.baseMetadataStorageJson,
        );
        expect(
          changed.sessionMetadataStorageJson,
          original.sessionMetadataStorageJson,
        );
        expectSession(changed.baseMetadata, original.baseMetadata!);
        expectSession(changed.sessionMetadata, original.sessionMetadata!);
        expect(changed.body.toJsonBlocks(), body('body only').toJsonBlocks());
      },
    );

    test(
      'atomic replace updates body and current metadata but not base',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final target = store(db);
        final original = await create(target);
        final nextMetadata = session(
          title: 'Changed',
          status: 'published',
          cover: StructuredCoverSelection.removed(),
        );
        final changed = (await target.replaceSession(
          expected: original,
          body: body('changed body'),
          sessionMetadata: nextMetadata,
          updatedAt: instant.add(const Duration(seconds: 1)),
        ))!;
        expect(changed.revision, 2);
        expect(changed.base.toJsonBlocks(), original.base.toJsonBlocks());
        expectSession(changed.baseMetadata, original.baseMetadata!);
        expectSession(changed.sessionMetadata, nextMetadata);
        expect(
          changed.body.toJsonBlocks(),
          body('changed body').toJsonBlocks(),
        );
        expect(changed.updatedAt, instant.add(const Duration(seconds: 1)));
        expectSession(
          (await target.load(key()))!.sessionMetadata,
          nextMetadata,
        );
      },
    );

    test(
      'different accounts, editions, articles and origins remain isolated',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final first = store(db);
        final second = store(
          db,
          url: Uri.parse('https://other.example.invalid/v1'),
        );
        final keys = [
          key(),
          key(user: 'bob'),
          key(article: 'other'),
          key(locale: 'zh-CN'),
          key(locale: 'zh-TW'),
        ];
        for (var i = 0; i < keys.length; i++) {
          await create(
            first,
            forKey: keys[i],
            edited: session(title: 'session $i'),
          );
        }
        await create(second, edited: session(title: 'other backend'));
        for (var i = 0; i < keys.length; i++) {
          expect(
            (await first.load(keys[i]))?.sessionMetadata?.title,
            'session $i',
          );
        }
        expect(
          (await second.load(key()))?.sessionMetadata?.title,
          'other backend',
        );
        expect(await second.load(key(user: 'bob')), isNull);
      },
    );
  });

  group('local conflict and failure safety', () {
    test(
      'stale session cannot replace or discard a newer metadata-only edit',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final first = store(db);
        final second = store(db);
        final old = await create(first);
        final other = (await second.load(key()))!;
        final newer = (await first.replaceSession(
          expected: old,
          body: old.body,
          sessionMetadata: session(title: 'Later metadata'),
          updatedAt: instant,
        ))!;
        expect(
          await second.replaceSession(
            expected: other,
            body: body('lost edit'),
            sessionMetadata: session(title: 'Stale'),
            updatedAt: instant,
          ),
          isNull,
        );
        expect(
          await second.replace(
            expected: other,
            body: body('lost body'),
            updatedAt: instant,
          ),
          isNull,
        );
        expect(await second.discard(other), isFalse);
        final restored = (await second.load(key()))!;
        expect(restored.revision, newer.revision);
        expect(restored.sessionMetadata?.title, 'Later metadata');
        expect(restored.body.toJsonBlocks(), newer.body.toJsonBlocks());
      },
    );

    test('recreated row cannot be changed by the deleted row token', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final target = store(db);
      final old = await create(target);
      expect(await target.discard(old), isTrue);
      final next = await create(target, edited: session(title: 'Recreated'));
      expect(next.rowId, isNot(old.rowId));
      expect(
        await target.replaceSession(
          expected: old,
          body: body('stale'),
          sessionMetadata: session(),
          updatedAt: instant,
        ),
        isNull,
      );
      expect(await target.discard(old), isFalse);
      expect((await target.load(key()))?.sessionMetadata?.title, 'Recreated');
    });

    test(
      'tampering either metadata column invalidates an existing token',
      () async {
        for (final column in ['base_metadata', 'session_metadata']) {
          final db = AppDatabase(NativeDatabase.memory());
          try {
            final target = store(db);
            final original = await create(target);
            final alternate = jsonEncode(
              session(title: 'modified without version').toJson(),
            );
            await db.customStatement(
              'UPDATE structured_body_drafts SET $column = ?',
              [alternate],
            );
            expect(await target.discard(original), isFalse, reason: column);
            expect(
              await target.replaceSession(
                expected: original,
                body: body('stale'),
                sessionMetadata: session(),
                updatedAt: instant,
              ),
              isNull,
              reason: column,
            );
            expect((await target.load(key()))?.revision, original.revision);
            final row = await db
                .customSelect('SELECT $column FROM structured_body_drafts')
                .getSingle();
            expect(row.read<String>(column), alternate);
          } finally {
            await db.close();
          }
        }
      },
    );

    test('failed database update leaves the full prior session intact', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final target = store(db);
      final original = await create(target);
      await db.customStatement(
        "CREATE TRIGGER reject_session BEFORE UPDATE ON structured_body_drafts BEGIN SELECT RAISE(ABORT, 'storage failure'); END",
      );
      await expectLater(
        target.replaceSession(
          expected: original,
          body: body('not saved'),
          sessionMetadata: session(
            title: 'not saved',
            cover: StructuredCoverSelection.removed(),
          ),
          updatedAt: instant,
        ),
        throwsA(anything),
      );
      final retained = (await target.load(key()))!;
      expect(retained.revision, 1);
      expect(retained.body.toJsonBlocks(), original.body.toJsonBlocks());
      expectSession(retained.sessionMetadata, original.sessionMetadata!);
      expectSession(retained.baseMetadata, original.baseMetadata!);
      await db.customStatement('DROP TRIGGER reject_session');
      final saved = (await target.replaceSession(
        expected: original,
        body: body('saved'),
        sessionMetadata: session(title: 'saved'),
        updatedAt: instant,
      ))!;
      expect(saved.sessionMetadata?.title, 'saved');
      expect(saved.body.toJsonBlocks(), body('saved').toJsonBlocks());
    });

    test('failed creation preserves unrelated recovery rows', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final target = store(db);
      await create(target);
      await db.customStatement(
        "CREATE TRIGGER reject_session_insert BEFORE INSERT ON structured_body_drafts BEGIN SELECT RAISE(ABORT, 'storage failure'); END",
      );
      await expectLater(
        create(target, forKey: key(article: 'new')),
        throwsA(anything),
      );
      expect(await target.load(key(article: 'new')), isNull);
      expect(
        (await target.load(key()))?.sessionMetadata?.title,
        'Edited title',
      );
      await db.customStatement('DROP TRIGGER reject_session_insert');
      expect((await create(target, forKey: key(article: 'new'))).revision, 1);
    });

    test(
      'changing only selected cover still advances revision and protects old cover',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final target = store(db);
        final first = await create(target);
        final replaced = (await target.replaceSession(
          expected: first,
          body: first.body,
          sessionMetadata: session(
            cover: StructuredCoverSelection.local(
              mimeType: 'image/jpeg',
              bytes: [5, 4, 3],
            ),
          ),
          updatedAt: instant,
        ))!;
        expect(replaced.revision, 2);
        expect(await target.discard(first), isFalse);
        expect((await target.load(key()))?.sessionMetadata?.cover?.bytes, [
          5,
          4,
          3,
        ]);
        expect(await target.discard(replaced), isTrue);
      },
    );
  });

  group('corrupt and incomplete sessions', () {
    test(
      'bad JSON never turns into an absent session or allows overwrite',
      () async {
        for (final column in ['base_metadata', 'session_metadata']) {
          final db = AppDatabase(NativeDatabase.memory());
          try {
            final target = store(db);
            final previous = await create(target);
            await db.customStatement(
              'UPDATE structured_body_drafts SET $column = ?',
              ['{broken'],
            );
            await expectLater(
              target.load(key()),
              throwsFormatException,
              reason: column,
            );
            expect(
              await target.create(
                key: key(),
                base: base(),
                body: body('replacement'),
                updatedAt: instant,
              ),
              isNull,
            );
            expect(await target.discard(previous), isFalse);
            expect(
              await target.replaceSession(
                expected: previous,
                body: body('replacement'),
                sessionMetadata: session(),
                updatedAt: instant,
              ),
              isNull,
            );
            final row = await db
                .customSelect('SELECT $column FROM structured_body_drafts')
                .getSingle();
            expect(row.read<String>(column), '{broken');
          } finally {
            await db.close();
          }
        }
      },
    );

    test(
      'unknown metadata versions and fields are rejected, not discarded',
      () async {
        final variants = <Map<String, Object?>>[
          {...session().toJson(), 'schema': 2},
          {...session().toJson(), 'future': 'valuable'},
          {...session().toJson()}..remove('summary'),
          {...session().toJson(), 'publicationState': 'future'},
          {
            ...session().toJson(),
            'tags': {'values': [], 'touched': true, 'future': 1},
          },
        ];
        for (final invalid in variants) {
          final db = AppDatabase(NativeDatabase.memory());
          try {
            final target = store(db);
            final previous = await create(target);
            final raw = jsonEncode(invalid);
            await db.customStatement(
              'UPDATE structured_body_drafts SET session_metadata = ?',
              [raw],
            );
            await expectLater(target.load(key()), throwsFormatException);
            expect(await target.discard(previous), isFalse);
            expect(
              (await db
                      .customSelect(
                        'SELECT session_metadata FROM structured_body_drafts',
                      )
                      .getSingle())
                  .read<String>('session_metadata'),
              raw,
            );
          } finally {
            await db.close();
          }
        }
      },
    );

    test(
      'missing, malformed or oversized local cover is not silently removed',
      () async {
        final covers = <Object?>[
          {'kind': 'local', 'mimeType': 'image/png'},
          {'kind': 'local', 'mimeType': 'image/png', 'bytes': ''},
          {'kind': 'local', 'mimeType': 'image/png', 'bytes': '***'},
          {'kind': 'local', 'mimeType': 'image/gif', 'bytes': 'AQ=='},
          {'kind': 'remote', 'url': 'javascript:bad'},
        ];
        for (final cover in covers) {
          final db = AppDatabase(NativeDatabase.memory());
          try {
            final target = store(db);
            final saved = await create(target);
            final invalid = {...session().toJson(), 'cover': cover};
            await db.customStatement(
              'UPDATE structured_body_drafts SET session_metadata = ?',
              [jsonEncode(invalid)],
            );
            await expectLater(
              target.load(key()),
              throwsFormatException,
              reason: '$cover',
            );
            expect(await target.discard(saved), isFalse);
            expect(
              await db
                  .customSelect('SELECT id FROM structured_body_drafts')
                  .get(),
              hasLength(1),
            );
          } finally {
            await db.close();
          }
        }
      },
    );

    test(
      'oversized metadata cannot be parsed or overwritten by a stale token',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final target = store(db);
        final old = await create(target);
        final oversized =
            'x' * (StructuredSessionMetadata.maxEncodedLength + 1);
        await db.customStatement(
          'UPDATE structured_body_drafts SET session_metadata = ?',
          [oversized],
        );
        await expectLater(target.load(key()), throwsFormatException);
        expect(await target.discard(old), isFalse);
        expect(
          await target.replaceSession(
            expected: old,
            body: old.body,
            sessionMetadata: session(),
            updatedAt: instant,
          ),
          isNull,
        );
        expect(
          (await db
                  .customSelect(
                    'SELECT length(session_metadata) AS size FROM structured_body_drafts',
                  )
                  .getSingle())
              .read<int>('size'),
          oversized.length,
        );
      },
    );
  });

  group('v14 migration', () {
    test(
      'existing body-only rows stay unknown and can gain metadata without guessing a base',
      () async {
        final dir = await Directory.systemTemp.createTemp('rich-session-v14-');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/db.sqlite');
        var db = AppDatabase(NativeDatabase(file));
        final before = (await store(db).create(
          key: key(),
          base: base(),
          body: body('old body'),
          updatedAt: instant,
        ))!;
        await db.writeMetadata('migration-marker', 'retained');
        await db.close();
        final old = raw.sqlite3.open(file.path);
        old.execute(
          'ALTER TABLE structured_body_drafts DROP COLUMN base_metadata',
        );
        old.execute(
          'ALTER TABLE structured_body_drafts DROP COLUMN session_metadata',
        );
        old.execute('PRAGMA user_version = 14');
        old.close();
        db = AppDatabase(NativeDatabase(file));
        addTearDown(db.close);
        final target = store(db);
        final restored = (await target.load(key()))!;
        expect(restored.rowId, before.rowId);
        expect(restored.revision, before.revision);
        expect(restored.base.toJsonBlocks(), before.base.toJsonBlocks());
        expect(restored.body.toJsonBlocks(), before.body.toJsonBlocks());
        expect(restored.baseMetadata, isNull);
        expect(restored.sessionMetadata, isNull);
        expect(await db.readMetadata('migration-marker'), 'retained');
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          15,
        );
        final next = (await target.replaceSession(
          expected: restored,
          body: restored.body,
          sessionMetadata: unknown(),
          updatedAt: instant,
        ))!;
        expect(next.baseMetadata, isNull);
        expectSession(next.sessionMetadata, unknown());
        expect(await target.discard(restored), isFalse);
        expect(await target.discard(next), isTrue);
      },
    );

    test(
      'body-only API retains unknown metadata and never synthesizes defaults',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final target = store(db);
        final original = (await target.create(
          key: key(),
          base: base(),
          body: base(),
          updatedAt: instant,
        ))!;
        expect(original.baseMetadata, isNull);
        expect(original.sessionMetadata, isNull);
        final updated = (await target.replace(
          expected: original,
          body: body('body change'),
          updatedAt: instant,
        ))!;
        expect(updated.baseMetadata, isNull);
        expect(updated.sessionMetadata, isNull);
        expect(updated.baseMetadataStorageJson, isNull);
        expect(updated.sessionMetadataStorageJson, isNull);
      },
    );
  });
}

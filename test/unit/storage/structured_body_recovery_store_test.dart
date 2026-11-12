import 'dart:convert';
import 'dart:io';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_draft_store.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../../support/structured_article_fixtures.dart';

final backend = Uri.parse('https://api.example.invalid/v1');
final otherBackend = Uri.parse('https://other.example.invalid/v1');
final instant = DateTime.utc(2026, 10, 29, 11, 22, 33, 444, 555);

StructuredBodyKey key({
  String user = 'alice',
  String article = 'article-uuid',
  String locale = 'zh-CN',
}) => StructuredBodyKey(userId: user, articleId: article, locale: locale);

StructuredArticleDraft fullBody() {
  final article = structuredArticle();
  return StructuredArticleDraft.parse(
    version: article['contentBlocksVersion'],
    blocks: article['contentBlocks'],
  );
}

StructuredArticleDraft v0Body(String text) => StructuredArticleDraft.parse(
  version: 0,
  blocks: [
    {'id': 'p', 'type': 'paragraph', 'text': text},
    {
      'id': 'image',
      'type': 'image',
      'src': '/image.png',
      'alt': 'alt',
      'caption': '',
    },
  ],
);

StructuredArticleDraft modifiedBody() => fullBody()
    .setTextRunMark('heading', 0, 'bold', enabled: false)
    .replacePlainText('paragraph', 'new literal text');

Future<StructuredBodyRecovery> create(
  SqliteStructuredBodyRecoveryStore store, {
  StructuredBodyKey? forKey,
  StructuredArticleDraft? base,
  StructuredArticleDraft? body,
  DateTime? at,
}) async => (await store.create(
  key: forKey ?? key(),
  base: base ?? fullBody(),
  body: body ?? modifiedBody(),
  updatedAt: at ?? instant,
))!;

SqliteStructuredBodyRecoveryStore storeFor(AppDatabase db, {Uri? url}) =>
    SqliteStructuredBodyRecoveryStore(db, apiBaseUrl: url ?? backend);

void expectBody(
  StructuredArticleDraft actual,
  StructuredArticleDraft expected,
) {
  expect(actual.version, expected.version);
  expect(actual.toJsonBlocks(), expected.toJsonBlocks());
}

void main() {
  group('identity and durable recovery', () {
    test(
      'round-trips the original base and modified body without flattening',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        final saved = await create(store);
        final loaded = (await store.load(key()))!;
        expect(loaded.rowId, saved.rowId);
        expect(loaded.revision, 1);
        expect(loaded.updatedAt, instant);
        expectBody(loaded.base, fullBody());
        expectBody(loaded.body, modifiedBody());
        expect(
          loaded.base.toJsonBlocks(),
          structuredArticle()['contentBlocks'],
        );
        expect(loaded.body.blocks.map((b) => b['id']), [
          'heading',
          'image-one',
          'paragraph',
          'quote',
          'list',
          'image-two',
          'code',
        ]);
        expect(loaded.body.blocks[1]['alt'], 'First image alt');
        expect(loaded.body.blocks[1]['caption'], 'First caption');
        expect(loaded.body.blocks.last['code'], '  a\n\n b  \n');
        expect(
          (loaded.body.blocks.first['inlines'] as List).first['href'],
          '/guide',
        );
      },
    );

    test(
      'v0 and v1 are independently preserved even when versions differ',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        await create(store, base: v0Body('original'), body: fullBody());
        final saved = (await store.load(key()))!;
        expectBody(saved.base, v0Body('original'));
        expectBody(saved.body, fullBody());
        final replaced = (await store.replace(
          expected: saved,
          body: v0Body('local change'),
          updatedAt: instant,
        ))!;
        expectBody(replaced.base, v0Body('original'));
        expectBody(replaced.body, v0Body('local change'));
      },
    );

    test('survives closing and reopening the database', () async {
      final directory = await Directory.systemTemp.createTemp(
        'rich-body-restart-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/data.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      final initial = await create(storeFor(db));
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final loaded = (await storeFor(db).load(key()))!;
      expect(loaded.rowId, initial.rowId);
      expect(loaded.revision, initial.revision);
      expect(loaded.updatedAt, instant);
      expectBody(loaded.base, fullBody());
      expectBody(loaded.body, modifiedBody());
      expect(await storeFor(db).discard(initial), isTrue);
      expect(await storeFor(db).load(key()), isNull);
    });

    test('separates account, stable article, locale and backend', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final first = storeFor(db);
      final second = storeFor(db, url: otherBackend);
      final variants = [
        key(),
        key(user: 'bob'),
        key(article: 'second-article'),
        key(locale: 'en'),
        key(locale: 'zh-TW'),
      ];
      for (var i = 0; i < variants.length; i++) {
        await create(first, forKey: variants[i], body: v0Body('body$i'));
      }
      await create(second, body: v0Body('other backend'));
      for (var i = 0; i < variants.length; i++) {
        expectBody((await first.load(variants[i]))!.body, v0Body('body$i'));
      }
      expectBody((await second.load(key()))!.body, v0Body('other backend'));
      expect(await first.load(key(user: 'nobody')), isNull);
      expect(await first.load(key(article: 'missing')), isNull);
      expect(await second.load(key(locale: 'en')), isNull);
      expect(
        (await db.customSelect('SELECT id FROM structured_body_drafts').get()),
        hasLength(6),
      );
    });

    test(
      'backend credentials, query and fragment never enter local namespace',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final privateUrl = Uri.parse(
          'https://user:private@api.example.invalid/v1?secret=token#fragment',
        );
        final withCredentials = storeFor(db, url: privateUrl);
        final canonical = storeFor(db);
        final created = await create(withCredentials);
        expect(created.backendStorageKey, 'https://api.example.invalid/v1');
        expectBody((await canonical.load(key()))!.body, modifiedBody());
        final row = await db
            .customSelect('SELECT backend FROM structured_body_drafts')
            .getSingle();
        expect(row.read<String>('backend'), 'https://api.example.invalid/v1');
        expect(row.read<String>('backend'), isNot(contains('private')));
        expect(row.read<String>('backend'), isNot(contains('secret')));
        expect(row.read<String>('backend'), isNot(contains('fragment')));
      },
    );

    test('separate paths are distinct backends', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final first = storeFor(
        db,
        url: Uri.parse('https://api.example.invalid/one/'),
      );
      final second = storeFor(
        db,
        url: Uri.parse('https://api.example.invalid/two'),
      );
      await create(first, body: v0Body('one'));
      await create(second, body: v0Body('two'));
      expectBody((await first.load(key()))!.body, v0Body('one'));
      expectBody((await second.load(key()))!.body, v0Body('two'));
    });

    test('rejects missing or modified identity and unknown locale', () {
      for (final value in ['', ' ', ' alice', 'alice ']) {
        expect(() => key(user: value), throwsArgumentError, reason: value);
        expect(() => key(article: value), throwsArgumentError, reason: value);
      }
      for (final locale in ['', 'en-US', 'zh', 'zh-cn', ' en', 'other']) {
        expect(() => key(locale: locale), throwsArgumentError, reason: locale);
      }
      expect(key(locale: 'zh-CN').locale, 'zh-CN');
      expect(key(locale: 'zh-TW').locale, 'zh-TW');
      expect(key(locale: 'en').locale, 'en');
    });

    test('requires an HTTP backend namespace', () {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      for (final url in [
        'file:///tmp/data',
        'ftp://example.invalid/x',
        '/relative',
      ]) {
        expect(() => storeFor(db, url: Uri.parse(url)), throwsArgumentError);
      }
    });
  });

  group('compare and swap', () {
    test('duplicate create cannot overwrite a snapshot', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = storeFor(db);
      final original = await create(store);
      final conflicting = await store.create(
        key: key(),
        base: v0Body('other base'),
        body: v0Body('other body'),
        updatedAt: instant.add(const Duration(days: 1)),
      );
      expect(conflicting, isNull);
      final loaded = (await store.load(key()))!;
      expect(loaded.rowId, original.rowId);
      expect(loaded.revision, 1);
      expectBody(loaded.base, fullBody());
      expectBody(loaded.body, modifiedBody());
    });

    test(
      'replacement advances revision but keeps the original base and identity',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        final original = await create(store);
        final newer = (await store.replace(
          expected: original,
          body: v0Body('revision two'),
          updatedAt: instant.add(const Duration(seconds: 1)),
        ))!;
        expect(newer.rowId, original.rowId);
        expect(newer.revision, 2);
        expect(newer.key.articleId, original.key.articleId);
        expect(newer.key.userId, original.key.userId);
        expect(newer.key.locale, original.key.locale);
        expect(newer.baseStorageJson, original.baseStorageJson);
        expectBody(newer.base, original.base);
        expectBody(newer.body, v0Body('revision two'));
        expect(newer.updatedAt, instant.add(const Duration(seconds: 1)));
      },
    );

    test('two editors cannot overwrite or discard one another', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final first = storeFor(db);
      final second = storeFor(db);
      final a = await create(first);
      final b = (await second.load(key()))!;
      final aSaved = (await first.replace(
        expected: a,
        body: v0Body('A edit'),
        updatedAt: instant,
      ))!;
      expect(
        await second.replace(
          expected: b,
          body: v0Body('B edit'),
          updatedAt: instant,
        ),
        isNull,
      );
      expect(await second.discard(b), isFalse);
      expectBody((await second.load(key()))!.body, v0Body('A edit'));
      expect(await second.discard(aSaved), isTrue);
      expect(await first.load(key()), isNull);
    });

    test(
      'same body and timestamp still advance revision and protect later edit',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        final old = await create(store);
        final next = (await store.replace(
          expected: old,
          body: old.body,
          updatedAt: old.updatedAt,
        ))!;
        expect(next.revision, old.revision + 1);
        expect(await store.discard(old), isFalse);
        expect(
          await store.replace(
            expected: old,
            body: old.body,
            updatedAt: old.updatedAt,
          ),
          isNull,
        );
        expect(await store.discard(next), isTrue);
      },
    );

    test(
      'timestamps may move backwards without making newer body disposable',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        final old = await create(store);
        final next = (await store.replace(
          expected: old,
          body: v0Body('new'),
          updatedAt: instant.subtract(const Duration(days: 1)),
        ))!;
        expect(next.updatedAt.isBefore(old.updatedAt), isTrue);
        expect(await store.discard(old), isFalse);
        expectBody((await store.load(key()))!.body, v0Body('new'));
      },
    );

    test(
      'deleting then recreating does not allow an old token to affect the new row',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        final old = await create(store);
        expect(await store.discard(old), isTrue);
        final next = await create(store);
        expect(next.rowId, isNot(old.rowId));
        expect(next.revision, old.revision);
        expect(await store.discard(old), isFalse);
        expect(
          await store.replace(
            expected: old,
            body: v0Body('stale'),
            updatedAt: instant,
          ),
          isNull,
        );
        expectBody((await store.load(key()))!.body, modifiedBody());
      },
    );

    test(
      'a token from a different backend cannot affect an identical row',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final first = storeFor(db);
        final second = storeFor(db, url: otherBackend);
        final firstSaved = await create(first);
        final secondSaved = await create(second);
        // Force all row-local fields to match so this checks the backend fence
        // itself, not merely the fact that SQLite assigned two different IDs.
        final foreignToken = StructuredBodyRecovery(
          key: firstSaved.key,
          backendStorageKey: firstSaved.backendStorageKey,
          rowId: secondSaved.rowId,
          revision: secondSaved.revision,
          base: secondSaved.base,
          body: secondSaved.body,
          updatedAt: secondSaved.updatedAt,
          baseStorageJson: secondSaved.baseStorageJson,
          bodyStorageJson: secondSaved.bodyStorageJson,
        );
        expect(await second.discard(foreignToken), isFalse);
        expect(
          await second.replace(
            expected: foreignToken,
            body: v0Body('wrong'),
            updatedAt: instant,
          ),
          isNull,
        );
        expect(await second.discard(firstSaved), isFalse);
        expect(
          await second.replace(
            expected: firstSaved,
            body: v0Body('wrong'),
            updatedAt: instant,
          ),
          isNull,
        );
        expect(await second.discard(secondSaved), isTrue);
        expect(await first.load(key()), isNotNull);
      },
    );

    test(
      'token cannot cross article, account or edition even with a row id',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        final a = await create(store);
        for (final otherKey in [
          key(user: 'bob'),
          key(article: 'another'),
          key(locale: 'en'),
        ]) {
          final forged = StructuredBodyRecovery(
            key: otherKey,
            backendStorageKey: a.backendStorageKey,
            rowId: a.rowId,
            revision: a.revision,
            base: a.base,
            body: a.body,
            updatedAt: a.updatedAt,
            baseStorageJson: a.baseStorageJson,
            bodyStorageJson: a.bodyStorageJson,
          );
          expect(await store.discard(forged), isFalse);
          expect(
            await store.replace(
              expected: forged,
              body: v0Body('wrong'),
              updatedAt: instant,
            ),
            isNull,
          );
        }
        expectBody((await store.load(key()))!.body, modifiedBody());
      },
    );

    test(
      'multiple updates preserve base and never revive old snapshots',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        final snapshots = <StructuredBodyRecovery>[await create(store)];
        for (var i = 0; i < 6; i++) {
          snapshots.add(
            (await store.replace(
              expected: snapshots.last,
              body: v0Body('revision $i'),
              updatedAt: instant,
            ))!,
          );
        }
        for (final stale in snapshots.take(snapshots.length - 1)) {
          expect(await store.discard(stale), isFalse);
          expect(
            await store.replace(
              expected: stale,
              body: fullBody(),
              updatedAt: instant,
            ),
            isNull,
          );
        }
        expect(snapshots.last.revision, 7);
        expectBody(snapshots.last.base, fullBody());
        expectBody((await store.load(key()))!.body, v0Body('revision 5'));
      },
    );
  });

  group('fail-closed persistence', () {
    test(
      'corrupt JSON is not interpreted as a missing or empty draft',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        await create(store);
        await db.customStatement(
          'UPDATE structured_body_drafts SET body_blocks = ?',
          ['{broken'],
        );
        await expectLater(store.load(key()), throwsFormatException);
        expect(
          await store.create(
            key: key(),
            base: fullBody(),
            body: modifiedBody(),
            updatedAt: instant,
          ),
          isNull,
        );
        final row = await db
            .customSelect('SELECT body_blocks FROM structured_body_drafts')
            .getSingle();
        expect(row.read<String>('body_blocks'), '{broken');
      },
    );

    test(
      'unknown versions and malformed base or body are not restored',
      () async {
        final cases = <Map<String, Object>>[
          {'column': 'base_version', 'value': 2},
          {'column': 'body_version', 'value': 2},
          {'column': 'base_blocks', 'value': '{}'},
          {'column': 'body_blocks', 'value': '[]'},
          {'column': 'base_blocks', 'value': '[{"id":"x","type":"future"}]'},
          {
            'column': 'body_blocks',
            'value': '[{"id":"x","type":"paragraph","text":"x","extra":true}]',
          },
          {
            'column': 'body_blocks',
            'value':
                '[{"id":"x","type":"paragraph","text":"x","inlines":[{"text":"wrong"}]}]',
          },
        ];
        for (final testCase in cases) {
          final db = AppDatabase(NativeDatabase.memory());
          try {
            final store = storeFor(db);
            await create(store);
            await db.customStatement(
              'UPDATE structured_body_drafts SET ${testCase['column']} = ?',
              [testCase['value']],
            );
            await expectLater(
              store.load(key()),
              throwsFormatException,
              reason: '$testCase',
            );
            expect(
              await store.create(
                key: key(),
                base: fullBody(),
                body: fullBody(),
                updatedAt: instant,
              ),
              isNull,
            );
          } finally {
            await db.close();
          }
        }
      },
    );

    test(
      'oversized stored JSON is rejected without replacing the row',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        await create(store);
        final oversized = 'x' * 1000001;
        await db.customStatement(
          'UPDATE structured_body_drafts SET body_blocks = ?',
          [oversized],
        );
        await expectLater(store.load(key()), throwsFormatException);
        expect(
          await store.create(
            key: key(),
            base: fullBody(),
            body: fullBody(),
            updatedAt: instant,
          ),
          isNull,
        );
        final row = await db
            .customSelect(
              'SELECT length(body_blocks) AS size FROM structured_body_drafts',
            )
            .getSingle();
        expect(row.read<int>('size'), 1000001);
      },
    );

    test(
      'corruption without revision change invalidates previous token',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        final old = await create(store);
        await db.customStatement(
          'UPDATE structured_body_drafts SET body_blocks = ?',
          ['{broken'],
        );
        expect(await store.discard(old), isFalse);
        expect(
          await store.replace(
            expected: old,
            body: v0Body('not a repair'),
            updatedAt: instant,
          ),
          isNull,
        );
        await expectLater(store.load(key()), throwsFormatException);
        expect(
          (await db
                  .customSelect(
                    'SELECT body_blocks FROM structured_body_drafts',
                  )
                  .getSingle())
              .read<String>('body_blocks'),
          '{broken',
        );
      },
    );

    test(
      'every stored compare field participates in local conflict detection',
      () async {
        final cases = <String, Object>{
          'base_version': 0,
          'base_blocks': '[{"id":"p","type":"paragraph","text":"tampered"}]',
          'body_version': 0,
          'body_blocks': '[{"id":"p","type":"paragraph","text":"tampered"}]',
          'updated_at': instant.microsecondsSinceEpoch + 1,
          'revision': 42,
        };
        for (final item in cases.entries) {
          final db = AppDatabase(NativeDatabase.memory());
          try {
            final store = storeFor(db);
            final old = await create(store);
            await db.customStatement(
              'UPDATE structured_body_drafts SET ${item.key} = ?',
              [item.value],
            );
            expect(await store.discard(old), isFalse, reason: item.key);
            expect(
              await store.replace(
                expected: old,
                body: v0Body('wrong'),
                updatedAt: instant,
              ),
              isNull,
              reason: item.key,
            );
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

    test('revision must be positive and cannot overflow', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = storeFor(db);
      await create(store);
      await db.customStatement(
        'UPDATE structured_body_drafts SET revision = 0',
      );
      await expectLater(store.load(key()), throwsFormatException);
      await db.customStatement(
        'UPDATE structured_body_drafts SET revision = 9223372036854775807',
      );
      final maximum = (await store.load(key()))!;
      expect(
        await store.replace(
          expected: maximum,
          body: v0Body('overflow'),
          updatedAt: instant,
        ),
        isNull,
      );
      expect((await store.load(key()))!.revision, maximum.revision);
      expect(await store.discard(maximum), isTrue);
    });

    test('a failed create rolls back and another attempt can succeed', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = storeFor(db);
      await db.customStatement(
        "CREATE TRIGGER reject_rich_insert BEFORE INSERT ON structured_body_drafts BEGIN SELECT RAISE(ABORT, 'synthetic insert failure'); END",
      );
      await expectLater(create(store), throwsA(anything));
      expect(await store.load(key()), isNull);
      await db.customStatement('DROP TRIGGER reject_rich_insert');
      final saved = await create(store);
      expect(saved.revision, 1);
      expectBody((await store.load(key()))!.body, modifiedBody());
    });

    test(
      'a failed replacement leaves old content and revision untouched',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        final old = await create(store);
        await db.customStatement(
          "CREATE TRIGGER reject_rich_update BEFORE UPDATE ON structured_body_drafts BEGIN SELECT RAISE(ABORT, 'synthetic update failure'); END",
        );
        await expectLater(
          store.replace(expected: old, body: v0Body('new'), updatedAt: instant),
          throwsA(anything),
        );
        final retained = (await store.load(key()))!;
        expect(retained.revision, old.revision);
        expectBody(retained.base, old.base);
        expectBody(retained.body, old.body);
        await db.customStatement('DROP TRIGGER reject_rich_update');
        final saved = (await store.replace(
          expected: old,
          body: v0Body('new'),
          updatedAt: instant,
        ))!;
        expect(saved.revision, 2);
        expectBody(saved.body, v0Body('new'));
      },
    );

    test('failed deletion is surfaced and preserves snapshot', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = storeFor(db);
      final saved = await create(store);
      await db.customStatement(
        "CREATE TRIGGER reject_rich_delete BEFORE DELETE ON structured_body_drafts BEGIN SELECT RAISE(ABORT, 'synthetic delete failure'); END",
      );
      await expectLater(store.discard(saved), throwsA(anything));
      expectBody((await store.load(key()))!.body, saved.body);
      await db.customStatement('DROP TRIGGER reject_rich_delete');
      expect(await store.discard(saved), isTrue);
    });

    test(
      'detached exported bodies cannot change stored or in-memory values',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = storeFor(db);
        final saved = await create(store);
        final exported = saved.body.toJsonBlocks();
        exported[1]['alt'] = 'mutated';
        (exported[0]['inlines'] as List).clear();
        expect(saved.body.blocks[1]['alt'], 'First image alt');
        expectBody((await store.load(key()))!.body, modifiedBody());
        expect(() => saved.body.blocks.clear(), throwsUnsupportedError);
        expect(
          () => saved.base.blocks.first['text'] = 'changed',
          throwsUnsupportedError,
        );
      },
    );
  });

  group('database migration and isolation', () {
    test(
      'v13 upgrade keeps plain drafts, cache, queue and legacy data intact',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'rich-body-upgrade-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/data.sqlite');
        var db = AppDatabase(NativeDatabase(file));
        final plain = SqliteBlogDraftStore(db, apiBaseUrl: backend);
        await plain.save(
          BlogDraft(
            userId: 'alice',
            blogId: 'public-slug',
            title: 'old title',
            content: 'unpublished plain text',
            tags: const ['one'],
            categoryIds: const [],
            updatedAt: instant,
          ),
        );
        await db.writeMetadata('marker', 'keep');
        await db.customStatement(
          "INSERT INTO drafts(blog_id,title,content,tags,updated_at) VALUES('legacy','legacy title','ownerless','[]',1)",
        );
        await db.customStatement("INSERT INTO theme(id,mode) VALUES(0,'dark')");
        await db.upsertBlogRow(
          id: 'cached',
          contentLocale: 'en',
          title: 'cached title',
          content: 'cached body',
          posterId: 'author',
          imageUrl: '',
          tags: [],
          updatedAt: instant,
        );
        await db.customStatement(
          "INSERT INTO publish_queue(id, backend, user_id, idempotency_key, title, content, tags, state, created_at, updated_at) "
          "VALUES('pending', 'https://api.example.invalid/v1', 'alice', 'retry-key', 'queued', 'offline work', '[]', 'pending', 1, 1)",
        );
        await db.close();

        final old = raw.sqlite3.open(file.path);
        old.execute('DROP TABLE structured_body_drafts');
        old.execute('PRAGMA user_version = 13');
        old.close();

        db = AppDatabase(NativeDatabase(file));
        addTearDown(db.close);
        final restoredPlain = await SqliteBlogDraftStore(
          db,
          apiBaseUrl: backend,
        ).load('public-slug', userId: 'alice');
        expect(restoredPlain?.title, 'old title');
        expect(restoredPlain?.content, 'unpublished plain text');
        expect(restoredPlain?.tags, ['one']);
        expect(restoredPlain?.categoryIds, isEmpty);
        expect(await db.readMetadata('marker'), 'keep');
        expect(
          (await db.customSelect('SELECT content FROM drafts').getSingle())
              .read<String>('content'),
          'ownerless',
        );
        expect(
          (await db.customSelect('SELECT mode FROM theme').getSingle())
              .read<String>('mode'),
          'dark',
        );
        expect(
          (await db
                  .customSelect(
                    'SELECT content FROM blog_cache WHERE id = \'cached\'',
                  )
                  .getSingle())
              .read<String>('content'),
          'cached body',
        );
        expect(
          (await db
                  .customSelect(
                    "SELECT content FROM publish_queue WHERE id = 'pending'",
                  )
                  .getSingle())
              .read<String>('content'),
          'offline work',
        );
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          14,
        );
        expect(await storeFor(db).load(key()), isNull);
        await create(storeFor(db));
        expect(
          (await SqliteBlogDraftStore(
            db,
            apiBaseUrl: backend,
          ).load('public-slug', userId: 'alice'))?.content,
          'unpublished plain text',
        );
        expectBody((await storeFor(db).load(key()))!.body, modifiedBody());
      },
    );

    test(
      'structured recovery and legacy drafts never replace each other',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final plain = SqliteBlogDraftStore(db, apiBaseUrl: backend);
        final rich = storeFor(db);
        final legacy = BlogDraft(
          userId: 'alice',
          blogId: 'article-uuid',
          title: 'plain',
          content: 'original markdown',
          tags: const [],
          updatedAt: instant,
        );
        await plain.save(legacy);
        final saved = await create(rich);
        await plain.save(
          BlogDraft(
            userId: 'alice',
            blogId: 'article-uuid',
            title: 'plain updated',
            content: 'new markdown',
            tags: const [],
            updatedAt: instant,
          ),
        );
        expectBody((await rich.load(key()))!.body, modifiedBody());
        expect(await plain.deleteDraftsFor('article-uuid', userId: 'alice'), 1);
        expectBody((await rich.load(key()))!.body, modifiedBody());
        expect(await rich.discard(saved), isTrue);
        expect(await plain.load('article-uuid', userId: 'alice'), isNull);
      },
    );

    test(
      'separate database connections observe local revisions and conflicts',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'rich-body-two-db-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/data.sqlite');
        final db1 = AppDatabase(NativeDatabase(file));
        final db2 = AppDatabase(NativeDatabase(file));
        addTearDown(db1.close);
        addTearDown(db2.close);
        final one = storeFor(db1);
        final two = storeFor(db2);
        final initial = await create(one);
        final other = (await two.load(key()))!;
        final updated = (await two.replace(
          expected: other,
          body: v0Body('second connection'),
          updatedAt: instant,
        ))!;
        expect(await one.discard(initial), isFalse);
        expect(
          await one.replace(
            expected: initial,
            body: v0Body('stale first connection'),
            updatedAt: instant,
          ),
          isNull,
        );
        expectBody((await one.load(key()))!.body, v0Body('second connection'));
        expect(await one.discard(updated), isTrue);
      },
    );

    test(
      'table only contains namespaced body data, not API credentials',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final url = Uri.parse(
          'https://name:password@example.invalid/api?secret=token#fragment',
        );
        await create(storeFor(db, url: url));
        final row =
            (await db
                    .customSelect('SELECT * FROM structured_body_drafts')
                    .getSingle())
                .data;
        final serialized = jsonEncode(row);
        expect(serialized, isNot(contains('password')));
        expect(serialized, isNot(contains('token')));
        expect(serialized, isNot(contains('fragment')));
        expect(row['locale'], 'zh-CN');
        expect(row['article_id'], 'article-uuid');
        expect(row['user_id'], 'alice');
      },
    );
  });
}

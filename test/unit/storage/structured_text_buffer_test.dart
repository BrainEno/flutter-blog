import 'dart:convert';
import 'dart:io';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_buffer_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../../support/structured_article_fixtures.dart';

final time = DateTime.utc(2026, 10, 29);
final url = Uri.parse('https://api.example.invalid/v1');

StructuredBodyKey key({
  String user = 'user',
  String article = 'article',
  String locale = 'en',
}) => StructuredBodyKey(userId: user, articleId: article, locale: locale);

StructuredArticleDraft document() {
  final fixture = structuredArticle();
  return StructuredArticleDraft.parse(
    version: fixture['contentBlocksVersion'],
    blocks: fixture['contentBlocks'],
  );
}

StructuredTextBuffer buffer(String text, {String id = 'paragraph'}) =>
    StructuredTextBuffer(blockId: id, text: text);
SqliteStructuredBodyRecoveryStore store(AppDatabase db, {Uri? backend}) =>
    SqliteStructuredBodyRecoveryStore(db, apiBaseUrl: backend ?? url);

Future<StructuredBodyRecovery> create(
  SqliteStructuredBodyRecoveryStore target, {
  StructuredBodyKey? identity,
}) async => (await target.create(
  key: identity ?? key(),
  base: document(),
  body: document(),
  updatedAt: time,
))!;

Future<StructuredTextBufferRecovery> save(
  SqliteStructuredBodyRecoveryStore target,
  StructuredBodyRecovery parent,
  String text,
) async => (await target.createTextBuffer(
  expected: parent,
  buffer: buffer(text),
  updatedAt: time,
))!;

Future<void> corrupt(AppDatabase db, String column, Object? value) async {
  // Column names are fixed test fixtures, never user input.
  await db.customStatement('UPDATE structured_body_drafts SET $column = ?', [
    value,
  ]);
}

void main() {
  group('intermediate text values', () {
    test(
      'empty, whitespace, newlines, unicode and control characters round trip exactly',
      () {
        for (final text in [
          '',
          ' ',
          '\n\r\t',
          '你好 🌏 e\u0301',
          '\u0000\u0001"\\',
        ]) {
          final input = buffer(text);
          final decoded = StructuredTextBuffer.decode(input.encode());
          expect(decoded.blockId, 'paragraph');
          expect(decoded.text, text);
          expect(decoded.encode(), input.encode());
        }
      },
    );

    test('limits count Dart UTF-16 units without dropping characters', () {
      final text = '😀' * 10000;
      expect(text.length, 20000);
      expect(StructuredTextBuffer.decode(buffer(text).encode()).text, text);
      expect(() => buffer('${text}x'), throwsFormatException);
    });

    test('large escaped values still fit bounded storage', () {
      final input = buffer('\u0000' * StructuredTextBuffer.maxTextLength);
      expect(
        input.encode().length,
        lessThan(StructuredTextBuffer.maxEncodedLength),
      );
      expect(StructuredTextBuffer.decode(input.encode()).text, input.text);
      expect(
        () => StructuredTextBuffer.decode(
          'x' * (StructuredTextBuffer.maxEncodedLength + 1),
        ),
        throwsFormatException,
      );
    });

    test('rejects invalid identity and out-of-range input before writing', () {
      for (final id in ['', ' x', 'x ', 'x' * 2049]) {
        expect(() => buffer('text', id: id), throwsFormatException);
      }
      expect(() => buffer('x' * 20001), throwsFormatException);
    });

    test(
      'strict version, shape and fields never silently reinterpret data',
      () {
        final invalid = <Object?>[
          null,
          [],
          'text',
          {},
          {'schema': 2, 'blockId': 'paragraph', 'text': 'x'},
          {'schema': 1.0, 'blockId': 'paragraph', 'text': 'x'},
          {'schema': 1, 'blockId': 'paragraph'},
          {'schema': 1, 'blockId': 'paragraph', 'text': null},
          {'schema': 1, 'blockId': 42, 'text': 'x'},
          {'schema': 1, 'blockId': '', 'text': 'x'},
          {'schema': 1, 'blockId': 'paragraph', 'text': 'x', 'unknown': true},
        ];
        for (final value in invalid) {
          expect(
            () => StructuredTextBuffer.decode(jsonEncode(value)),
            throwsFormatException,
            reason: '$value',
          );
        }
        expect(
          () => StructuredTextBuffer.decode('{bad'),
          throwsFormatException,
        );
      },
    );

    test('only an unformatted text block may be targeted', () {
      final body = document();
      buffer('ok').validateTarget(body);
      for (final id in [
        'heading',
        'quote',
        'image-one',
        'list',
        'code',
        'missing',
      ]) {
        expect(
          () => buffer('ok', id: id).validateTarget(body),
          throwsFormatException,
          reason: id,
        );
      }
    });

    test('valid heading and quote retain their non-text fields', () {
      final body = StructuredArticleDraft.parse(
        version: 1,
        blocks: [
          {'id': 'h', 'type': 'heading', 'level': 3, 'text': 'heading'},
          {
            'id': 'q',
            'type': 'quote',
            'text': 'quote',
            'attribution': 'someone',
          },
        ],
      );
      final changed = buffer('next', id: 'h').applyTo(body);
      final next = buffer('new quote', id: 'q').applyTo(changed);
      expect(next.blocks[0], {
        'id': 'h',
        'type': 'heading',
        'level': 3,
        'text': 'next',
      });
      expect(next.blocks[1], {
        'id': 'q',
        'type': 'quote',
        'text': 'new quote',
        'attribution': 'someone',
      });
      expect(body.blocks[0]['text'], 'heading');
    });

    test('empty intermediate text is not misrepresented as a valid body', () {
      final original = document();
      final pending = buffer('');
      pending.validateTarget(original);
      expect(() => pending.applyTo(original), throwsFormatException);
      expect(original.blocks[2]['text'], 'literal **asterisks**');
    });

    test('application preserves every other block and inline structure', () {
      final original = document();
      final result = buffer('literal *markdown* and 链接').applyTo(original);
      expect(result.version, original.version);
      expect(result.blocks[2]['text'], 'literal *markdown* and 链接');
      for (var i = 0; i < original.blocks.length; i++) {
        if (i != 2) {
          expect(result.blocks[i], original.blocks[i]);
        }
      }
    });
  });

  group('buffer persistence', () {
    late AppDatabase db;
    late SqliteStructuredBodyRecoveryStore target;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      target = store(db);
    });
    tearDown(() => db.close());

    test(
      'absent row and absent buffer are distinct from a buffered row',
      () async {
        expect(await target.loadTextBuffer(key()), isNull);
        await create(target);
        expect(await target.loadTextBuffer(key()), isNull);
        expect(await target.load(key()), isNotNull);
      },
    );

    test(
      'empty text is stored separately and normal loading fails closed',
      () async {
        final initial = await create(target);
        final saved = await save(target, initial, '');
        expect(saved.parent.revision, initial.revision + 1);
        expect(saved.parent.body.toJsonBlocks(), initial.body.toJsonBlocks());
        final loaded = (await target.loadTextBuffer(key()))!;
        expect(loaded.buffer.text, '');
        expect(loaded.storageJson, saved.storageJson);
        await expectLater(target.load(key()), throwsFormatException);
        expect(
          await target.create(
            key: key(),
            base: document(),
            body: document(),
            updatedAt: time,
          ),
          isNull,
        );
      },
    );

    test('stale normal updates and deletes cannot discard a buffer', () async {
      final initial = await create(target);
      final saved = await save(target, initial, 'pending');
      expect(
        await target.replace(
          expected: initial,
          body: document(),
          updatedAt: time,
        ),
        isNull,
      );
      expect(await target.discard(initial), isFalse);
      expect(
        (await target.loadTextBuffer(key()))!.storageJson,
        saved.storageJson,
      );
    });

    test(
      'a current buffered parent cannot be used by normal update or delete',
      () async {
        final initial = await create(target);
        final saved = await save(target, initial, 'pending');
        expect(
          await target.replace(
            expected: saved.parent,
            body: document(),
            updatedAt: time,
          ),
          isNull,
        );
        expect(await target.discard(saved.parent), isFalse);
        expect((await target.loadTextBuffer(key()))!.buffer.text, 'pending');
      },
    );

    test('replace uses exact revision and preserves immutable base', () async {
      final initial = await create(target);
      final first = await save(target, initial, 'one');
      final second = (await target.replaceTextBuffer(
        expected: first,
        buffer: buffer('two'),
        updatedAt: time,
      ))!;
      expect(second.parent.revision, first.parent.revision + 1);
      expect(second.parent.rowId, first.parent.rowId);
      expect(second.parent.baseStorageJson, first.parent.baseStorageJson);
      expect(second.parent.bodyStorageJson, first.parent.bodyStorageJson);
      expect(second.buffer.text, 'two');
      expect(
        await target.replaceTextBuffer(
          expected: first,
          buffer: buffer('stale'),
          updatedAt: time,
        ),
        isNull,
      );
      expect(
        await target.discardTextBuffer(expected: first, updatedAt: time),
        isNull,
      );
      expect((await target.loadTextBuffer(key()))!.buffer.text, 'two');
    });

    test('explicit apply changes body atomically and removes buffer', () async {
      final initial = await create(target);
      final saved = await save(target, initial, 'applied');
      final applied = (await target.applyTextBuffer(
        expected: saved,
        updatedAt: time,
      ))!;
      expect(applied.revision, saved.parent.revision + 1);
      expect(applied.baseStorageJson, initial.baseStorageJson);
      expect(applied.body.blocks[2]['text'], 'applied');
      expect(await target.loadTextBuffer(key()), isNull);
      expect(
        (await target.load(key()))!.body.toJsonBlocks(),
        applied.body.toJsonBlocks(),
      );
      expect(
        await target.applyTextBuffer(expected: saved, updatedAt: time),
        isNull,
      );
    });

    test(
      'invalid application leaves the intermediate value recoverable',
      () async {
        final saved = await save(target, await create(target), '');
        await expectLater(
          target.applyTextBuffer(expected: saved, updatedAt: time),
          throwsFormatException,
        );
        final recovered = (await target.loadTextBuffer(key()))!;
        expect(recovered.storageJson, saved.storageJson);
        expect(recovered.parent.revision, saved.parent.revision);
        expect(recovered.parent.bodyStorageJson, saved.parent.bodyStorageJson);
      },
    );

    test(
      'explicit discard preserves the body and increments the revision',
      () async {
        final initial = await create(target);
        final saved = await save(target, initial, '');
        final discarded = (await target.discardTextBuffer(
          expected: saved,
          updatedAt: time,
        ))!;
        expect(discarded.bodyStorageJson, initial.bodyStorageJson);
        expect(discarded.baseStorageJson, initial.baseStorageJson);
        expect(discarded.revision, saved.parent.revision + 1);
        expect(await target.loadTextBuffer(key()), isNull);
        expect(
          await target.discardTextBuffer(expected: saved, updatedAt: time),
          isNull,
        );
      },
    );

    test(
      'retargeting is rejected rather than losing the first buffer',
      () async {
        final saved = await save(target, await create(target), 'unsaved');
        await expectLater(
          target.replaceTextBuffer(
            expected: saved,
            buffer: buffer('other', id: 'heading'),
            updatedAt: time,
          ),
          throwsArgumentError,
        );
        expect((await target.loadTextBuffer(key()))!.buffer.text, 'unsaved');
      },
    );

    test('creation refuses formatted, missing or non-text targets', () async {
      final initial = await create(target);
      for (final id in ['heading', 'quote', 'missing', 'code', 'image-one']) {
        await expectLater(
          target.createTextBuffer(
            expected: initial,
            buffer: buffer('x', id: id),
            updatedAt: time,
          ),
          throwsFormatException,
        );
      }
      expect(await target.loadTextBuffer(key()), isNull);
      expect((await target.load(key()))!.revision, initial.revision);
    });

    test('raw buffer mutation without revision update conflicts', () async {
      final saved = await save(target, await create(target), 'first');
      final changedRaw = jsonEncode({
        'schema': 1,
        'blockId': 'paragraph',
        'text': 'external',
      });
      await corrupt(db, 'text_buffer', changedRaw);
      expect(
        await target.replaceTextBuffer(
          expected: saved,
          buffer: buffer('next'),
          updatedAt: time,
        ),
        isNull,
      );
      expect(
        await target.discardTextBuffer(expected: saved, updatedAt: time),
        isNull,
      );
      expect(
        await target.applyTextBuffer(expected: saved, updatedAt: time),
        isNull,
      );
      expect((await target.loadTextBuffer(key()))!.storageJson, changedRaw);
    });

    test('bad or unknown buffer data is not treated as absent', () async {
      final saved = await save(target, await create(target), 'first');
      for (final rawValue in [
        '{bad',
        'null',
        '{}',
        '{"schema":2,"blockId":"paragraph","text":"future"}',
        'x' * 150001,
      ]) {
        await corrupt(db, 'text_buffer', rawValue);
        await expectLater(target.loadTextBuffer(key()), throwsFormatException);
        await expectLater(target.load(key()), throwsFormatException);
        expect(await target.discard(saved.parent), isFalse);
        expect(
          await target.replace(
            expected: saved.parent,
            body: document(),
            updatedAt: time,
          ),
          isNull,
        );
        expect(
          await target.discardTextBuffer(expected: saved, updatedAt: time),
          isNull,
        );
      }
    });

    test('a forged mismatch between raw and parsed value is refused', () async {
      final saved = await save(target, await create(target), 'original');
      final forged = StructuredTextBufferRecovery(
        parent: saved.parent,
        buffer: buffer('substitute'),
        storageJson: saved.storageJson,
      );
      await expectLater(
        target.applyTextBuffer(expected: forged, updatedAt: time),
        throwsFormatException,
      );
      await expectLater(
        target.discardTextBuffer(expected: forged, updatedAt: time),
        throwsFormatException,
      );
      await expectLater(
        target.replaceTextBuffer(
          expected: forged,
          buffer: buffer('replacement'),
          updatedAt: time,
        ),
        throwsFormatException,
      );
      expect((await target.loadTextBuffer(key()))!.buffer.text, 'original');
    });

    test('damaged parent does not permit buffer recovery', () async {
      await save(target, await create(target), 'pending');
      await corrupt(db, 'body_blocks', 'not-json');
      await expectLater(target.loadTextBuffer(key()), throwsFormatException);
      await expectLater(target.load(key()), throwsFormatException);
    });

    test('identity and backend partition both reading and writing', () async {
      final parent = await create(target);
      final saved = await save(target, parent, 'private');
      for (final other in [
        key(user: 'other'),
        key(article: 'other'),
        key(locale: 'zh-TW'),
      ]) {
        expect(await target.loadTextBuffer(other), isNull);
      }
      final otherBackend = store(
        db,
        backend: Uri.parse('https://other.example.invalid/v1'),
      );
      expect(await otherBackend.loadTextBuffer(key()), isNull);
      expect(
        await otherBackend.discardTextBuffer(expected: saved, updatedAt: time),
        isNull,
      );
      expect(
        await otherBackend.replaceTextBuffer(
          expected: saved,
          buffer: buffer('wrong'),
          updatedAt: time,
        ),
        isNull,
      );
      expect((await target.loadTextBuffer(key()))!.buffer.text, 'private');
    });

    test('stale parent cannot create a buffer after a body edit', () async {
      final initial = await create(target);
      final edited = (await target.replace(
        expected: initial,
        body: document().replacePlainText('paragraph', 'newer'),
        updatedAt: time,
      ))!;
      expect(
        await target.createTextBuffer(
          expected: initial,
          buffer: buffer('stale'),
          updatedAt: time,
        ),
        isNull,
      );
      expect(await target.loadTextBuffer(key()), isNull);
      expect(
        (await target.load(key()))!.bodyStorageJson,
        edited.bodyStorageJson,
      );
    });

    test('revision exhaustion fails closed for each mutation', () async {
      await create(target);
      await corrupt(db, 'revision', 9223372036854775807);
      final initial = (await target.load(key()))!;
      expect(
        await target.createTextBuffer(
          expected: initial,
          buffer: buffer('x'),
          updatedAt: time,
        ),
        isNull,
      );
      expect(await target.loadTextBuffer(key()), isNull);
    });

    test(
      'catalog still exposes identity but never exposes the buffered text',
      () async {
        await save(target, await create(target), 'secret draft');
        final page = await target.page(userId: 'user');
        expect(page.entries, hasLength(1));
        expect(page.entries.single.key!.articleId, 'article');
        expect(page.entries.single.key!.locale, 'en');
      },
    );
  });

  group('database lifecycle and concurrency', () {
    test(
      'buffer survives close and reopen without changing the base',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'structured-buffer-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/db.sqlite');
        var db = AppDatabase(NativeDatabase(file));
        final initial = await create(store(db));
        final saved = await save(store(db), initial, '');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        addTearDown(db.close);
        final loaded = (await store(db).loadTextBuffer(key()))!;
        expect(loaded.storageJson, saved.storageJson);
        expect(loaded.parent.baseStorageJson, initial.baseStorageJson);
        expect(loaded.parent.bodyStorageJson, initial.bodyStorageJson);
        expect(loaded.buffer.text, '');
      },
    );

    test('two writers compete without clobbering the winner', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final first = store(db);
      final second = store(db);
      final initial = await create(first);
      final results = await Future.wait([
        first.createTextBuffer(
          expected: initial,
          buffer: buffer('first'),
          updatedAt: time,
        ),
        second.createTextBuffer(
          expected: initial,
          buffer: buffer('second'),
          updatedAt: time,
        ),
      ]);
      expect(results.whereType<StructuredTextBufferRecovery>(), hasLength(1));
      expect(results.where((result) => result == null), hasLength(1));
      expect(
        (await first.loadTextBuffer(key()))!.storageJson,
        results.whereType<StructuredTextBufferRecovery>().single.storageJson,
      );
    });

    test('delete and recreate cannot reuse an old buffer token', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final target = store(db);
      final original = await create(target);
      final saved = await save(target, original, 'old');
      final cleared = (await target.discardTextBuffer(
        expected: saved,
        updatedAt: time,
      ))!;
      expect(await target.discard(cleared), isTrue);
      final recreated = await create(target);
      final newer = await save(target, recreated, 'new');
      expect(newer.parent.rowId, isNot(saved.parent.rowId));
      expect(
        await target.discardTextBuffer(expected: saved, updatedAt: time),
        isNull,
      );
      expect((await target.loadTextBuffer(key()))!.buffer.text, 'new');
    });

    test(
      'v15 migration preserves old data and introduces a nullable buffer',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'structured-buffer-migration-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/db.sqlite');
        var db = AppDatabase(NativeDatabase(file));
        final initial = await create(store(db));
        await db.close();
        final old = raw.sqlite3.open(file.path);
        old.execute(
          'ALTER TABLE structured_body_drafts DROP COLUMN text_buffer',
        );
        old.execute('PRAGMA user_version = 15');
        old.close();
        db = AppDatabase(NativeDatabase(file));
        addTearDown(db.close);
        final target = store(db);
        final loaded = (await target.load(key()))!;
        expect(loaded.rowId, initial.rowId);
        expect(loaded.revision, initial.revision);
        expect(loaded.baseStorageJson, initial.baseStorageJson);
        expect(loaded.bodyStorageJson, initial.bodyStorageJson);
        expect(await target.loadTextBuffer(key()), isNull);
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          16,
        );
        final pending = await save(target, loaded, 'after migration');
        expect(
          (await target.loadTextBuffer(key()))!.storageJson,
          pending.storageJson,
        );
      },
    );
  });
}

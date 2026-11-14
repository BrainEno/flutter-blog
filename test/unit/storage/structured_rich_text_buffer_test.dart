import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_rich_text_buffer.dart';
import 'package:belog/features/blog/domain/editing/structured_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/repositories/structured_rich_text_buffer_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/structured_article_fixtures.dart';

final now = DateTime.utc(2026, 11, 14);
StructuredBodyKey key({
  String user = 'author',
  String article = 'article',
  String locale = 'en',
}) => StructuredBodyKey(userId: user, articleId: article, locale: locale);
StructuredArticleDraft document() {
  final source = structuredArticle();
  return StructuredArticleDraft.parse(
    version: source['contentBlocksVersion'],
    blocks: source['contentBlocks'],
  );
}

StructuredRichBufferRun run(String text, {List<String>? marks, String? href}) =>
    StructuredRichBufferRun(text: text, marks: marks, href: href);
StructuredRichTextBuffer buffer({
  String id = 'heading',
  int? item,
  List<StructuredRichBufferRun>? runs,
  int base = -1,
  int extent = -1,
  int composeStart = -1,
  int composeEnd = -1,
}) => StructuredRichTextBuffer(
  blockId: id,
  itemIndex: item,
  runs:
      runs ??
      [
        run('Bold', marks: ['bold'], href: '/guide'),
        run('代码'),
      ],
  selectionBase: base,
  selectionExtent: extent,
  composingStart: composeStart,
  composingEnd: composeEnd,
);
SqliteStructuredBodyRecoveryStore store(
  AppDatabase db, {
  String backend = 'https://one.example.invalid',
}) => SqliteStructuredBodyRecoveryStore(db, apiBaseUrl: Uri.parse(backend));
Future<StructuredBodyRecovery> create(
  SqliteStructuredBodyRecoveryStore store, {
  StructuredBodyKey? identity,
}) async => (await store.create(
  key: identity ?? key(),
  base: document(),
  body: document(),
  updatedAt: now,
))!;
Future<StructuredRichTextBufferRecovery> save(
  SqliteStructuredBodyRecoveryStore store,
  StructuredBodyRecovery parent, {
  StructuredRichTextBuffer? value,
}) async => (await store.createRichTextBuffer(
  expected: parent,
  buffer: value ?? buffer(),
  updatedAt: now,
))!;
Map<String, Object?> block(StructuredArticleDraft body, String id) =>
    body.blocks.firstWhere((value) => value['id'] == id);
Future<void> corrupt(AppDatabase db, String column, Object? value) => db
    .customStatement('UPDATE structured_body_drafts SET $column = ?', [value]);

void main() {
  group('lossless bounded intermediate values', () {
    test('empty, whitespace, newlines, and literal syntax round-trip', () {
      for (final value in [
        '',
        ' ',
        '\n\r\t',
        '\u0000"\\',
        '文字 😀 e\u0301',
        '**literal** [x](y)',
      ]) {
        final original = buffer(
          runs: [run(value, marks: [], href: '/x')],
          base: value.length,
          extent: 0,
        );
        final decoded = StructuredRichTextBuffer.decode(original.encode());
        expect(decoded.text, value);
        expect(decoded.runs.single.marks, isEmpty);
        expect(decoded.runs.single.href, '/x');
        expect(decoded.selectionBase, value.length);
        expect(decoded.selectionExtent, 0);
        expect(decoded.encode(), original.encode());
      }
    });

    test(
      'unpaired surrogates and split pairs round-trip as exact code units',
      () {
        final high = String.fromCharCodes([0xd83d]);
        final low = String.fromCharCodes([0xde00]);
        final original = buffer(
          runs: [
            run('A$high', marks: ['bold']),
            run('${low}B', href: '/x'),
            run(high),
            run(low),
          ],
        );
        final decoded = StructuredRichTextBuffer.decode(original.encode());
        expect(
          decoded.runs.map((r) => r.text.codeUnits).toList(),
          original.runs.map((r) => r.text.codeUnits).toList(),
        );
        expect(decoded.runs[0].marks, ['bold']);
        expect(decoded.runs[1].href, '/x');
        expect(decoded.encode(), original.encode());
        expect(original.encode().contains(high), isFalse);
      },
    );

    test('zero runs, empty runs and absent marks are distinct', () {
      final empty = buffer(runs: []);
      final explicit = buffer(
        runs: [
          run('', marks: []),
          run(''),
        ],
      );
      expect(StructuredRichTextBuffer.decode(empty.encode()).runs, isEmpty);
      final decoded = StructuredRichTextBuffer.decode(explicit.encode());
      expect(decoded.runs.length, 2);
      expect(decoded.runs[0].marks, isEmpty);
      expect(decoded.runs[1].marks, isNull);
      expect(decoded.text, '');
      expect(decoded.encode(), isNot(empty.encode()));
    });

    test('selection is directional and composition can be pending', () {
      final original = buffer(
        runs: [run('abcd')],
        base: 4,
        extent: 1,
        composeStart: 1,
        composeEnd: 3,
      );
      final decoded = StructuredRichTextBuffer.decode(original.encode());
      expect(decoded.selectionBase, 4);
      expect(decoded.selectionExtent, 1);
      expect(decoded.composingStart, 1);
      expect(decoded.composingEnd, 3);
      expect(() => decoded.applyTo(document()), throwsFormatException);
    });

    test(
      'cursor and composing offsets may preserve an IME surrogate split',
      () {
        final value = buffer(
          runs: [run('😀')],
          base: 1,
          extent: 1,
          composeStart: 0,
          composeEnd: 1,
        );
        final decoded = StructuredRichTextBuffer.decode(value.encode());
        expect(decoded.selectionBase, 1);
        expect(decoded.composingEnd, 1);
        expect(decoded.text.codeUnits, '😀'.codeUnits);
        expect(() => decoded.applyTo(document()), throwsFormatException);
      },
    );

    test('input lists are defensively copied and immutable', () {
      final marks = ['bold'];
      final source = [run('x', marks: marks)];
      final value = buffer(runs: source);
      marks.add('code');
      source.add(run('other'));
      expect(value.runs.length, 1);
      expect(value.runs.first.marks, ['bold']);
      expect(() => value.runs.add(run('x')), throwsUnsupportedError);
      expect(
        () => value.runs.first.marks!.add('italic'),
        throwsUnsupportedError,
      );
    });

    test('invalid offsets, ranges, and item indices fail closed', () {
      for (final pair in [
        [-1, 0],
        [0, -1],
        [-2, -2],
        [0, 5],
        [5, 0],
      ]) {
        expect(
          () => buffer(runs: [run('abcd')], base: pair[0], extent: pair[1]),
          throwsFormatException,
        );
      }
      for (final pair in [
        [-1, 0],
        [0, -1],
        [2, 1],
        [0, 5],
        [-2, -2],
      ]) {
        expect(
          () => buffer(
            runs: [run('abcd')],
            composeStart: pair[0],
            composeEnd: pair[1],
          ),
          throwsFormatException,
        );
      }
      expect(() => buffer(item: -1), throwsFormatException);
      expect(() => buffer(item: 100), throwsFormatException);
      expect(() => buffer(id: ''), throwsFormatException);
      expect(() => buffer(id: ' heading'), throwsFormatException);
      expect(() => buffer(id: 'x' * 101), throwsFormatException);
    });

    test('rejects unknown or duplicate marks and unsafe links', () {
      expect(() => run('x', marks: ['bold', 'bold']), throwsFormatException);
      expect(() => run('x', marks: ['unsupported']), throwsFormatException);
      for (final href in [
        '',
        '//host',
        'javascript:alert(1)',
        'https://u:p@host/',
        '/space here',
      ]) {
        expect(() => run('x', href: href), throwsFormatException);
      }
      expect(run('x', marks: ['code', 'bold'], href: '/safe').marks, [
        'code',
        'bold',
      ]);
    });

    test('bounds run count, text length and serialized representation', () {
      expect(buffer(runs: [run('x' * 20000)]).text.length, 20000);
      expect(
        () => buffer(runs: [run('x' * 20000), run('x')]),
        throwsFormatException,
      );
      expect(() => run('x' * 20001), throwsFormatException);
      expect(
        buffer(runs: [for (var i = 0; i < 1000; i++) run('')]).runs.length,
        1000,
      );
      expect(
        () => buffer(runs: [for (var i = 0; i < 1001; i++) run('')]),
        throwsFormatException,
      );
      expect(
        () => StructuredRichTextBuffer.decode('x' * 1500001),
        throwsFormatException,
      );
      expect(
        () => buffer(
          runs: [
            for (var i = 0; i < 1000; i++) run('', href: '/${'x' * 2047}'),
          ],
        ),
        throwsFormatException,
      );
    });

    test('decoder rejects missing, extra, wrongly typed and future fields', () {
      final raw = buffer().toJson();
      for (final bad in <Map<String, Object?>>[
        {...raw, 'schema': 3},
        {...raw, 'schema': 2.0},
        {...raw, 'unexpected': true},
        {...raw}..remove('runs'),
        {...raw, 'itemIndex': '0'},
        {...raw, 'selectionBase': 1.5},
        {...raw, 'composingStart': null},
        {...raw, 'runs': 'bad'},
        {...raw, 'blockIdUnits': 'heading'},
      ]) {
        expect(
          () => StructuredRichTextBuffer.decode(jsonEncode(bad)),
          throwsFormatException,
        );
      }
      for (final raw in ['null', '[]', '{', '{}']) {
        expect(
          () => StructuredRichTextBuffer.decode(raw),
          throwsFormatException,
        );
      }
    });

    test(
      'decoder rejects malformed run fields and invalid UTF-16 integers',
      () {
        final source = buffer().toJson();
        final invalid = <Object?>[
          null,
          {},
          {
            'units': [1],
            'x': 1,
          },
          {
            'units': [-1],
          },
          {
            'units': [65536],
          },
          {
            'units': [1.0],
          },
          {
            'units': ['1'],
          },
          {'units': null},
          {'units': [], 'marks': null},
          {
            'units': [],
            'marks': [1],
          },
          {'units': [], 'hrefUnits': null},
          {
            'units': [],
            'hrefUnits': [1.5],
          },
          {
            'units': [],
            'marks': ['bad'],
          },
        ];
        for (final value in invalid) {
          expect(
            () => StructuredRichTextBuffer.decode(
              jsonEncode({
                ...source,
                'runs': [value],
              }),
            ),
            throwsFormatException,
            reason: '$value',
          );
        }
        expect(
          () => StructuredRichTextBuffer.decode(
            jsonEncode({
              ...source,
              'blockIdUnits': [65536],
            }),
          ),
          throwsFormatException,
        );
      },
    );

    test('random code-unit payloads survive the encoding unchanged', () {
      final random = Random(232244);
      for (var trial = 0; trial < 300; trial++) {
        final units = [for (var i = 0; i < 30; i++) random.nextInt(65536)];
        final text = String.fromCharCodes(units);
        final value = buffer(
          runs: [run(text, marks: trial.isEven ? [] : null)],
        );
        final decoded = StructuredRichTextBuffer.decode(value.encode());
        expect(
          decoded.runs.single.text.codeUnits,
          units,
          reason: 'trial $trial',
        );
        expect(decoded.encode(), value.encode());
      }
    });
  });

  group('validated application', () {
    test('applies formatted runs without touching other blocks', () {
      final source = document();
      final value = buffer(
        runs: [
          run('New ', marks: ['bold', 'italic'], href: '/new'),
          run('标题', marks: []),
        ],
      );
      final result = value.applyTo(source);
      expect(block(result, 'heading')['text'], 'New 标题');
      expect(block(result, 'heading')['level'], 2);
      expect(block(result, 'heading')['inlines'], [
        {
          'text': 'New ',
          'marks': ['bold', 'italic'],
          'href': '/new',
        },
        {'text': '标题', 'marks': <String>[]},
      ]);
      expect(result.blocks.skip(1).toList(), source.blocks.skip(1).toList());
      expect(block(source, 'heading')['text'], 'Bold代码');
    });

    test('list item apply preserves ordering and all other item runs', () {
      final source = document();
      final value = buffer(
        id: 'list',
        item: 1,
        runs: [
          run(' changed ', marks: ['code'], href: '/new'),
        ],
      );
      final result = value.applyTo(source);
      final before = block(source, 'list');
      final after = block(result, 'list');
      expect(after['items'], ['First item', ' changed ']);
      expect(after['ordered'], before['ordered']);
      expect(
        (after['itemInlines'] as List)[0],
        (before['itemInlines'] as List)[0],
      );
      expect((after['itemInlines'] as List)[1], [
        {
          'text': ' changed ',
          'marks': ['code'],
          'href': '/new',
        },
      ]);
      expect(
        result.blocks.where((b) => b['id'] != 'list').toList(),
        source.blocks.where((b) => b['id'] != 'list').toList(),
      );
    });

    test('rejects plain, nontext, missing, wrong index and v0 targets', () {
      final source = document();
      for (final id in ['paragraph', 'image-one', 'code', 'list', 'missing']) {
        expect(
          () => buffer(id: id).validateTarget(source),
          throwsFormatException,
          reason: id,
        );
      }
      expect(
        () => buffer(id: 'heading', item: 0).validateTarget(source),
        throwsFormatException,
      );
      expect(
        () => buffer(id: 'list', item: 2).validateTarget(source),
        throwsFormatException,
      );
      final v0 = StructuredArticleDraft.parse(
        version: 0,
        blocks: [
          {'id': 'p', 'type': 'paragraph', 'text': 'plain'},
        ],
      );
      expect(() => buffer(id: 'p').validateTarget(v0), throwsFormatException);
      final plainList = StructuredArticleDraft.parse(
        version: 1,
        blocks: [
          {
            'id': 'l',
            'type': 'list',
            'ordered': false,
            'items': ['one'],
          },
        ],
      );
      expect(
        () => buffer(id: 'l', item: 0).validateTarget(plainList),
        throwsFormatException,
      );
    });

    test(
      'empty runs, invalid text and unfinished composition remain buffered',
      () {
        final source = document();
        final high = String.fromCharCodes([0xd83d]);
        final cases = [
          buffer(runs: []),
          buffer(runs: [run('')]),
          buffer(runs: [run(' ')]),
          buffer(runs: [run(high)]),
          buffer(runs: [run('text')], composeStart: 0, composeEnd: 2),
        ];
        final original = source.toJsonBlocks();
        for (final value in cases) {
          expect(() => value.applyTo(source), throwsFormatException);
          expect(
            StructuredRichTextBuffer.decode(value.encode()).encode(),
            value.encode(),
          );
        }
        expect(source.toJsonBlocks(), original);
      },
    );

    test('split run surrogate pair is not silently rewritten on apply', () {
      final high = String.fromCharCodes([0xd83d]);
      final low = String.fromCharCodes([0xde00]);
      final value = buffer(runs: [run(high), run(low)]);
      expect(value.text, '😀');
      expect(() => value.applyTo(document()), throwsFormatException);
      expect(
        StructuredRichTextBuffer.decode(value.encode()).runs[0].text.codeUnits,
        [0xd83d],
      );
    });

    test('empty composing range is finished, active composition is not', () {
      final source = document();
      final collapsed = buffer(
        runs: [run('done')],
        composeStart: 1,
        composeEnd: 1,
      );
      expect(block(collapsed.applyTo(source), 'heading')['text'], 'done');
      final active = buffer(
        runs: [run('done')],
        composeStart: 1,
        composeEnd: 2,
      );
      expect(() => active.applyTo(source), throwsFormatException);
    });

    test('20,000 text limit and 2,000 list limit come from body validator', () {
      final source = document();
      final para = buffer(runs: [run('x' * 20000)]);
      expect(
        (block(para.applyTo(source), 'heading')['text'] as String).length,
        20000,
      );
      final list = buffer(id: 'list', item: 0, runs: [run('x' * 2001)]);
      expect(() => list.applyTo(source), throwsFormatException);
      expect(block(source, 'list')['items'], ['First item', ' second item ']);
    });
  });

  group('shared-slot SQLite persistence', () {
    late AppDatabase db;
    late SqliteStructuredBodyRecoveryStore target;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      target = store(db);
    });
    tearDown(() => db.close());

    test('missing row and empty slot do not invent a recovery', () async {
      expect(await target.loadRichTextBuffer(key()), isNull);
      final parent = await create(target);
      expect(await target.loadRichTextBuffer(key()), isNull);
      expect((await target.load(key()))!.revision, parent.revision);
    });

    test(
      'empty and composing states survive save without changing parent',
      () async {
        final parent = await create(target);
        final value = buffer(
          runs: [run('')],
          base: 0,
          extent: 0,
          composeStart: 0,
          composeEnd: 0,
        );
        final saved = await save(target, parent, value: value);
        final loaded = (await target.loadRichTextBuffer(key()))!;
        expect(loaded.storageJson, saved.storageJson);
        expect(loaded.buffer.text, '');
        expect(loaded.buffer.selectionBase, 0);
        expect(loaded.parent.rowId, parent.rowId);
        expect(loaded.parent.revision, parent.revision + 1);
        expect(loaded.parent.bodyStorageJson, parent.bodyStorageJson);
        expect(loaded.parent.baseStorageJson, parent.baseStorageJson);
        await expectLater(target.load(key()), throwsFormatException);
        await expectLater(target.loadTextBuffer(key()), throwsFormatException);
      },
    );

    test('unpaired text survives a real SQLite round trip', () async {
      final parent = await create(target);
      final high = String.fromCharCodes([0xd83d]);
      final value = buffer(
        runs: [
          run('A$high', marks: ['bold']),
        ],
        base: 2,
        extent: 2,
      );
      final saved = await save(target, parent, value: value);
      final loaded = (await target.loadRichTextBuffer(key()))!;
      expect(loaded.buffer.text.codeUnits, [65, 0xd83d]);
      expect(loaded.storageJson, saved.storageJson);
      await expectLater(
        target.applyRichTextBuffer(expected: loaded, updatedAt: now),
        throwsFormatException,
      );
      expect(
        (await target.loadRichTextBuffer(key()))!.storageJson,
        saved.storageJson,
      );
    });

    test(
      'plain and rich slots are mutually exclusive in both directions',
      () async {
        final parent = await create(target);
        final plain = (await target.createTextBuffer(
          expected: parent,
          buffer: StructuredTextBuffer(blockId: 'paragraph', text: 'pending'),
          updatedAt: now,
        ))!;
        await expectLater(
          target.loadRichTextBuffer(key()),
          throwsFormatException,
        );
        expect(
          await target.createRichTextBuffer(
            expected: plain.parent,
            buffer: buffer(),
            updatedAt: now,
          ),
          isNull,
        );
        final cleared = (await target.discardTextBuffer(
          expected: plain,
          updatedAt: now,
        ))!;
        final rich = await save(target, cleared);
        await expectLater(target.loadTextBuffer(key()), throwsFormatException);
        expect(
          await target.createTextBuffer(
            expected: rich.parent,
            buffer: StructuredTextBuffer(blockId: 'paragraph', text: 'pending'),
            updatedAt: now,
          ),
          isNull,
        );
        expect(
          (await target.loadRichTextBuffer(key()))!.storageJson,
          rich.storageJson,
        );
      },
    );

    test(
      'normal body writes and deletion cannot bypass an existing buffer',
      () async {
        final parent = await create(target);
        final rich = await save(target, parent);
        expect(
          await target.replace(
            expected: rich.parent,
            body: document(),
            updatedAt: now,
          ),
          isNull,
        );
        expect(await target.discard(rich.parent), isFalse);
        expect(
          await target.replace(
            expected: parent,
            body: document(),
            updatedAt: now,
          ),
          isNull,
        );
        expect(await target.discard(parent), isFalse);
        expect(
          (await target.loadRichTextBuffer(key()))!.storageJson,
          rich.storageJson,
        );
      },
    );

    test(
      'replacement uses exact revision, body, metadata and raw buffer',
      () async {
        final parent = await create(target);
        final first = await save(target, parent);
        final nextValue = buffer(
          runs: [
            run('second', marks: ['italic']),
          ],
          base: 6,
          extent: 6,
        );
        final second = (await target.replaceRichTextBuffer(
          expected: first,
          buffer: nextValue,
          updatedAt: now,
        ))!;
        expect(second.parent.rowId, first.parent.rowId);
        expect(second.parent.revision, first.parent.revision + 1);
        expect(second.parent.bodyStorageJson, first.parent.bodyStorageJson);
        expect(second.buffer.text, 'second');
        expect(
          await target.replaceRichTextBuffer(
            expected: first,
            buffer: buffer(),
            updatedAt: now,
          ),
          isNull,
        );
        expect(
          await target.discardRichTextBuffer(expected: first, updatedAt: now),
          isNull,
        );
        expect(
          (await target.loadRichTextBuffer(key()))!.storageJson,
          second.storageJson,
        );
      },
    );

    test(
      'retargeting a stored buffer never abandons the previous input',
      () async {
        final saved = await save(target, await create(target));
        for (final next in [
          buffer(id: 'quote'),
          buffer(id: 'list', item: 0),
          buffer(id: 'list', item: 1),
        ]) {
          await expectLater(
            target.replaceRichTextBuffer(
              expected: saved,
              buffer: next,
              updatedAt: now,
            ),
            throwsArgumentError,
          );
        }
        expect(
          (await target.loadRichTextBuffer(key()))!.storageJson,
          saved.storageJson,
        );
      },
    );

    test(
      'apply atomically saves the body and clears only its buffer',
      () async {
        final parent = await create(target);
        final saved = await save(
          target,
          parent,
          value: buffer(
            runs: [
              run('changed', marks: ['bold'], href: '/next'),
            ],
          ),
        );
        final result = (await target.applyRichTextBuffer(
          expected: saved,
          updatedAt: now,
        ))!;
        expect(result.revision, saved.parent.revision + 1);
        expect(result.baseStorageJson, parent.baseStorageJson);
        expect(block(result.body, 'heading')['text'], 'changed');
        expect(block(result.body, 'heading')['inlines'], [
          {
            'text': 'changed',
            'marks': ['bold'],
            'href': '/next',
          },
        ]);
        expect(
          result.body.blocks.skip(1).toList(),
          parent.body.blocks.skip(1).toList(),
        );
        expect(await target.loadRichTextBuffer(key()), isNull);
        expect(
          (await target.load(key()))!.body.toJsonBlocks(),
          result.body.toJsonBlocks(),
        );
        expect(
          await target.applyRichTextBuffer(expected: saved, updatedAt: now),
          isNull,
        );
      },
    );

    test(
      'invalid apply leaves the buffer, body, timestamp and revision intact',
      () async {
        final value = buffer(runs: [run('')]);
        final saved = await save(target, await create(target), value: value);
        await expectLater(
          target.applyRichTextBuffer(
            expected: saved,
            updatedAt: now.add(const Duration(days: 1)),
          ),
          throwsFormatException,
        );
        final loaded = (await target.loadRichTextBuffer(key()))!;
        expect(loaded.storageJson, saved.storageJson);
        expect(loaded.parent.revision, saved.parent.revision);
        expect(loaded.parent.bodyStorageJson, saved.parent.bodyStorageJson);
        expect(loaded.parent.updatedAt, saved.parent.updatedAt);
      },
    );

    test(
      'discard preserves exact body and metadata while advancing revision',
      () async {
        final parent = await create(target);
        final saved = await save(target, parent, value: buffer(runs: []));
        final result = (await target.discardRichTextBuffer(
          expected: saved,
          updatedAt: now,
        ))!;
        expect(result.bodyStorageJson, parent.bodyStorageJson);
        expect(result.baseStorageJson, parent.baseStorageJson);
        expect(result.baseMetadataStorageJson, parent.baseMetadataStorageJson);
        expect(
          result.sessionMetadataStorageJson,
          parent.sessionMetadataStorageJson,
        );
        expect(result.revision, saved.parent.revision + 1);
        expect(await target.loadRichTextBuffer(key()), isNull);
        expect(
          await target.discardRichTextBuffer(expected: saved, updatedAt: now),
          isNull,
        );
      },
    );

    test('raw buffer mutation without a revision bump conflicts', () async {
      final saved = await save(target, await create(target));
      final envelope = jsonDecode(saved.storageJson) as Map<String, dynamic>;
      envelope['buffer'] = buffer(runs: [run('external')]).toJson();
      final changed = jsonEncode(envelope);
      await corrupt(db, 'text_buffer', changed);
      expect(
        await target.replaceRichTextBuffer(
          expected: saved,
          buffer: buffer(),
          updatedAt: now,
        ),
        isNull,
      );
      expect(
        await target.discardRichTextBuffer(expected: saved, updatedAt: now),
        isNull,
      );
      expect(
        await target.applyRichTextBuffer(expected: saved, updatedAt: now),
        isNull,
      );
      expect((await target.loadRichTextBuffer(key()))!.storageJson, changed);
    });

    test('forged raw versus decoded buffer mismatch is rejected', () async {
      final saved = await save(target, await create(target));
      final forged = StructuredRichTextBufferRecovery(
        parent: saved.parent,
        buffer: buffer(runs: [run('forged')]),
        storageJson: saved.storageJson,
      );
      await expectLater(
        target.replaceRichTextBuffer(
          expected: forged,
          buffer: buffer(),
          updatedAt: now,
        ),
        throwsFormatException,
      );
      await expectLater(
        target.applyRichTextBuffer(expected: forged, updatedAt: now),
        throwsFormatException,
      );
      await expectLater(
        target.discardRichTextBuffer(expected: forged, updatedAt: now),
        throwsFormatException,
      );
      expect(
        (await target.loadRichTextBuffer(key()))!.storageJson,
        saved.storageJson,
      );
    });

    test('forged parent body cannot replace the exact stored parent', () async {
      final saved = await save(target, await create(target));
      final parent = saved.parent;
      final forgedParent = StructuredBodyRecovery(
        key: parent.key,
        backendStorageKey: parent.backendStorageKey,
        rowId: parent.rowId,
        revision: parent.revision,
        base: parent.base,
        body: parent.body.move('image-two', 1),
        updatedAt: parent.updatedAt,
        baseStorageJson: parent.baseStorageJson,
        bodyStorageJson: parent.bodyStorageJson,
        baseMetadata: parent.baseMetadata,
        sessionMetadata: parent.sessionMetadata,
        baseMetadataStorageJson: parent.baseMetadataStorageJson,
        sessionMetadataStorageJson: parent.sessionMetadataStorageJson,
      );
      final forged = StructuredRichTextBufferRecovery(
        parent: forgedParent,
        buffer: saved.buffer,
        storageJson: saved.storageJson,
      );
      await expectLater(
        target.applyRichTextBuffer(expected: forged, updatedAt: now),
        throwsFormatException,
      );
      await expectLater(
        target.discardRichTextBuffer(expected: forged, updatedAt: now),
        throwsFormatException,
      );
      await expectLater(
        target.replaceRichTextBuffer(
          expected: forged,
          buffer: buffer(),
          updatedAt: now,
        ),
        throwsFormatException,
      );
      final after = (await target.loadRichTextBuffer(key()))!;
      expect(after.parent.bodyStorageJson, parent.bodyStorageJson);
      expect(after.storageJson, saved.storageJson);
    });

    test(
      'bad, unknown and oversized stored data never becomes absence',
      () async {
        final saved = await save(target, await create(target));
        for (final raw in [
          '{bad',
          '{}',
          'null',
          '{"schema":9}',
          'x' * 5600001,
        ]) {
          await corrupt(db, 'text_buffer', raw);
          await expectLater(
            target.loadRichTextBuffer(key()),
            throwsFormatException,
          );
          await expectLater(
            target.loadTextBuffer(key()),
            throwsFormatException,
          );
          await expectLater(target.load(key()), throwsFormatException);
          expect(await target.discard(saved.parent), isFalse);
          expect(
            await target.discardRichTextBuffer(expected: saved, updatedAt: now),
            isNull,
          );
        }
      },
    );

    test('damaged parent remains inaccessible and is not repaired', () async {
      await save(target, await create(target));
      await corrupt(db, 'body_blocks', '{bad');
      await expectLater(
        target.loadRichTextBuffer(key()),
        throwsFormatException,
      );
      await expectLater(target.load(key()), throwsFormatException);
      final row = await db
          .customSelect(
            'SELECT body_blocks, text_buffer FROM structured_body_drafts',
          )
          .getSingle();
      expect(row.read<String>('body_blocks'), '{bad');
      expect(row.read<String>('text_buffer'), isNotEmpty);
    });

    test(
      'backend, account, article and locale partition reads and writes',
      () async {
        final saved = await save(target, await create(target));
        for (final other in [
          key(user: 'other'),
          key(article: 'other'),
          key(locale: 'zh-TW'),
        ]) {
          expect(await target.loadRichTextBuffer(other), isNull);
        }
        final otherBackend = store(db, backend: 'https://two.example.invalid');
        expect(await otherBackend.loadRichTextBuffer(key()), isNull);
        expect(
          await otherBackend.replaceRichTextBuffer(
            expected: saved,
            buffer: buffer(),
            updatedAt: now,
          ),
          isNull,
        );
        expect(
          await otherBackend.applyRichTextBuffer(
            expected: saved,
            updatedAt: now,
          ),
          isNull,
        );
        expect(
          await otherBackend.discardRichTextBuffer(
            expected: saved,
            updatedAt: now,
          ),
          isNull,
        );
        expect(
          (await target.loadRichTextBuffer(key()))!.storageJson,
          saved.storageJson,
        );
      },
    );

    test(
      'parent raw changes without a revision bump cause a conflict',
      () async {
        final saved = await save(target, await create(target));
        final changed = jsonEncode(document().move('image-two', 1).blocks);
        await corrupt(db, 'body_blocks', changed);
        expect(
          await target.replaceRichTextBuffer(
            expected: saved,
            buffer: buffer(),
            updatedAt: now,
          ),
          isNull,
        );
        expect(
          await target.applyRichTextBuffer(expected: saved, updatedAt: now),
          isNull,
        );
        expect(
          await target.discardRichTextBuffer(expected: saved, updatedAt: now),
          isNull,
        );
        await expectLater(
          target.loadRichTextBuffer(key()),
          throwsFormatException,
        );
        final row = await db
            .customSelect(
              'SELECT body_blocks, text_buffer FROM structured_body_drafts',
            )
            .getSingle();
        expect(row.read<String>('body_blocks'), changed);
        expect(row.read<String>('text_buffer'), saved.storageJson);
      },
    );

    test(
      'reordered list cannot be reopened under the old item index',
      () async {
        final value = buffer(id: 'list', item: 0, runs: [run('replacement')]);
        final saved = await save(target, await create(target), value: value);
        final oldList = block(document(), 'list');
        final changed = document().replace('list', {
          ...oldList,
          'items': (oldList['items'] as List).reversed.toList(),
          'itemInlines': (oldList['itemInlines'] as List).reversed.toList(),
        });
        await corrupt(db, 'body_blocks', jsonEncode(changed.blocks));
        await expectLater(
          target.loadRichTextBuffer(key()),
          throwsFormatException,
        );
        expect(
          await target.applyRichTextBuffer(expected: saved, updatedAt: now),
          isNull,
        );
        expect(
          await target.discardRichTextBuffer(expected: saved, updatedAt: now),
          isNull,
        );
        final row = await db
            .customSelect(
              'SELECT body_blocks, text_buffer FROM structured_body_drafts',
            )
            .getSingle();
        expect(row.read<String>('body_blocks'), jsonEncode(changed.blocks));
        expect(row.read<String>('text_buffer'), saved.storageJson);
      },
    );

    test(
      'unknown envelope fields and changed source snapshot fail closed',
      () async {
        final saved = await save(target, await create(target));
        final base = jsonDecode(saved.storageJson) as Map<String, dynamic>;
        for (final changed in [
          {...base, 'extra': true},
          {...base, 'schema': 3},
          {...base, 'sourceVersion': 0},
          {...base, 'sourceHex': '00'},
          {...base, 'buffer': null},
        ]) {
          await corrupt(db, 'text_buffer', jsonEncode(changed));
          await expectLater(
            target.loadRichTextBuffer(key()),
            throwsFormatException,
          );
          await expectLater(target.load(key()), throwsFormatException);
          expect(
            await target.discardRichTextBuffer(expected: saved, updatedAt: now),
            isNull,
          );
        }
      },
    );

    test('wrong target cannot create a buffer or change the parent', () async {
      final parent = await create(target);
      for (final value in [
        buffer(id: 'paragraph'),
        buffer(id: 'image-one'),
        buffer(id: 'list', item: 2),
        buffer(id: 'missing'),
      ]) {
        await expectLater(
          target.createRichTextBuffer(
            expected: parent,
            buffer: value,
            updatedAt: now,
          ),
          throwsFormatException,
        );
      }
      expect(await target.loadRichTextBuffer(key()), isNull);
      expect((await target.load(key()))!.revision, parent.revision);
    });
  });

  group('restarts, races and row incarnation', () {
    test('intermediate survives database close and reopen exactly', () async {
      final directory = await Directory.systemTemp.createTemp('rich-buffer-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/recovery.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      final parent = await create(store(db));
      final high = String.fromCharCodes([0xd83d]);
      final value = buffer(
        runs: [
          run(high, marks: ['bold']),
          run('', href: '/x'),
        ],
        base: 1,
        extent: 0,
        composeStart: 0,
        composeEnd: 1,
      );
      final saved = await save(store(db), parent, value: value);
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final loaded = (await store(db).loadRichTextBuffer(key()))!;
      expect(loaded.storageJson, saved.storageJson);
      expect(loaded.parent.bodyStorageJson, parent.bodyStorageJson);
      expect(loaded.parent.baseStorageJson, parent.baseStorageJson);
      expect(loaded.buffer.runs[0].text.codeUnits, [0xd83d]);
      expect(loaded.buffer.runs[1].href, '/x');
      expect(loaded.buffer.selectionBase, 1);
      expect(loaded.buffer.composingEnd, 1);
    });

    test('two creates race on the exclusive slot without clobbering', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final first = store(db);
      final second = store(db);
      final parent = await create(first);
      final results = await Future.wait([
        first.createRichTextBuffer(
          expected: parent,
          buffer: buffer(runs: [run('first')]),
          updatedAt: now,
        ),
        second.createRichTextBuffer(
          expected: parent,
          buffer: buffer(runs: [run('second')]),
          updatedAt: now,
        ),
      ]);
      expect(
        results.whereType<StructuredRichTextBufferRecovery>(),
        hasLength(1),
      );
      expect(results.where((result) => result == null), hasLength(1));
      expect(
        (await first.loadRichTextBuffer(key()))!.storageJson,
        results
            .whereType<StructuredRichTextBufferRecovery>()
            .single
            .storageJson,
      );
    });

    test('two replacements race against the same raw revision', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final first = store(db);
      final second = store(db);
      final saved = await save(first, await create(first));
      final results = await Future.wait([
        first.replaceRichTextBuffer(
          expected: saved,
          buffer: buffer(runs: [run('first')]),
          updatedAt: now,
        ),
        second.replaceRichTextBuffer(
          expected: saved,
          buffer: buffer(runs: [run('second')]),
          updatedAt: now,
        ),
      ]);
      expect(
        results.whereType<StructuredRichTextBufferRecovery>(),
        hasLength(1),
      );
      expect(results.where((result) => result == null), hasLength(1));
      expect(
        (await first.loadRichTextBuffer(key()))!.storageJson,
        results
            .whereType<StructuredRichTextBufferRecovery>()
            .single
            .storageJson,
      );
    });

    test('delete and recreate produces a different row incarnation', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final target = store(db);
      final first = await save(target, await create(target));
      final cleared = (await target.discardRichTextBuffer(
        expected: first,
        updatedAt: now,
      ))!;
      expect(await target.discard(cleared), isTrue);
      final next = await save(
        target,
        await create(target),
        value: buffer(runs: [run('new')]),
      );
      expect(next.parent.rowId, isNot(first.parent.rowId));
      expect(
        await target.discardRichTextBuffer(expected: first, updatedAt: now),
        isNull,
      );
      expect(
        await target.applyRichTextBuffer(expected: first, updatedAt: now),
        isNull,
      );
      expect((await target.loadRichTextBuffer(key()))!.buffer.text, 'new');
    });
  });
}

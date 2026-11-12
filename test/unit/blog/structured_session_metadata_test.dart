import 'dart:convert';
import 'dart:typed_data';

import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredSessionMetadata metadata({
  String? slug = 'article-slug',
  String? title = 'Title',
  String? summary = 'Original summary',
  String? workType = 'essay',
  String? status = 'draft',
  StructuredTaxonomySelection? tags,
  StructuredTaxonomySelection? categories,
  StructuredCoverSelection? cover,
}) => StructuredSessionMetadata(
  slug: slug,
  title: title,
  summary: summary,
  workType: workType,
  publicationState: status,
  tags: tags,
  categories: categories,
  cover: cover,
);

void main() {
  group('metadata recovery format', () {
    test('round-trips fields and preserves exact whitespace and Unicode', () {
      final original = metadata(
        slug: 'article-slug',
        title: '  标题\n',
        summary: ' literal **summary** ',
        tags: StructuredTaxonomySelection(values: ['散文', 'one'], touched: true),
        categories: StructuredTaxonomySelection(
          values: ['category-1'],
          touched: false,
        ),
        cover: StructuredCoverSelection.remote('/media/cover.webp'),
      );
      final restored = StructuredSessionMetadata.decode(
        jsonEncode(original.toJson()),
      );
      expect(restored.slug, 'article-slug');
      expect(restored.title, '  标题\n');
      expect(restored.summary, ' literal **summary** ');
      expect(restored.workType, 'essay');
      expect(restored.publicationState, 'draft');
      expect(restored.tags?.values, ['散文', 'one']);
      expect(restored.tags?.touched, isTrue);
      expect(restored.categories?.values, ['category-1']);
      expect(restored.categories?.touched, isFalse);
      expect(restored.cover?.kind, StructuredCoverKind.remote);
      expect(restored.cover?.url, '/media/cover.webp');
      expect(restored.toJson(), original.toJson());
    });

    test('unknown is distinct from known empty text and empty selections', () {
      final unknown = metadata(
        slug: null,
        title: null,
        summary: null,
        workType: null,
        status: null,
      );
      final empty = metadata(
        slug: '',
        title: '',
        summary: '',
        workType: '',
        status: null,
        tags: StructuredTaxonomySelection(values: [], touched: true),
        categories: StructuredTaxonomySelection(values: [], touched: false),
        cover: StructuredCoverSelection.removed(),
      );
      final a = StructuredSessionMetadata.decode(jsonEncode(unknown.toJson()));
      final b = StructuredSessionMetadata.decode(jsonEncode(empty.toJson()));
      expect(a.slug, isNull);
      expect(a.title, isNull);
      expect(a.summary, isNull);
      expect(a.workType, isNull);
      expect(a.publicationState, isNull);
      expect(a.tags, isNull);
      expect(a.categories, isNull);
      expect(a.cover, isNull);
      expect(b.slug, '');
      expect(b.title, '');
      expect(b.summary, '');
      expect(b.workType, '');
      expect(b.tags?.values, isEmpty);
      expect(b.tags?.touched, isTrue);
      expect(b.categories?.values, isEmpty);
      expect(b.categories?.touched, isFalse);
      expect(b.cover?.kind, StructuredCoverKind.removed);
    });

    test('known draft, known published and unknown are not inferred', () {
      for (final status in [null, 'draft', 'published']) {
        final restored = StructuredSessionMetadata.decode(
          jsonEncode(metadata(status: status).toJson()),
        );
        expect(restored.publicationState, status);
      }
      for (final status in ['', 'scheduled', 'Draft', 'published ']) {
        expect(() => metadata(status: status), throwsFormatException);
      }
    });

    test('unrecognized or incomplete top-level fields fail closed', () {
      final source = metadata().toJson();
      for (final field in source.keys) {
        final missing = Map<String, Object?>.from(source)..remove(field);
        expect(
          () => StructuredSessionMetadata.parse(missing),
          throwsFormatException,
          reason: field,
        );
      }
      expect(
        () => StructuredSessionMetadata.parse({
          ...source,
          'future': 'preserve me',
        }),
        throwsFormatException,
      );
      for (final version in [null, 0, 2, '1', 1.0]) {
        expect(
          () => StructuredSessionMetadata.parse({...source, 'schema': version}),
          throwsFormatException,
        );
      }
      for (final value in [null, [], 'metadata', 1]) {
        expect(
          () => StructuredSessionMetadata.parse(value),
          throwsFormatException,
        );
      }
    });

    test('non-string values for known text fields fail closed', () {
      final source = metadata().toJson();
      for (final field in [
        'slug',
        'title',
        'summary',
        'workType',
        'publicationState',
      ]) {
        for (final value in [true, 4, [], {}]) {
          expect(
            () => StructuredSessionMetadata.parse({...source, field: value}),
            throwsFormatException,
            reason: '$field $value',
          );
        }
      }
    });

    test('text is bounded without trimming an in-progress edit', () {
      expect(metadata(title: 'x' * 20000).title, hasLength(20000));
      for (final field in ['slug', 'title', 'summary', 'workType']) {
        final source = metadata().toJson();
        expect(
          () =>
              StructuredSessionMetadata.parse({...source, field: 'x' * 20001}),
          throwsFormatException,
        );
      }
      expect(metadata(title: '  ').title, '  ');
    });

    test('decode rejects malformed or overly large JSON before parsing', () {
      expect(
        () => StructuredSessionMetadata.decode('{'),
        throwsFormatException,
      );
      expect(
        () => StructuredSessionMetadata.decode(
          'x' * (StructuredSessionMetadata.maxEncodedLength + 1),
        ),
        throwsFormatException,
      );
    });
  });

  group('taxonomy selections', () {
    test('selection copies the input and exposes an immutable list', () {
      final source = <String>['first', 'second'];
      final selection = StructuredTaxonomySelection(
        values: source,
        touched: true,
      );
      source[0] = 'later';
      source.add('third');
      expect(selection.values, ['first', 'second']);
      expect(() => selection.values.add('no'), throwsUnsupportedError);
      expect(selection.toJson(), {
        'values': ['first', 'second'],
        'touched': true,
      });
    });

    test('touched and untouched empty selections survive independently', () {
      final touched = StructuredTaxonomySelection.parse({
        'values': [],
        'touched': true,
      })!;
      final untouched = StructuredTaxonomySelection.parse({
        'values': [],
        'touched': false,
      })!;
      expect(touched.values, isEmpty);
      expect(untouched.values, isEmpty);
      expect(touched.touched, isTrue);
      expect(untouched.touched, isFalse);
      expect(StructuredTaxonomySelection.parse(null), isNull);
    });

    test('unknown, missing and ill-typed selection fields are rejected', () {
      final invalid = <Object?>[
        [],
        {},
        {'values': []},
        {'touched': true},
        {'values': [], 'touched': true, 'extra': 1},
        {
          'values': [null],
          'touched': true,
        },
        {
          'values': [1],
          'touched': true,
        },
        {'values': null, 'touched': true},
        {'values': [], 'touched': null},
        {'values': [], 'touched': 'true'},
      ];
      for (final value in invalid) {
        expect(
          () => StructuredTaxonomySelection.parse(value),
          throwsFormatException,
          reason: '$value',
        );
      }
    });

    test('limits count and element length without dropping values', () {
      final max = StructuredTaxonomySelection(
        values: List.filled(100, 'x' * 2048),
        touched: true,
      );
      expect(max.values, hasLength(100));
      expect(max.values.first, hasLength(2048));
      expect(
        () => StructuredTaxonomySelection(
          values: List.filled(101, 'x'),
          touched: false,
        ),
        throwsFormatException,
      );
      expect(
        () => StructuredTaxonomySelection(values: ['x' * 2049], touched: true),
        throwsFormatException,
      );
      expect(
        StructuredTaxonomySelection(
          values: ['', '  ', 'same', 'same'],
          touched: true,
        ).values,
        ['', '  ', 'same', 'same'],
      );
    });
  });

  group('cover selection', () {
    test('unknown, unchanged, removed and remote are distinct', () {
      expect(StructuredCoverSelection.parse(null), isNull);
      final unchanged = StructuredCoverSelection.parse({'kind': 'unchanged'})!;
      final removed = StructuredCoverSelection.parse({'kind': 'removed'})!;
      final remote = StructuredCoverSelection.parse({
        'kind': 'remote',
        'url': 'https://example.invalid/a',
      })!;
      expect(unchanged.kind, StructuredCoverKind.unchanged);
      expect(removed.kind, StructuredCoverKind.removed);
      expect(remote.kind, StructuredCoverKind.remote);
      expect(remote.url, 'https://example.invalid/a');
      expect(unchanged.bytes, isNull);
      expect(removed.url, isNull);
    });

    test(
      'local bytes survive, input and output mutation cannot change them',
      () {
        final bytes = Uint8List.fromList([0, 1, 2, 127, 128, 255]);
        final cover = StructuredCoverSelection.local(
          mimeType: 'image/png',
          bytes: bytes,
        );
        bytes[0] = 99;
        final exported = cover.bytes!;
        exported[1] = 99;
        expect(cover.bytes, [0, 1, 2, 127, 128, 255]);
        final restored = StructuredCoverSelection.parse(cover.toJson())!;
        expect(restored.kind, StructuredCoverKind.local);
        expect(restored.mimeType, 'image/png');
        expect(restored.bytes, [0, 1, 2, 127, 128, 255]);
        expect(restored.toJson(), cover.toJson());
        expect(restored.toJson()['byteLength'], 6);
        expect(
          StructuredCoverSelection.local(
            mimeType: 'image/png',
            bytes: utf8.encode('123456789'),
          ).toJson()['crc32'],
          'cbf43926',
        );
        final changedBytes = {
          ...cover.toJson(),
          'bytes': base64Encode([0, 1, 2, 127, 128, 254]),
        };
        expect(
          () => StructuredCoverSelection.parse(changedBytes),
          throwsFormatException,
        );
        expect(
          () => StructuredCoverSelection.parse({
            ...cover.toJson(),
            'byteLength': 5,
          }),
          throwsFormatException,
        );
        expect(
          () => StructuredCoverSelection.parse({
            ...cover.toJson(),
            'crc32': '00000000',
          }),
          throwsFormatException,
        );
      },
    );

    test('supported local MIME values round-trip without inventing a type', () {
      for (final mime in ['image/png', 'image/jpeg', 'image/webp']) {
        final cover = StructuredCoverSelection.local(
          mimeType: mime,
          bytes: [1, 2, 3],
        );
        expect(StructuredCoverSelection.parse(cover.toJson())?.mimeType, mime);
      }
    });

    test(
      'invalid MIME, empty or non-byte input fails rather than disappearing',
      () {
        for (final mime in [
          '',
          'image/gif',
          'IMAGE/PNG',
          'image/png; charset=utf-8',
        ]) {
          expect(
            () => StructuredCoverSelection.local(mimeType: mime, bytes: [1]),
            throwsFormatException,
          );
        }
        for (final bytes in [
          <int>[],
          [-1],
          [256],
          [1, -1],
        ]) {
          expect(
            () => StructuredCoverSelection.local(
              mimeType: 'image/png',
              bytes: bytes,
            ),
            throwsFormatException,
          );
        }
        expect(
          () => StructuredCoverSelection.local(
            mimeType: 'image/png',
            bytes: Uint8List(StructuredCoverSelection.maxImageBytes + 1),
          ),
          throwsFormatException,
        );
      },
    );

    test('URL credentials, network paths and unsafe schemes are rejected', () {
      for (final url in [
        '',
        '//host/x',
        'javascript:alert(1)',
        'https://user:pass@host/x',
        '/space here',
        '/a\\b',
      ]) {
        expect(
          () => StructuredCoverSelection.remote(url),
          throwsFormatException,
          reason: url,
        );
      }
      expect(StructuredCoverSelection.remote('/media/id').url, '/media/id');
      expect(
        StructuredCoverSelection.remote('https://host.example/x').url,
        'https://host.example/x',
      );
    });

    test('corrupt, missing or future cover shapes fail closed', () {
      final invalid = <Object?>[
        [],
        {},
        {'kind': 'future'},
        {'kind': null},
        {'kind': 'unchanged', 'url': '/x'},
        {'kind': 'removed', 'extra': true},
        {'kind': 'remote'},
        {'kind': 'remote', 'url': null},
        {'kind': 'local', 'mimeType': 'image/png'},
        {'kind': 'local', 'mimeType': null, 'bytes': 'AQ=='},
        {'kind': 'local', 'mimeType': 'image/png', 'bytes': null},
        {'kind': 'local', 'mimeType': 'image/png', 'bytes': ''},
        {'kind': 'local', 'mimeType': 'image/png', 'bytes': 'not base64!'},
        {'kind': 'local', 'mimeType': 'image/png', 'bytes': 'AQ'},
      ];
      for (final value in invalid) {
        expect(
          () => StructuredCoverSelection.parse(value),
          throwsFormatException,
          reason: '$value',
        );
      }
    });
  });
}

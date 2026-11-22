import 'dart:convert';
import 'dart:typed_data';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/notion_import/notion_image_upload.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_plan.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_source.dart';
import 'package:belog/features/blog/domain/notion_import/notion_local_images.dart';
import 'package:belog/features/blog/domain/notion_import/notion_page_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

const _fence = NowaveSessionFence(userId: 'user', generation: 1);

Map<String, Object?> _image(String key) => {
  'type': 'image',
  'image': {
    'type': 'external',
    'external': {'url': notionLocalImageUrl(key)},
  },
};

Map<String, Object?> _page(
  String id, {
  List<String> english = const [],
  List<String> images = const [],
}) => {
  'id': id,
  'properties': {
    if (english.isNotEmpty)
      'English': {
        'relation': [
          for (final link in english) {'id': link},
        ],
      },
  },
  'blocks': [for (final key in images) _image(key)],
};

NotionBundle _bundle(List<Map<String, Object?>> pages) => NotionBundle.parse(
  jsonEncode({
    'version': 1,
    'database': {'id': 'db'},
    'pages': pages,
  }),
);

final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
]);

NotionLocalImage _local(String name, Uint8List Function() read) =>
    NotionLocalImage(name: name, size: 8, read: read);

class _Repository implements NotionImportRepository {
  final uploads = <String>[];
  final answers = <Either<Failure, String>>[];

  @override
  Future<Either<Failure, String>> uploadImage({
    required Uint8List bytes,
    required String contentType,
    required NowaveSessionFence sessionFence,
  }) async {
    uploads.add(contentType);
    if (answers.isNotEmpty) return answers.removeAt(0);
    return right('/api/media/${uploads.length}');
  }

  @override
  Future<Either<Failure, NotionImportReport>> submit({
    required NotionBundle bundle,
    required bool apply,
    required NowaveSessionFence sessionFence,
    NotionImportPlan? plan,
  }) => throw UnimplementedError();
}

void main() {
  group('NotionPageSelection', () {
    test('pairs pages through English in both directions', () {
      final selection = NotionPageSelection.of(
        _bundle([
          _page('a-1', english: ['B1']),
          _page('b1'),
          _page('c'),
        ]),
      );

      expect(selection.all, {0, 1, 2});
      // IDs match without case or dashes, the way Notion writes them.
      expect(selection.partnersOf(0), {1});
      expect(selection.partnersOf(1), {0});
      expect(selection.partnersOf(2), isEmpty);
      expect(selection.partnersOf(9), isEmpty);
    });

    test('a page never pairs with itself or with a missing page', () {
      final selection = NotionPageSelection.of(
        _bundle([
          _page('a', english: ['a', 'gone']),
        ]),
      );

      expect(selection.partnersOf(0), isEmpty);
    });

    test('toggling a page takes its partners along', () {
      final selection = NotionPageSelection.of(
        _bundle([
          _page('a', english: ['b']),
          _page('b'),
          _page('c'),
        ]),
      );

      expect(selection.toggle({2}, 0, include: true), {0, 1, 2});
      expect(selection.toggle({0, 1, 2}, 1, include: false), {2});
      final current = {2};
      selection.toggle(current, 0, include: true);
      expect(current, {2}, reason: 'the given set is not changed');
    });

    test('knows which local images the selected pages use', () {
      final selection = NotionPageSelection.of(
        _bundle([
          _page('a', images: ['A/x.png', 'A/y.png']),
          _page('b', images: ['A/y.png']),
          _page('c'),
        ]),
      );

      expect(selection.imagesOf({0}), {'A/x.png', 'A/y.png'});
      expect(selection.imagesOf({1, 2}), {'A/y.png'});
      expect(selection.imagesOf({}), isEmpty);
      expect(NotionPageSelection.empty.imagesOf({0}), isEmpty);
    });
  });

  group('NotionImageUploader', () {
    test('uploads each image once and skips what cannot go', () async {
      final repository = _Repository();
      final uploader = NotionImageUploader(
        repository: repository,
        fence: _fence,
      );
      final progress = <(int, int)>[];
      final images = {
        'A/ok.png': _local('A/ok.png', () => _png),
        'A/text.png': _local('A/text.png', () => Uint8List.fromList([1, 2])),
        'A/broken.png': _local(
          'A/broken.png',
          () => throw const NotionImportSourceException(
            NotionImportSourceError.invalidZip,
          ),
        ),
      };

      final outcome = await uploader.upload(
        ['A/ok.png', 'A/text.png', 'A/broken.png', 'A/absent.png'],
        images,
        stillWanted: () => true,
        onProgress: (done, total) => progress.add((done, total)),
      );

      expect(outcome, isA<NotionImagesUploaded>());
      final uploaded = outcome as NotionImagesUploaded;
      expect(uploaded.urls, {'A/ok.png': '/api/media/1'});
      expect(uploaded.skipped, ['text.png', 'broken.png', 'absent.png']);
      expect(repository.uploads, ['image/png']);
      expect(progress, [(1, 4), (2, 4), (3, 4), (4, 4)]);

      // A second preview reuses the address instead of uploading again.
      final again = await uploader.upload(
        ['A/ok.png'],
        images,
        stillWanted: () => true,
      );
      expect((again as NotionImagesUploaded).urls, {
        'A/ok.png': '/api/media/1',
      });
      expect(repository.uploads, hasLength(1));

      // Another account's addresses are not reused.
      uploader.forget();
      await uploader.upload(['A/ok.png'], images, stillWanted: () => true);
      expect(repository.uploads, hasLength(2));
    });

    test('an image refused as invalid is skipped; the rest still go', () async {
      final repository = _Repository()
        ..answers.add(
          left(
            const Failure(
              'animated',
              kind: FailureKind.validation,
              code: 'server.BAD_USER_INPUT',
            ),
          ),
        );
      final uploader = NotionImageUploader(
        repository: repository,
        fence: _fence,
      );

      final outcome = await uploader.upload(
        ['A/one.png', 'A/two.png'],
        {
          'A/one.png': _local('A/one.png', () => _png),
          'A/two.png': _local(
            'A/two.png',
            () => Uint8List.fromList([..._png, 1]),
          ),
        },
        stillWanted: () => true,
      );

      final uploaded = outcome as NotionImagesUploaded;
      expect(uploaded.skipped, ['one.png']);
      expect(uploaded.urls, {'A/two.png': '/api/media/2'});
    });

    test('any other failure stops without retrying', () async {
      final repository = _Repository()..answers.add(left(Failure.timeout()));
      final uploader = NotionImageUploader(
        repository: repository,
        fence: _fence,
      );

      final outcome = await uploader.upload(
        ['A/one.png', 'A/two.png'],
        {
          'A/one.png': _local('A/one.png', () => _png),
          'A/two.png': _local('A/two.png', () => _png),
        },
        stillWanted: () => true,
      );

      expect(outcome, isA<NotionImageUploadStopped>());
      expect(repository.uploads, hasLength(1));
    });

    test('stops quietly when the result is no longer wanted', () async {
      final repository = _Repository();
      final uploader = NotionImageUploader(
        repository: repository,
        fence: _fence,
      );

      final outcome = await uploader.upload(
        ['A/one.png', 'A/two.png'],
        {
          'A/one.png': _local('A/one.png', () => _png),
          'A/two.png': _local('A/two.png', () => _png),
        },
        stillWanted: () => false,
      );

      expect(outcome, isA<NotionImageUploadAbandoned>());
      expect(repository.uploads, hasLength(1));
    });

    test('the content key tells different bytes and names apart', () {
      final a = NotionImageUploader.contentKey('a.png', _png);
      expect(NotionImageUploader.contentKey('a.png', _png), a);
      expect(NotionImageUploader.contentKey('b.png', _png), isNot(a));
      expect(
        NotionImageUploader.contentKey('a.png', Uint8List.fromList([1])),
        isNot(a),
      );
    });
  });
}

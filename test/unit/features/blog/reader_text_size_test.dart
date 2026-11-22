import 'dart:async';
import 'dart:io';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/reader/sqlite_reader_text_size_store.dart';
import 'package:belog/features/blog/domain/reader/reader_text_size.dart';
import 'package:belog/features/blog/presentation/viewer/reader_text_size_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// A store whose read finishes only when the test says so, and whose writes
/// can be made to fail.
class _SlowStore implements ReaderTextSizeStore {
  final read = Completer<ReaderTextSize>();
  final saved = <ReaderTextSize>[];
  bool failSaves = false;
  int loads = 0;

  @override
  Future<ReaderTextSize> load() {
    loads++;
    return read.future;
  }

  @override
  Future<void> save(ReaderTextSize size) async {
    if (failSaves) throw StateError('disk full');
    saved.add(size);
  }
}

void main() {
  group('ReaderTextSize', () {
    test('reads its stored name back, and anything else as standard', () {
      for (final size in ReaderTextSize.values) {
        expect(ReaderTextSize.parse(size.name), size);
      }
      expect(ReaderTextSize.parse(null), ReaderTextSize.standard);
      expect(ReaderTextSize.parse('enormous'), ReaderTextSize.standard);
    });

    test('every step has a body size, growing, with standard at 1', () {
      expect(
        NoWaveTypeScale.readerBodySizes,
        hasLength(ReaderTextSize.values.length),
      );
      for (var i = 1; i < ReaderTextSize.values.length; i++) {
        expect(
          readerBodySize(ReaderTextSize.values[i]),
          greaterThan(readerBodySize(ReaderTextSize.values[i - 1])),
        );
      }
      expect(readerTextFactor(ReaderTextSize.standard), 1);
      expect(
        readerBodySize(ReaderTextSize.standard),
        NoWaveTypeScale.articleBody,
      );
    });
  });

  group('ReaderTextSizeController', () {
    test('starts at standard and takes the saved size once loaded', () async {
      final store = _SlowStore();
      final controller = ReaderTextSizeController(store);
      addTearDown(controller.dispose);

      expect(controller.value, ReaderTextSize.standard);
      final loading = controller.load();
      // A second caller shares the first read.
      unawaited(controller.load());
      store.read.complete(ReaderTextSize.large);
      await loading;

      expect(controller.value, ReaderTextSize.large);
      expect(store.loads, 1);
      expect(store.saved, isEmpty);
    });

    test('a choice made while the saved size is read wins', () async {
      final store = _SlowStore();
      final controller = ReaderTextSizeController(store);
      addTearDown(controller.dispose);

      final loading = controller.load();
      controller.select(ReaderTextSize.small);
      store.read.complete(ReaderTextSize.largest);
      await loading;

      expect(controller.value, ReaderTextSize.small);
      expect(store.saved, [ReaderTextSize.small]);
    });

    test('choosing the current size writes nothing', () async {
      final store = _SlowStore();
      final controller = ReaderTextSizeController(store);
      addTearDown(controller.dispose);

      controller.select(ReaderTextSize.standard);
      await Future<void>.delayed(Duration.zero);

      expect(store.saved, isEmpty);
    });

    test('a failed read or write leaves the size usable', () async {
      final store = _SlowStore()..failSaves = true;
      final controller = ReaderTextSizeController(store);
      addTearDown(controller.dispose);

      final loading = controller.load();
      store.read.completeError(StateError('locked'));
      await loading;
      expect(controller.value, ReaderTextSize.standard);

      controller.select(ReaderTextSize.extraLarge);
      await Future<void>.delayed(Duration.zero);
      expect(controller.value, ReaderTextSize.extraLarge);
    });
  });

  test(
    'the SQLite store defaults to standard and survives reopening',
    () async {
      final dir = await Directory.systemTemp.createTemp('reader-text-size-');
      final file = File('${dir.path}/app.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      try {
        await db.writeMetadata('other_preference', 'keep');
        expect(
          await SqliteReaderTextSizeStore(db).load(),
          ReaderTextSize.standard,
        );
        await SqliteReaderTextSizeStore(db).save(ReaderTextSize.extraLarge);
        await db.close();

        db = AppDatabase(NativeDatabase(file));
        expect(
          await SqliteReaderTextSizeStore(db).load(),
          ReaderTextSize.extraLarge,
        );
        expect(await db.readMetadata('other_preference'), 'keep');
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}

import 'dart:async';
import 'dart:io';

import 'package:belog/core/config/app_durations.dart';
import 'package:belog/core/config/app_limits.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_comment_draft_store.dart';
import 'package:belog/features/blog/domain/repositories/comment_draft_store.dart';
import 'package:belog/features/blog/presentation/comments/comment_draft_keeper.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drafts in memory, per account and article, that can hold back its loads.
class _Store implements CommentDraftStore {
  final saved = <String, CommentDraft>{};
  final saves = <String>[];
  Completer<void>? gate;
  bool failLoad = false;
  bool failSave = false;

  @override
  Future<CommentDraft?> load({
    required String userId,
    required String slug,
  }) async {
    final wait = gate;
    if (wait != null) await wait.future;
    if (failLoad) throw StateError('disk');
    return saved['$userId/$slug'];
  }

  @override
  Future<void> save({
    required String userId,
    required String slug,
    required CommentDraft draft,
  }) async {
    saves.add('$userId/$slug:${draft.text}');
    if (failSave) throw StateError('disk');
    if (draft.isBlank) {
      saved.remove('$userId/$slug');
    } else {
      saved['$userId/$slug'] = draft;
    }
  }
}

/// A comment box without a widget: just the text and the reply target.
class _Box {
  CommentDraft value = const CommentDraft(text: '');
  late CommentDraftKeeper keeper;

  void type(String text) {
    value = CommentDraft(
      text: text,
      parentCommentId: value.parentCommentId,
      parentAuthorName: value.parentAuthorName,
    );
    keeper.changed();
  }
}

_Box _box(_Store store, {String slug = 'patrol'}) {
  final box = _Box();
  box.keeper = CommentDraftKeeper(
    store,
    slug: slug,
    read: () => box.value,
    apply: (draft) => box.value = draft,
  );
  return box;
}

void main() {
  group('CommentDraftKeeper', () {
    late _Store store;

    setUp(() => store = _Store());

    testWidgets('puts the signed-in reader\'s draft back in an empty box', (
      tester,
    ) async {
      store.saved['ann/patrol'] = const CommentDraft(
        text: 'half a thought',
        parentCommentId: 'c1',
        parentAuthorName: 'Bo',
      );
      final box = _box(store)..keeper.follow('ann');
      await tester.pump();
      expect(box.value.text, 'half a thought');
      expect(box.value.parentCommentId, 'c1');
      expect(box.keeper.showsRestored, isTrue);
      // Putting it back is not typing: nothing is written.
      await tester.pump(AppDurations.commentDraftSave * 2);
      expect(store.saves, isEmpty);

      box.type('half a thought, finished');
      expect(box.keeper.showsRestored, isFalse);
      box.keeper.dispose();
    });

    testWidgets('keeps typing after the quiet moment, once', (tester) async {
      final box = _box(store)..keeper.follow('ann');
      await tester.pump();
      box
        ..type('h')
        ..type('he')
        ..type('hello');
      await tester.pump(AppDurations.commentDraftSave ~/ 2);
      expect(store.saves, isEmpty);
      await tester.pump(AppDurations.commentDraftSave);
      expect(store.saves, ['ann/patrol:hello']);
    });

    testWidgets('flush keeps it at once; a blank box removes the draft', (
      tester,
    ) async {
      final box = _box(store)..keeper.follow('ann');
      await tester.pump();
      box.type('hello');
      box.keeper.flush();
      await tester.pump();
      expect(store.saved['ann/patrol']?.text, 'hello');

      box.type('');
      box.keeper.flush();
      await tester.pump();
      expect(store.saved, isEmpty);
      // Nothing changed since: a second flush writes nothing.
      box.keeper.flush();
      await tester.pump();
      expect(store.saves, hasLength(2));
    });

    testWidgets('never overwrites what was typed while the draft was read', (
      tester,
    ) async {
      store
        ..saved['ann/patrol'] = const CommentDraft(text: 'old')
        ..gate = Completer<void>();
      final box = _box(store)..keeper.follow('ann');
      box.type('new');
      store.gate!.complete();
      await tester.pump();
      expect(box.value.text, 'new');
      expect(box.keeper.showsRestored, isFalse);
      box.keeper.dispose();
    });

    testWidgets('a picked reply target also counts as started', (tester) async {
      store
        ..saved['ann/patrol'] = const CommentDraft(text: 'old')
        ..gate = Completer<void>();
      final box = _box(store)..keeper.follow('ann');
      box.value = const CommentDraft(text: '', parentCommentId: 'c9');
      store.gate!.complete();
      await tester.pump();
      expect(box.value.text, isEmpty);
      expect(box.value.parentCommentId, 'c9');
    });

    testWidgets('switching accounts keeps each reader\'s draft their own', (
      tester,
    ) async {
      store.saved['bo/patrol'] = const CommentDraft(text: 'bo wrote');
      final box = _box(store)..keeper.follow('ann');
      await tester.pump();
      box.type('ann wrote');

      box.keeper.follow('bo');
      await tester.pump();
      // Ann's unsaved typing went to Ann, and Bo sees only Bo's.
      expect(store.saved['ann/patrol']?.text, 'ann wrote');
      expect(box.value.text, 'bo wrote');
      expect(store.saved['bo/patrol']?.text, 'bo wrote');

      box.keeper.follow(null);
      await tester.pump();
      expect(box.value.text, isEmpty);
      expect(box.keeper.owner, isNull);
      // A guest's box is not kept.
      box.type('guest');
      await tester.pump(AppDurations.commentDraftSave * 2);
      expect(store.saves, ['ann/patrol:ann wrote']);
    });

    testWidgets('a slow read for the previous reader never lands', (
      tester,
    ) async {
      store
        ..saved['ann/patrol'] = const CommentDraft(text: 'ann wrote')
        ..gate = Completer<void>();
      final box = _box(store)..keeper.follow('ann');
      box.keeper.follow('bo');
      store.gate!.complete();
      await tester.pump();
      expect(box.value.text, isEmpty);
    });

    testWidgets('storage failures are logged, not thrown', (tester) async {
      store
        ..saved['ann/patrol'] = const CommentDraft(text: 'x')
        ..failLoad = true
        ..failSave = true;
      final box = _box(store)..keeper.follow('ann');
      await tester.pump();
      expect(box.value.text, isEmpty);
      box.type('y');
      box.keeper.flush();
      await tester.pump();
      expect(store.saves, ['ann/patrol:y']);
    });

    testWidgets('dispose keeps the last typing and then stops', (tester) async {
      final box = _box(store)..keeper.follow('ann');
      await tester.pump();
      box.type('last words');
      box.keeper.dispose();
      await tester.pump();
      expect(store.saved['ann/patrol']?.text, 'last words');
      box.type('after');
      await tester.pump(AppDurations.commentDraftSave * 2);
      expect(store.saves, hasLength(1));
    });

    testWidgets('silently changes the box without it counting as typing', (
      tester,
    ) async {
      final box = _box(store)..keeper.follow('ann');
      await tester.pump();
      box.keeper.silently(() => box.type('the app did this'));
      await tester.pump(AppDurations.commentDraftSave * 2);
      expect(store.saves, isEmpty);
    });
  });

  group('SqliteCommentDraftStore', () {
    late Directory dir;
    late AppDatabase db;
    late SqliteCommentDraftStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('belog-comment-drafts-');
      db = AppDatabase(NativeDatabase(File('${dir.path}/drafts.sqlite')));
      store = SqliteCommentDraftStore(
        db,
        apiBaseUrl: Uri.parse('https://api.example.invalid'),
      );
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('round-trips a reply per account and article', () async {
      const reply = CommentDraft(
        text: '巡逻队的结尾\n第二行',
        parentCommentId: 'c1',
        parentAuthorName: 'Bo',
      );
      await store.save(userId: 'ann', slug: 'patrol', draft: reply);
      await store.save(
        userId: 'ann',
        slug: 'wall',
        draft: const CommentDraft(text: 'top level'),
      );
      expect(await store.load(userId: 'ann', slug: 'patrol'), reply);
      expect(
        await store.load(userId: 'ann', slug: 'wall'),
        const CommentDraft(text: 'top level'),
      );
      expect(await store.load(userId: 'bo', slug: 'patrol'), isNull);
    });

    test('another backend does not see the drafts', () async {
      await store.save(
        userId: 'ann',
        slug: 'patrol',
        draft: const CommentDraft(text: 'x'),
      );
      final other = SqliteCommentDraftStore(
        db,
        apiBaseUrl: Uri.parse('https://other.example.invalid'),
      );
      expect(await other.load(userId: 'ann', slug: 'patrol'), isNull);
    });

    test(
      'a blank draft removes it, and the last one removes the row',
      () async {
        await store.save(
          userId: 'ann',
          slug: 'patrol',
          draft: const CommentDraft(text: 'x'),
        );
        await store.save(
          userId: 'ann',
          slug: 'patrol',
          draft: const CommentDraft(text: '  \n'),
        );
        expect(await store.load(userId: 'ann', slug: 'patrol'), isNull);
        expect(await db.readMetadata(store.keyFor('ann')), isNull);
      },
    );

    test('keeps the newest drafts up to the limit', () async {
      for (var i = 0; i < AppLimits.commentDrafts + 2; i++) {
        await store.save(
          userId: 'ann',
          slug: 'a$i',
          draft: CommentDraft(text: 'd$i'),
        );
      }
      // Writing an old one again makes it the newest.
      await store.save(
        userId: 'ann',
        slug: 'a2',
        draft: const CommentDraft(text: 'again'),
      );
      expect(await store.load(userId: 'ann', slug: 'a0'), isNull);
      expect(await store.load(userId: 'ann', slug: 'a1'), isNull);
      expect((await store.load(userId: 'ann', slug: 'a2'))?.text, 'again');
      expect(await store.load(userId: 'ann', slug: 'a3'), isNotNull);
      expect(
        await store.load(
          userId: 'ann',
          slug: 'a${AppLimits.commentDrafts + 1}',
        ),
        isNotNull,
      );
    });

    test('writes issued together all land', () async {
      await Future.wait([
        for (var i = 0; i < 5; i++)
          store.save(
            userId: 'ann',
            slug: 'a$i',
            draft: CommentDraft(text: 'd$i'),
          ),
      ]);
      for (var i = 0; i < 5; i++) {
        expect((await store.load(userId: 'ann', slug: 'a$i'))?.text, 'd$i');
      }
    });

    test('a damaged or foreign value reads as no draft', () async {
      await db.writeMetadata(store.keyFor('ann'), 'not json');
      expect(await store.load(userId: 'ann', slug: 'patrol'), isNull);
      await db.writeMetadata(store.keyFor('ann'), '{"a":1}');
      expect(await store.load(userId: 'ann', slug: 'patrol'), isNull);
      await db.writeMetadata(
        store.keyFor('ann'),
        '[3, {"slug": "patrol"}, {"slug": "", "text": "x"}, '
        '{"slug": "patrol", "text": "kept", "parent": ""}, '
        '{"slug": "patrol", "text": "shadowed"}]',
      );
      expect(
        await store.load(userId: 'ann', slug: 'patrol'),
        const CommentDraft(text: 'kept'),
      );
      // A write starts from what could be read, not from the damage.
      await store.save(
        userId: 'ann',
        slug: 'wall',
        draft: const CommentDraft(text: 'w'),
      );
      expect((await store.load(userId: 'ann', slug: 'patrol'))?.text, 'kept');
    });
  });
}

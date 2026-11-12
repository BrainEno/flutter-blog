import 'dart:async';
import 'dart:io';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/structured_article_fixtures.dart';

class _Identity implements NowaveSessionIdentity {
  @override
  String? get activeUserId => 'author';
  @override
  String? get accessToken => 'token';
  @override
  int get sessionGeneration => 1;
  @override
  Stream<void> get identityChanges => const Stream.empty();
}

class _Reader implements StructuredEditionReader {
  _Reader(this.result);
  StructuredEditionReadResult result;
  @override
  Future<StructuredEditionReadResult> read({
    required StructuredBodyKey key,
    required NowaveSessionFence fence,
  }) async => result;
}

final _key = StructuredBodyKey(
  userId: 'author',
  articleId: 'article-uuid',
  locale: 'en',
);
const _fence = NowaveSessionFence(userId: 'author', generation: 1);
final _backend = Uri.parse('https://restart.example');

StructuredArticleDraft _body() {
  final article = structuredArticle();
  return StructuredArticleDraft.parse(
    version: article['contentBlocksVersion'],
    blocks: article['contentBlocks'],
  );
}

StructuredSessionMetadata _metadata() => StructuredSessionMetadata(
  slug: 'slug',
  title: 'title',
  summary: '',
  workType: 'other',
  publicationState: 'draft',
  tags: null,
  categories: null,
  cover: StructuredCoverSelection.local(
    mimeType: 'image/webp',
    bytes: [1, 2, 255],
  ),
);

LocalStructuredSession _session(AppDatabase db, _Reader reader) {
  final store = SqliteStructuredBodyRecoveryStore(db, apiBaseUrl: _backend);
  final identity = _Identity();
  return LocalStructuredSession(
    key: _key,
    fence: _fence,
    opener: OpenStructuredEditingSession(
      reader: reader,
      store: store,
      identity: identity,
    ),
    now: () => DateTime.utc(2026),
  );
}

StructuredEditionReadResult _remote() => StructuredEditionReadResult.found(
  StructuredEdition(
    key: _key,
    body: _body(),
    metadata: _metadata(),
    rawArticle: {'id': 'article-uuid'},
    metadataIssues: const {},
  ),
);

void main() {
  test(
    'local body, inline data, metadata and cover survive a database restart offline',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'structured-session-restart-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/sessions.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      final reader = _Reader(_remote());
      final first = _session(db, reader);
      await first.open();
      first.edit(
        (body) => body.setTextRunLink('heading', 0, 'https://example.com/new'),
      );
      first.edit(
        (body) => body.replacePlainText('paragraph', 'recovered after restart'),
      );
      expect(await first.flush(), LocalStructuredFlushResult.saved);
      expect(await first.close(), isTrue);
      await db.close();

      reader.result = const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.unavailable,
      );
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final second = _session(db, reader);
      await second.open();
      expect(second.state.phase, LocalStructuredPhase.recoveryChoice);
      expect(
        second.state.baseComparison,
        StructuredBaseComparison.remoteUnavailable,
      );
      expect(second.resumeRecovery(), isTrue);
      final blocks = second.state.body!.toJsonBlocks();
      expect(blocks.first['id'], 'heading');
      expect(
        (blocks.first['inlines'] as List).first['href'],
        'https://example.com/new',
      );
      expect(
        blocks.firstWhere((block) => block['id'] == 'paragraph')['text'],
        'recovered after restart',
      );
      expect(
        blocks.firstWhere((block) => block['id'] == 'image-one')['alt'],
        'First image alt',
      );
      expect(
        blocks.firstWhere((block) => block['id'] == 'image-one')['caption'],
        'First caption',
      );
      expect(second.state.metadata!.cover!.bytes, [1, 2, 255]);
      expect(await second.close(), isTrue);
    },
  );

  test(
    'corrupt persisted recovery blocks remote initialization after restart',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'structured-session-corrupt-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/sessions.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      final reader = _Reader(_remote());
      final first = _session(db, reader);
      await first.open();
      first.edit((body) => body.replacePlainText('paragraph', 'local edit'));
      expect(await first.flush(), LocalStructuredFlushResult.saved);
      expect(await first.close(), isTrue);
      await db.customStatement(
        "UPDATE structured_body_drafts SET body_blocks = 'not-json'",
      );
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final second = _session(db, reader);
      await second.open();
      expect(second.state.phase, LocalStructuredPhase.localReadFailed);
      expect(second.state.body, isNull);
      expect(second.edit((body) => body), isFalse);
      final rows = await db
          .customSelect('SELECT body_blocks FROM structured_body_drafts')
          .get();
      expect(rows.single.read<String>('body_blocks'), 'not-json');
      expect(await second.close(), isTrue);
    },
  );
}

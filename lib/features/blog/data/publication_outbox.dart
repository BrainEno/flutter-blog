import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/storage/sqlite_publication_outbox.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/data/datasources/nowave_article_codec.dart';
import 'package:belog/features/blog/domain/entities/queued_publication.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// Foreground worker for explicitly requested publications. Ordinary drafts
/// never enter this service. No background OS job is registered.
///
/// The server has no capability negotiation for article idempotency or
/// media cleanup. An ambiguous article/media POST is paused rather than
/// automatically repeated. An article can be reconciled by its stable slug.
class PublicationOutbox extends ChangeNotifier with WidgetsBindingObserver {
  PublicationOutbox({
    required this.store,
    required this.client,
    required this.sessions,
    required this.appUser,
    required this.connection,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SqlitePublicationOutbox store;
  final NowaveApiClient client;
  final NowaveSessionManager sessions;
  final AppUserCubit appUser;
  final ConnectionChecker connection;
  final DateTime Function() _now;

  static const int maxAttempts = 3;
  static const Duration pollInterval = Duration(seconds: 30);

  StreamSubscription<AppUserState>? _userSubscription;
  StreamSubscription<NowaveAuthStatus>? _sessionSubscription;
  Timer? _timer;
  Future<void>? _running;
  bool _started = false;
  bool _disposed = false;
  bool _runAgain = false;
  bool? online;

  /// Recovers interrupted operations before enabling the worker.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await store.recoverInterrupted();
    if (_disposed) return;
    WidgetsBinding.instance.addObserver(this);
    _userSubscription = appUser.stream.listen((_) => kick());
    _sessionSubscription = sessions.statusStream.listen((_) => kick());
    _timer = Timer.periodic(pollInterval, (_) => kick());
    _changed();
    kick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) kick();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_userSubscription?.cancel());
    unawaited(_sessionSubscription?.cancel());
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Capture a new, owner-scoped intent only after explicit user consent.
  Future<QueuedPublication> enqueue({
    required String ownerId,
    required String title,
    required String content,
    required List<String> tags,
    Uint8List? coverBytes,
    String? coverMime,
  }) async {
    if (!_isOwner(ownerId)) throw StateError('The current account changed.');
    final item = await store.enqueue(
      ownerId: ownerId,
      title: title,
      content: content,
      tags: tags,
      coverBytes: coverBytes,
      coverMime: coverMime,
    );
    _changed();
    kick();
    return item;
  }

  Future<List<QueuedPublication>> list(String ownerId) async {
    if (!_isOwner(ownerId)) return const [];
    final items = await store.list(ownerId);
    return _isOwner(ownerId) ? items : const [];
  }

  Future<bool> retry(
    String ownerId,
    String id, {
    bool acceptMediaReupload = false,
  }) async {
    if (!_isOwner(ownerId)) return false;
    final result = await store.retry(
      ownerId,
      id,
      acceptMediaReupload: acceptMediaReupload,
    );
    _changed();
    if (result) kick();
    return result;
  }

  Future<bool> edit(
    String ownerId,
    String id, {
    required String title,
    required String content,
    required List<String> tags,
  }) async {
    if (!_isOwner(ownerId)) return false;
    final result = await store.edit(
      ownerId,
      id,
      title: title,
      content: content,
      tags: tags,
    );
    _changed();
    return result;
  }

  Future<bool> removeCover(
    String ownerId,
    String id, {
    bool acceptPossibleOrphan = false,
  }) async {
    if (!_isOwner(ownerId)) return false;
    final result = await store.removeCover(
      ownerId,
      id,
      acceptPossibleOrphan: acceptPossibleOrphan,
    );
    _changed();
    return result;
  }

  Future<bool> remove(
    String ownerId,
    String id, {
    bool acceptPossibleOrphan = false,
  }) async {
    if (!_isOwner(ownerId)) return false;
    final result = await store.remove(
      ownerId,
      id,
      acceptPossibleOrphan: acceptPossibleOrphan,
    );
    _changed();
    return result;
  }

  void kick() {
    if (!_started || _disposed) return;
    if (_running != null) {
      _runAgain = true;
      return;
    }
    unawaited(processNow());
  }

  /// Exposed so an explicit retry and tests can wait for a completed pass.
  Future<void> processNow() async {
    if (_disposed) return;
    final running = _running;
    if (running != null) return running;
    final pass = _drain();
    _running = pass;
    try {
      await pass;
    } catch (error, stackTrace) {
      AppLogger.error(
        'publication outbox pass failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _running = null;
      if (_runAgain && !_disposed) {
        _runAgain = false;
        kick();
      }
    }
  }

  Future<void> _drain() async {
    final state = appUser.state;
    if (state is! AppUserLoggedIn) return;
    final ownerId = state.user.id;
    if (!_isOwner(ownerId)) return;
    // Do not continuously probe connectivity for users with no queued work.
    if (!await store.hasQueued(ownerId)) {
      if (online != null) {
        online = null;
        _changed();
      }
      return;
    }
    if (!_isOwner(ownerId) || _disposed) return;
    final connected = await connection.isConnected;
    if (online != connected) {
      online = connected;
      _changed();
    }
    if (!connected || _disposed) return;
    while (!_disposed && _isOwner(ownerId)) {
      final item = await store.claimNext(ownerId);
      if (item == null) return;
      _changed();
      await _attempt(item);
      _changed();
    }
  }

  Future<void> _attempt(QueuedPublication original) async {
    final ownerId = original.ownerId;
    final id = original.id;
    try {
      // An earlier attempt may have been interrupted before its result was
      // persisted. Never repeat its POST against an unverified deployment.
      if (original.phase == PublicationPhase.articleSending) {
        await store.failAttempt(ownerId, id, code: 'article.outcomeUnknown');
        return;
      }
      _validateBeforeMedia(original);
      final tagIds = <String>[];
      for (final name
          in original.tags
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .toSet()) {
        final auth = await _verifiedSession(ownerId);
        _requireCurrent(auth, ownerId);
        final data = await client.postJson(
          '/tags',
          {'name': name},
          authenticate: false,
          extraHeaders: auth.headers,
        );
        if (data is! Map ||
            data['id'] is! String ||
            (data['id'] as String).isEmpty) {
          throw const FormatException('Invalid tag response.');
        }
        final tagId = data['id'] as String;
        if (!tagIds.contains(tagId)) tagIds.add(tagId);
      }

      var item = (await store.get(ownerId, id))!;
      if (item.hasCover && item.remoteCoverUrl == null) {
        final bytes = await store.readCover(ownerId, id);
        if (bytes == null || bytes.isEmpty || item.coverMime == null) {
          throw const _ValidationFailure('media.missing');
        }
        final auth = await _verifiedSession(ownerId);
        if (!await store.beginMedia(ownerId, id)) return;
        _requireCurrent(auth, ownerId);
        final asset = await client.uploadMedia(
          bytes,
          item.coverMime!,
          authenticate: false,
          extraHeaders: auth.headers,
        );
        if (asset.id.isEmpty) {
          throw const FormatException('Invalid media response.');
        }
        if (!await store.saveUploadedMedia(
          ownerId,
          id,
          client.mediaUri(asset.id).toString(),
        )) {
          return;
        }
        item = (await store.get(ownerId, id))!;
      }

      final auth = await _verifiedSession(ownerId);
      final slug = 'belog-$id';
      final requestJson =
          item.requestJson ??
          jsonEncode(<String, dynamic>{
            'slug': slug,
            'title': item.title,
            'contentBlocks': blogToContentBlocks(
              content: item.content,
              coverUrl: item.remoteCoverUrl,
            ),
            'contentBlocksVersion': 0,
            'publish': true,
            'locale': 'zh-CN',
            if (tagIds.isNotEmpty) 'tagIds': tagIds,
          });
      if (!await store.beginArticle(ownerId, id, requestJson)) return;
      _requireCurrent(auth, ownerId);
      final response = await client.postJson(
        '/articles',
        jsonDecode(requestJson),
        authenticate: false,
        extraHeaders: {
          ...auth.headers,
          'Idempotency-Key': 'belog-publication-$id',
        },
      );
      if (response is! Map ||
          response['slug'] != slug ||
          response['authorId'] != ownerId) {
        throw const FormatException(
          'Article confirmation did not match the intent.',
        );
      }
      await store.markPublished(ownerId, id, slug);
    } catch (error) {
      await _handleFailure(ownerId, id, error);
    }
  }

  void _validateBeforeMedia(QueuedPublication item) {
    if (item.title.trim().isEmpty ||
        item.title.length > 250 ||
        item.content.trim().isEmpty) {
      throw const _ValidationFailure('article.validation');
    }
    final blocks = blogToContentBlocks(
      content: item.content,
      coverUrl: item.hasCover ? 'https://example.invalid/cover' : null,
    );
    if (blocks.length > 200 || jsonEncode(blocks).length > 1000000) {
      throw const _ValidationFailure('article.validation');
    }
  }

  Future<void> _handleFailure(String ownerId, String id, Object error) async {
    final item = await store.get(ownerId, id);
    if (item == null || item.status != PublicationStatus.uploading) return;
    final isAuth =
        error is _OwnerUnavailable ||
        (error is NowaveApiException &&
            (error.statusCode == 401 || error.statusCode == 403));
    final isValidation =
        error is _ValidationFailure ||
        (error is NowaveApiException &&
            (error.statusCode == 400 ||
                error.statusCode == 413 ||
                error.statusCode == 415));
    final code = isAuth
        ? 'auth.ownerUnavailable'
        : isValidation
        ? 'article.validation'
        : _isNetwork(error)
        ? 'network.unavailable'
        : 'server.unavailable';

    if (item.phase == PublicationPhase.mediaSending) {
      // _OwnerUnavailable is thrown synchronously before invoking the POST.
      // Other transport/server errors may occur after the asset was stored.
      if (error is _OwnerUnavailable || isAuth || isValidation) {
        await store.failAttempt(
          ownerId,
          id,
          code: isValidation ? 'media.validation' : code,
          phase: PublicationPhase.ready,
        );
      } else {
        await store.failAttempt(
          ownerId,
          id,
          code: 'media.outcomeUnknown',
          phase: PublicationPhase.mediaUncertain,
        );
      }
      return;
    }
    if (item.phase == PublicationPhase.articleSending) {
      if (error is _OwnerUnavailable || isAuth || isValidation) {
        await store.rejectArticle(ownerId, id, code);
      } else {
        await store.failAttempt(ownerId, id, code: 'article.outcomeUnknown');
      }
      return;
    }
    if (error is _OwnerUnavailable) {
      // A revoked/expired session must not cause a tight claim/retry loop.
      await store.failAttempt(ownerId, id, code: 'auth.ownerUnavailable');
      return;
    }
    final retryable =
        !isAuth &&
        !isValidation &&
        (error is! NowaveApiException ||
            error.statusCode == 429 ||
            error.statusCode >= 500);
    DateTime? retryAt;
    if (retryable && item.attemptCount < maxAttempts) {
      final seconds = item.attemptCount == 1 ? 10 : 60;
      final requested = error is NowaveApiException
          ? error.retryAfterSeconds ?? 0
          : 0;
      final delay = requested > seconds
          ? requested.clamp(seconds, 900).toInt()
          : seconds;
      retryAt = _now().toUtc().add(Duration(seconds: delay));
    }
    await store.failAttempt(
      ownerId,
      id,
      code: error is _ValidationFailure ? error.code : code,
      retryAt: retryAt,
    );
  }

  bool _isNetwork(Object error) =>
      error is SocketException ||
      error is HttpException ||
      error is TimeoutException ||
      error is http.ClientException;

  bool _isOwner(String ownerId) {
    final state = appUser.state;
    final session = sessions.currentSession;
    return ownerId.isNotEmpty &&
        state is AppUserLoggedIn &&
        state.user.id == ownerId &&
        session?.userId == ownerId;
  }

  Future<_VerifiedSession> _verifiedSession(String ownerId) async {
    var session = sessions.currentSession;
    if (!_isOwner(ownerId) || session == null) throw const _OwnerUnavailable();
    if (!session.accessExpiresAt.isAfter(
      _now().add(const Duration(seconds: 30)),
    )) {
      await sessions.ensureFreshAccess();
      session = sessions.currentSession;
    }
    if (!_isOwner(ownerId) ||
        session == null ||
        session.accessToken.isEmpty ||
        !session.accessExpiresAt.isAfter(_now())) {
      throw const _OwnerUnavailable();
    }
    final auth = _VerifiedSession(session);
    // Do not trust the cached user id alone. Verify the actor for this exact
    // captured token; disable the client's automatic refresh/401 retry.
    final data = await client.getJson(
      '/me',
      authenticate: false,
      extraHeaders: auth.headers,
    );
    _requireCurrent(auth, ownerId);
    if (data is! Map || data['id'] != ownerId) throw const _OwnerUnavailable();
    return auth;
  }

  void _requireCurrent(_VerifiedSession auth, String ownerId) {
    if (!_isOwner(ownerId) ||
        !identical(sessions.currentSession, auth.session) ||
        !auth.session.accessExpiresAt.isAfter(_now())) {
      throw const _OwnerUnavailable();
    }
  }

  /// Check an ambiguous article against a published server representation.
  /// Failure/404 is not proof that it was never created, so this method
  /// never resends, edits or deletes the uncertain intent.
  Future<bool> reconcile(String ownerId, String id) async {
    if (!_isOwner(ownerId)) return false;
    final item = await store.get(ownerId, id);
    if (item == null ||
        !item.articleOutcomeUncertain ||
        item.requestJson == null) {
      return false;
    }
    try {
      final auth = await _verifiedSession(ownerId);
      final request = (jsonDecode(item.requestJson!) as Map)
          .cast<String, dynamic>();
      final slug = request['slug'];
      if (slug is! String || slug != 'belog-$id') return false;
      _requireCurrent(auth, ownerId);
      final data = await client.getJson(
        '/articles/$slug',
        query: {'locale': 'zh-CN'},
        authenticate: false,
        extraHeaders: auth.headers,
      );
      _requireCurrent(auth, ownerId);
      if (data is! Map ||
          data['slug'] != slug ||
          data['authorId'] != ownerId ||
          data['title'] != request['title'] ||
          !_matches(request['contentBlocks'], data['contentBlocks'])) {
        return false;
      }
      final expectedTags = (request['tagIds'] as List? ?? const [])
          .cast<String>()
          .toSet();
      final actualTags = (data['tags'] as List? ?? const [])
          .whereType<Map>()
          .map((tag) => tag['id'])
          .whereType<String>()
          .toSet();
      if (expectedTags.length != actualTags.length ||
          !expectedTags.containsAll(actualTags)) {
        return false;
      }
      final confirmed = await store.markReconciled(ownerId, id, slug);
      _changed();
      return confirmed;
    } catch (_) {
      return false;
    }
  }

  bool _matches(Object? expected, Object? actual) {
    if (expected is Map && actual is Map) {
      return expected.keys.every(
        (key) =>
            actual.containsKey(key) && _matches(expected[key], actual[key]),
      );
    }
    if (expected is List && actual is List) {
      return expected.length == actual.length &&
          List.generate(
            expected.length,
            (i) => _matches(expected[i], actual[i]),
          ).every((match) => match);
    }
    return expected == actual;
  }
}

class _VerifiedSession {
  const _VerifiedSession(this.session);
  final NowaveSessionData session;
  Map<String, String> get headers => {
    'authorization': 'Bearer ${session.accessToken}',
  };
}

class _OwnerUnavailable implements Exception {
  const _OwnerUnavailable();
}

class _ValidationFailure implements Exception {
  const _ValidationFailure(this.code);
  final String code;
}

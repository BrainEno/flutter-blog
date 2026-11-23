import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/config/app_limits.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:flutter/foundation.dart';

/// The reading history as the article lists see it: how far the signed-in
/// reader got with each article they opened, so a row in the feed, a search
/// result or a saved article can say "42% read" or "Finished".
///
/// It is the app's [ReadingHistoryStore]: every write the reader, the
/// history page and sign-out make passes through here on its way to
/// [_history], so a mark changes the moment the position is saved, with no
/// polling and no second query per row. On an account change it drops the
/// old reader's marks at once and reads the new reader's most recent
/// history (the same bounded page the history page shows).
///
/// Marks are a courtesy: a failed read leaves the lists unmarked, never
/// broken. Listeners hear only changes a list would show - a position that
/// moves within the same whole percentage is silent - so the rows under an
/// open article do not rebuild on every scroll.
class ReadingMarks extends ChangeNotifier
    implements ReadingHistoryStore, UnattributedHistoryMaintenance {
  ReadingMarks(this._history, {required AppUserCubit users}) {
    _subscription = users.stream.listen(_follow);
    _follow(users.state);
  }

  final ReadingHistoryStore _history;
  late final StreamSubscription<AppUserState> _subscription;

  /// Whose marks [_progress] holds; null for a guest, who has no history.
  String? _userId;

  /// Bumped on every account change, so a slow read for the previous
  /// account cannot land in the new one's marks.
  int _generation = 0;
  final Map<String, double> _progress = {};
  bool _disposed = false;

  /// How far the signed-in reader got with [blogId], from 0 to 1; null
  /// when they never opened it (or no one is signed in).
  double? progressFor(String blogId) => _progress[blogId];

  void _follow(AppUserState state) {
    final userId = state is AppUserLoggedIn && state.user.id.isNotEmpty
        ? state.user.id
        : null;
    if (userId == _userId) return;
    _userId = userId;
    final generation = ++_generation;
    if (_progress.isNotEmpty) {
      _progress.clear();
      notifyListeners();
    }
    if (userId != null) unawaited(_load(userId, generation));
  }

  Future<void> _load(String userId, int generation) async {
    final List<ReadingHistoryEntry> entries;
    try {
      entries = await _history.list(userId: userId);
    } catch (_) {
      // The history page reports its own failures; here the lists simply
      // stay unmarked.
      return;
    }
    if (_disposed || generation != _generation) return;
    var changed = false;
    for (final entry in entries) {
      final progress = entry.progress;
      // A position saved while this read was in flight is newer.
      if (progress == null || _progress.containsKey(entry.blogId)) continue;
      _progress[entry.blogId] = progress;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _mark(String userId, String blogId, double? progress) {
    if (_disposed || userId != _userId) return;
    final before = _progress[blogId];
    if (progress == null) {
      _progress.remove(blogId);
    } else {
      _progress[blogId] = progress;
    }
    if (!_sameMark(before, progress)) notifyListeners();
  }

  /// Whether a list would show [a] and [b] the same way.
  static bool _sameMark(double? a, double? b) {
    final stage = ReadingProgress.stageOf(a);
    if (stage != ReadingProgress.stageOf(b)) return false;
    if (stage != ReadingStage.partway) return true;
    return (a! * 100).round() == (b! * 100).round();
  }

  @override
  Future<void> record({required String userId, required Blog blog}) =>
      _history.record(userId: userId, blog: blog);

  @override
  Future<List<ReadingHistoryEntry>> list({
    required String userId,
    int limit = AppLimits.readingHistoryPageSize,
  }) => _history.list(userId: userId, limit: limit);

  @override
  Future<void> saveProgress({
    required String userId,
    required String blogId,
    required double progress,
  }) async {
    await _history.saveProgress(
      userId: userId,
      blogId: blogId,
      progress: progress,
    );
    _mark(userId, blogId, progress);
  }

  @override
  Future<double?> progressOf({
    required String userId,
    required String blogId,
  }) => _history.progressOf(userId: userId, blogId: blogId);

  @override
  Future<void> remove({required String userId, required String blogId}) async {
    await _history.remove(userId: userId, blogId: blogId);
    _mark(userId, blogId, null);
  }

  @override
  Future<void> clear({required String userId}) async {
    await _history.clear(userId: userId);
    if (_disposed || userId != _userId || _progress.isEmpty) return;
    _progress.clear();
    notifyListeners();
  }

  @override
  Future<bool> hasUnattributedHistory() async {
    final history = _history;
    return history is UnattributedHistoryMaintenance &&
        await history.hasUnattributedHistory();
  }

  @override
  Future<void> clearUnattributedHistory() async {
    final history = _history;
    if (history is UnattributedHistoryMaintenance) {
      await history.clearUnattributedHistory();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

import 'dart:async';

import 'package:belog/core/config/app_durations.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/domain/repositories/comment_draft_store.dart';

/// Keeps the comment box of one article in step with its saved draft.
///
/// The box belongs to whoever is signed in ([follow]): their unsent comment
/// is read back into an empty box, and what they type is kept a moment
/// after they stop ([changed]) - or at once when they leave the article or
/// the app ([flush]). A guest has no drafts.
///
/// Changes the app makes itself - putting a saved draft back, emptying the
/// box for the next account - go through [silently], so they are never
/// mistaken for the reader's typing and written under the wrong account.
/// Storage failures are logged; the box keeps working.
class CommentDraftKeeper {
  CommentDraftKeeper(
    this._store, {
    required this.slug,
    required this.read,
    required this.apply,
  });

  final CommentDraftStore _store;

  /// The article the box is under.
  final String slug;

  /// The box as it is now.
  final CommentDraft Function() read;

  /// Puts [CommentDraft] in the box: text and reply target. A blank draft
  /// empties it.
  final void Function(CommentDraft draft) apply;

  String? _owner;
  Timer? _timer;
  bool _dirty = false;
  bool _muted = false;
  bool _disposed = false;

  /// Bumped on every restore and owner change, so a slow read cannot land
  /// after a newer one or in another account's box.
  int _generation = 0;
  CommentDraft? _restored;

  /// Whose drafts the box holds now; null for a guest.
  String? get owner => _owner;

  /// Whether the box still shows exactly the draft that was put back, so
  /// the page can say so (and offer to throw it away).
  bool get showsRestored {
    final restored = _restored;
    if (restored == null) return false;
    final now = read();
    return now.text == restored.text &&
        now.parentCommentId == restored.parentCommentId;
  }

  /// The signed-in reader is now [userId]: what the previous one typed is
  /// kept for them and taken out of the box, and [userId]'s draft is read.
  void follow(String? userId) {
    if (_disposed || userId == _owner) return;
    flush();
    final previous = _owner;
    _owner = userId;
    _restored = null;
    if (previous != null) silently(() => apply(const CommentDraft(text: '')));
    restore();
  }

  /// Reads the owner's draft into the box, unless something has been typed
  /// in the meantime.
  void restore() {
    final owner = _owner;
    final generation = ++_generation;
    if (_disposed || owner == null) return;
    unawaited(_restore(owner, generation));
  }

  Future<void> _restore(String owner, int generation) async {
    final CommentDraft? draft;
    try {
      draft = await _store.load(userId: owner, slug: slug);
    } catch (e, stackTrace) {
      AppLogger.error(
        'reading a comment draft failed',
        error: e,
        stackTrace: stackTrace,
      );
      return;
    }
    if (_disposed ||
        generation != _generation ||
        owner != _owner ||
        draft == null ||
        draft.isBlank ||
        _touched(read())) {
      return;
    }
    final restored = draft;
    _restored = restored;
    silently(() => apply(restored));
  }

  /// Whether the reader has started something of their own: typed, or
  /// picked a comment to answer. A saved draft never overwrites that.
  static bool _touched(CommentDraft box) =>
      !box.isBlank || box.parentCommentId != null;

  /// The reader changed the box: keep it after a quiet moment.
  void changed() {
    if (_disposed || _muted || _owner == null) return;
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(AppDurations.commentDraftSave, flush);
  }

  /// Runs [change] without it counting as the reader's.
  void silently(void Function() change) {
    final wasMuted = _muted;
    _muted = true;
    try {
      change();
    } finally {
      _muted = wasMuted;
    }
  }

  /// Keeps what is in the box now, if the reader changed it since the last
  /// write. A blank box removes the draft.
  void flush() {
    _timer?.cancel();
    _timer = null;
    final owner = _owner;
    if (!_dirty || owner == null) return;
    _dirty = false;
    unawaited(_save(owner, read()));
  }

  Future<void> _save(String owner, CommentDraft draft) async {
    try {
      await _store.save(userId: owner, slug: slug, draft: draft);
    } catch (e, stackTrace) {
      AppLogger.error(
        'saving a comment draft failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Keeps any unsaved typing and stops.
  void dispose() {
    if (_disposed) return;
    flush();
    _disposed = true;
  }
}

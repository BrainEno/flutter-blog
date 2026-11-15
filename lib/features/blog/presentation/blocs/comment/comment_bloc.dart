import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/comments/comment_edit_guard.dart';
import 'package:belog/features/blog/domain/repositories/comment_repository.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_event.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_edit_result.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

/// Loads a viewer page's comment thread and handles submit/delete (issue
/// #19).
///
/// Submits carry the server's `Idempotency-Key`: one key is minted per
/// logical comment. When a submit fails and the composer is retried with
/// the same text (and the same reply target), the pending key is reused so
/// the server replays the original work instead of posting twice; any
/// change of content or target mints a fresh key.
class CommentBloc extends Bloc<CommentEvent, CommentState> {
  final GetComments getComments;
  final CreateComment createComment;
  final DeleteComment deleteComment;
  final Uuid uuid;
  final NowaveSessionIdentity? sessionIdentity;
  final EditComment? editComment;
  final Map<String, Object> _editing = {};
  StreamSubscription<void>? _identitySubscription;
  int _identityEpoch = 0;

  /// Composer limit; the server enforces its own body cap and rejects
  /// anything beyond it.
  static const maxContentLength = 2000;

  /// Slug of the article whose thread this bloc manages.
  final String slug;

  CommentBloc({
    required this.getComments,
    required this.createComment,
    required this.deleteComment,
    required this.slug,
    Uuid? uuidGenerator,
    NowaveSessionIdentity? sessionIdentity,
    this.editComment,
  }) : sessionIdentity = sessionIdentity ?? createComment.sessionIdentity,
       uuid = uuidGenerator ?? const Uuid(),
       super(const CommentState()) {
    on<CommentsRequested>(_onCommentsRequested);
    on<MoreCommentsRequested>(_onMoreCommentsRequested);
    on<CommentSubmitted>(_onCommentSubmitted);
    on<CommentDeleteRequested>(_onCommentDeleteRequested);
    on<CommentIdentityChanged>(_onIdentityChanged);
    on<CommentEditApplied>(_onEditApplied);
    _identitySubscription = this.sessionIdentity?.identityChanges.listen((_) {
      _identityEpoch++;
      _pageGeneration++;
      _clearPending();
      _editing.clear();
      if (!isClosed) add(CommentIdentityChanged(_identityEpoch));
    });
  }

  /// Captured synchronously at event admission, before a queued handler can
  /// observe a newer account. Missing identity always fails closed.
  NowaveSessionFence? captureFence() {
    final identity = sessionIdentity;
    final user = identity?.activeUserId;
    if (identity == null ||
        user == null ||
        user.isEmpty ||
        (identity.accessToken?.isEmpty ?? true)) {
      return null;
    }
    return NowaveSessionFence(
      userId: user,
      generation: identity.sessionGeneration,
    );
  }

  bool _current(NowaveSessionFence? fence, int epoch) {
    final identity = sessionIdentity;
    return fence != null &&
        identity != null &&
        epoch == _identityEpoch &&
        identity.activeUserId == fence.userId &&
        identity.sessionGeneration == fence.generation &&
        !(identity.accessToken?.isEmpty ?? true);
  }

  @override
  void add(CommentEvent event) {
    if ((event is CommentSubmitted || event is CommentDeleteRequested) &&
        state.identityEpoch != _identityEpoch) {
      return;
    }
    if (event is CommentSubmitted && event.fence == null) {
      event = CommentSubmitted(
        content: event.content,
        parentCommentId: event.parentCommentId,
        fence: captureFence(),
      );
    } else if (event is CommentDeleteRequested && event.fence == null) {
      event = CommentDeleteRequested(event.commentId, fence: captureFence());
    }
    super.add(event);
  }

  void _onIdentityChanged(
    CommentIdentityChanged event,
    Emitter<CommentState> emit,
  ) {
    if (event.epoch != _identityEpoch) return;
    _nextCursor = null;
    emit(
      state.copyWith(
        identityEpoch: event.epoch,
        submitting: false,
        deletingIds: const {},
        isLoadingMore: false,
        error: '',
        hasMore: false,
        clearLoadMoreFailure: true,
      ),
    );
    add(const CommentsRequested());
  }

  @override
  Future<void> close() async {
    await _identitySubscription?.cancel();
    return super.close();
  }

  String? _pendingKey;
  String? _pendingContent;
  String? _pendingParent;
  String? _nextCursor;
  int _pageGeneration = 0;

  Future<void> _onCommentsRequested(
    CommentsRequested event,
    Emitter<CommentState> emit,
  ) async {
    final generation = ++_pageGeneration;
    _nextCursor = null;
    emit(
      state.copyWith(
        status: CommentListStatus.loading,
        comments: const [],
        error: '',
        hasMore: false,
        isLoadingMore: false,
        clearLoadMoreFailure: true,
        paginationUnavailable: false,
      ),
    );
    final result = await getComments(slug);
    if (emit.isDone || generation != _pageGeneration) return;
    result.fold(
      (failure) => emit(
        state.copyWith(
          status: CommentListStatus.failure,
          error: _messageFor(failure, fallback: '评论加载失败，请稍后重试'),
          failure: _withCode(failure, 'comments.load'),
        ),
      ),
      (page) {
        _nextCursor = page.nextCursor;
        emit(
          state.copyWith(
            status: CommentListStatus.loaded,
            comments: page.items,
            error: '',
            hasMore: page.hasMore,
            isLoadingMore: false,
            clearLoadMoreFailure: true,
            paginationUnavailable: false,
          ),
        );
      },
    );
  }

  Future<void> _onMoreCommentsRequested(
    MoreCommentsRequested event,
    Emitter<CommentState> emit,
  ) async {
    final current = state;
    final cursor = _nextCursor;
    if (current.status != CommentListStatus.loaded ||
        cursor == null ||
        !current.hasMore ||
        current.isLoadingMore ||
        current.paginationUnavailable) {
      return;
    }

    final generation = _pageGeneration;
    emit(current.copyWith(isLoadingMore: true, clearLoadMoreFailure: true));
    final result = await getComments(slug, cursor: cursor);
    if (emit.isDone || generation != _pageGeneration) return;
    final latest = state;
    if (latest.status != CommentListStatus.loaded) return;

    result.fold(
      (failure) {
        if (failure.code == commentCursorUnavailableFailureCode) {
          _nextCursor = null;
          emit(
            latest.copyWith(
              isLoadingMore: false,
              hasMore: false,
              clearLoadMoreFailure: true,
              paginationUnavailable: true,
            ),
          );
          return;
        }
        emit(latest.copyWith(isLoadingMore: false, loadMoreFailure: failure));
      },
      (page) {
        // A locally submitted root can also arrive in a later server page when
        // its sort key is beyond the saved cursor. Drop only repeated IDs; keep
        // the cursor moving and append any unseen roots from that page.
        final newRoots = _newRootComments(latest.comments, page.items);
        if (page.nextCursor == cursor ||
            (newRoots.isEmpty && page.nextCursor != null)) {
          // Older deployments may ignore `cursor` and return a page that makes
          // no progress. Stop rather than looping or duplicating rows.
          _nextCursor = null;
          emit(
            latest.copyWith(
              isLoadingMore: false,
              hasMore: false,
              clearLoadMoreFailure: true,
              paginationUnavailable: true,
            ),
          );
          return;
        }

        if (newRoots.isEmpty) {
          _nextCursor = null;
          emit(
            latest.copyWith(
              isLoadingMore: false,
              hasMore: false,
              clearLoadMoreFailure: true,
              paginationUnavailable: false,
            ),
          );
          return;
        }

        _nextCursor = page.nextCursor;
        emit(
          latest.copyWith(
            comments: _sortRoots([...latest.comments, ...newRoots]),
            isLoadingMore: false,
            hasMore: page.hasMore,
            clearLoadMoreFailure: true,
          ),
        );
      },
    );
  }

  static List<Comment> _newRootComments(
    List<Comment> current,
    List<Comment> next,
  ) {
    final seen = current.map((comment) => comment.id).toSet();
    return next.where((comment) => seen.add(comment.id)).toList();
  }

  static List<Comment> _sortRoots(List<Comment> comments) {
    return comments..sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  }

  Future<void> _onCommentSubmitted(
    CommentSubmitted event,
    Emitter<CommentState> emit,
  ) async {
    final fence = event.fence;
    final epoch = _identityEpoch;
    if (!_current(fence, epoch)) return;
    final content = event.content.trim();
    if (content.isEmpty || state.submitting) {
      return;
    }
    if (content.length > maxContentLength) {
      emit(
        state.copyWith(
          error: '评论太长了（最多 $maxContentLength 字）',
          failure: Failure(
            '评论太长了（最多 $maxContentLength 字）',
            kind: FailureKind.validation,
            code: 'comments.tooLong',
          ),
        ),
      );
      return;
    }

    // Retry of the same logical submit reuses the pending idempotency key
    // so the server replays the original comment on success and never
    // duplicates it.
    final samePending =
        _pendingKey != null &&
        _pendingContent == content &&
        _pendingParent == event.parentCommentId;
    if (!samePending) {
      _pendingKey = uuid.v4();
      _pendingContent = content;
      _pendingParent = event.parentCommentId;
    }

    emit(state.copyWith(submitting: true, error: ''));
    final result = await createComment(
      CreateCommentParams(
        slug: slug,
        content: content,
        parentCommentId: event.parentCommentId,
        idempotencyKey: _pendingKey!,
        sessionFence: fence,
      ),
    );
    if (emit.isDone || !_current(fence, epoch)) return;
    await result.fold(
      (failure) async {
        // Keep the pending key: a retry of the unchanged text replays the
        // same idempotent request.
        emit(
          state.copyWith(
            submitting: false,
            error: _messageFor(failure, fallback: '评论发送失败，请稍后重试'),
            failure: _withCode(failure, 'comments.send'),
          ),
        );
      },
      (comment) async {
        _clearPending();
        emit(
          state.copyWith(
            submitting: false,
            error: '',
            comments: _insertComment(state.comments, comment),
          ),
        );
      },
    );
  }

  Future<void> _onCommentDeleteRequested(
    CommentDeleteRequested event,
    Emitter<CommentState> emit,
  ) async {
    final fence = event.fence;
    final epoch = _identityEpoch;
    if (!_current(fence, epoch)) return;
    if (state.deletingIds.contains(event.commentId) ||
        _editing.containsKey(event.commentId)) {
      return;
    }
    emit(
      state.copyWith(
        deletingIds: {...state.deletingIds, event.commentId},
        error: '',
      ),
    );
    final result = await deleteComment(event.commentId, sessionFence: fence);
    if (emit.isDone || !_current(fence, epoch)) return;
    final remaining = {...state.deletingIds}..remove(event.commentId);
    await result.fold(
      (failure) async {
        emit(
          state.copyWith(
            deletingIds: remaining,
            error: _messageFor(failure, fallback: '评论删除失败，请稍后重试'),
            failure: _withCode(failure, 'comments.delete'),
          ),
        );
      },
      (_) async {
        emit(
          state.copyWith(
            deletingIds: remaining,
            error: '',
            comments: _removeComment(state.comments, event.commentId),
          ),
        );
      },
    );
  }

  /// Save one explicitly plain-text comment. The snapshot check catches local
  /// changes before sending; it is NOT a server-side compare-and-swap. Other
  /// devices can still write between this check and the PATCH.
  Future<CommentEditResult> editPlainComment({
    required Comment original,
    required String text,
    required NowaveSessionFence fence,
  }) async {
    final epoch = _identityEpoch;
    if (isClosed || !_current(fence, epoch)) {
      return const CommentEditResult(CommentEditStatus.sessionChanged);
    }
    final content = text.trim();
    final current = CommentEditGuard.find(state.comments, original.id);
    if (current == null ||
        !CommentEditGuard.sameSnapshot(current, original) ||
        original.authorId != fence.userId ||
        !CommentEditGuard.canEdit(original, maxLength: maxContentLength) ||
        state.deletingIds.contains(original.id) ||
        _editing.containsKey(original.id) ||
        content.isEmpty ||
        content == original.content ||
        content.length > maxContentLength) {
      return const CommentEditResult(CommentEditStatus.stale);
    }
    final token = Object();
    _editing[original.id] = token;
    try {
      final result =
          await (editComment ?? EditComment(createComment.commentRepository))(
            commentId: original.id,
            content: content,
            sessionFence: fence,
          );
      if (isClosed || !_current(fence, epoch)) {
        return const CommentEditResult(CommentEditStatus.sessionChanged);
      }
      return result.fold<CommentEditResult>(
        (failure) => CommentEditResult(
          failure.code == 'comments.editUnknown'
              ? CommentEditStatus.outcomeUnknown
              : CommentEditStatus.rejected,
          failure: failure,
        ),
        (updated) {
          if (!CommentEditGuard.acceptsResponse(original, updated, content)) {
            return const CommentEditResult(CommentEditStatus.outcomeUnknown);
          }
          add(
            CommentEditApplied(before: original, after: updated, fence: fence),
          );
          return const CommentEditResult(CommentEditStatus.saved);
        },
      );
    } catch (_) {
      return const CommentEditResult(CommentEditStatus.outcomeUnknown);
    } finally {
      if (identical(_editing[original.id], token)) _editing.remove(original.id);
    }
  }

  void _onEditApplied(CommentEditApplied event, Emitter<CommentState> emit) {
    if (!_current(event.fence, _identityEpoch)) return;
    final current = CommentEditGuard.find(state.comments, event.before.id);
    if (current == null ||
        !CommentEditGuard.sameSnapshot(current, event.before)) {
      return;
    }
    emit(
      state.copyWith(
        comments: CommentEditGuard.apply(
          state.comments,
          event.before,
          event.after,
        ),
      ),
    );
  }

  void _clearPending() {
    _pendingKey = null;
    _pendingContent = null;
    _pendingParent = null;
  }

  String _messageFor(Failure failure, {required String fallback}) {
    final message = failure.message;
    return message.isNotEmpty ? message : fallback;
  }

  /// The fallback failures minted here (empty message from a stub or an
  /// unexpected catch-all) get a stable code so the UI can still
  /// localize them (issue #24); real failures keep their own code.
  Failure _withCode(Failure failure, String code) {
    return failure.message.isEmpty
        ? Failure(
            _fallbackFor(code),
            kind: failure.kind,
            code: code,
            l10nKey: failure.l10nKey,
          )
        : failure.forPresentation();
  }

  String _fallbackFor(String code) => switch (code) {
    'comments.send' => '评论发送失败，请稍后重试',
    'comments.delete' => '评论删除失败，请稍后重试',
    _ => '评论加载失败，请稍后重试',
  };

  /// Inserts a root comment in server order or nests a reply under its direct
  /// parent.
  static List<Comment> _insertComment(List<Comment> comments, Comment added) {
    final parent = added.parentCommentId;
    if (parent == null) {
      return _sortRoots([...comments, added]);
    }
    return comments
        .map(
          (c) => c.id == parent
              ? _copyWithReplies(c, [...c.replies, added])
              : _copyWithReplies(c, _insertComment(c.replies, added)),
        )
        .toList();
  }

  /// Removes a comment together with its whole reply subtree.
  static List<Comment> _removeComment(List<Comment> comments, String id) {
    return comments
        .where((c) => c.id != id)
        .map((c) => _copyWithReplies(c, _removeComment(c.replies, id)))
        .toList();
  }

  static Comment _copyWithReplies(Comment comment, List<Comment> replies) {
    if (identical(comment.replies, replies) &&
        comment.replies.length == replies.length) {
      return comment;
    }
    return Comment(
      id: comment.id,
      articleId: comment.articleId,
      authorId: comment.authorId,
      parentCommentId: comment.parentCommentId,
      content: comment.content,
      isPlainText: comment.isPlainText,
      authorName: comment.authorName,
      authorAvatarUrl: comment.authorAvatarUrl,
      createdAt: comment.createdAt,
      editedAt: comment.editedAt,
      replies: replies,
    );
  }
}

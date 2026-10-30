import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_event.dart';
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
  }) : uuid = uuidGenerator ?? const Uuid(),
       super(const CommentState()) {
    on<CommentsRequested>(_onCommentsRequested);
    on<CommentSubmitted>(_onCommentSubmitted);
    on<CommentDeleteRequested>(_onCommentDeleteRequested);
  }

  String? _pendingKey;
  String? _pendingContent;
  String? _pendingParent;

  Future<void> _onCommentsRequested(
    CommentsRequested event,
    Emitter<CommentState> emit,
  ) async {
    emit(state.copyWith(status: CommentListStatus.loading, error: ''));
    final result = await getComments(slug);
    result.fold(
      (failure) => emit(
        state.copyWith(
          status: CommentListStatus.failure,
          error: _messageFor(failure, fallback: '评论加载失败，请稍后重试'),
          failure: _withCode(failure, 'comments.load'),
        ),
      ),
      (comments) => emit(
        state.copyWith(
          status: CommentListStatus.loaded,
          comments: comments,
          error: '',
        ),
      ),
    );
  }

  Future<void> _onCommentSubmitted(
    CommentSubmitted event,
    Emitter<CommentState> emit,
  ) async {
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
      ),
    );
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
    if (state.deletingIds.contains(event.commentId)) {
      return;
    }
    emit(
      state.copyWith(
        deletingIds: {...state.deletingIds, event.commentId},
        error: '',
      ),
    );
    final remaining = {...state.deletingIds}..remove(event.commentId);
    final result = await deleteComment(event.commentId);
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

  /// Appends a root comment at the end (oldest first) or nests a reply
  /// under its direct parent.
  static List<Comment> _insertComment(List<Comment> comments, Comment added) {
    final parent = added.parentCommentId;
    if (parent == null) {
      return [...comments, added];
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
      authorName: comment.authorName,
      authorAvatarUrl: comment.authorAvatarUrl,
      createdAt: comment.createdAt,
      replies: replies,
    );
  }
}

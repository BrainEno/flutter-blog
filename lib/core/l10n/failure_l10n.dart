import 'package:belog/core/error/failures.dart';
import 'package:belog/l10n/app_localizations.dart';

/// Translates typed, display-safe failures using their stable codes.
/// Unknown codes never expose raw exception details: Chinese legacy
/// messages are retained for Chinese users, otherwise a localized generic
/// message is chosen by failure kind.
String localizedFailure(AppLocalizations l10n, Failure failure) {
  switch (failure.l10nKey ?? failure.code) {
    // Network / connectivity.
    case 'network.offline':
      return l10n.errorNetworkOffline;
    case 'network.unavailable':
      return l10n.errorNetworkUnavailable;
    case 'network.timeout':
      return l10n.errorTimeout;

    // Auth.
    case 'auth.required':
      return l10n.errorAuthRequired;
    case 'auth.sessionExpired':
      return l10n.errorAuthSessionExpired;
    case 'auth.sessionChanged':
      return l10n.errorAuthSessionChanged;
    case 'auth.notSignedIn':
      return l10n.errorNotSignedIn;
    case 'auth.invalidCredentials':
      return l10n.errorInvalidCredentials;
    case 'auth.emailPasswordFormat':
      return l10n.errorEmailPasswordFormat;
    case 'auth.emailTaken':
      return l10n.errorEmailTaken;
    case 'auth.signupBadInput':
      return l10n.errorSignupBadInput;
    case 'auth.rateLimited':
      return l10n.errorAuthRateLimited;
    case 'auth.signupRateLimited':
      return l10n.errorSignupRateLimited;
    case 'auth.parse':
      return l10n.errorLoginParse;
    case 'auth.parse.missingUser':
      return l10n.errorLoginMissingUser;

    // Server error codes (mirrors the no-wave API contract).
    case 'server.UNAUTHENTICATED':
      return l10n.errorAuthExpired;
    case 'server.FORBIDDEN':
    case 'server.permission':
      return l10n.errorPermission;
    case 'server.NOT_FOUND':
      return l10n.errorNotFound;
    case 'server.CONFLICT':
      return l10n.errorConflict;
    case 'server.IDEMPOTENCY_CONFLICT':
      return l10n.errorIdempotencyConflict;
    case 'server.BAD_USER_INPUT':
      return l10n.errorBadInput;
    case 'server.RATE_LIMITED':
      return l10n.errorRateLimited;
    case 'server.SERVICE_UNAVAILABLE':
      return l10n.errorServiceUnavailable;
    case 'server.error':
      return l10n.errorServer;
    case 'server.parse':
      return l10n.errorServerParse;
    case 'storage.io':
      return l10n.errorStorage;

    // Data-shape problems raised before the server sees anything.
    case 'client.parse':
      return l10n.errorDataFormat;
    case 'profile.parse':
      return l10n.errorProfileParse;
    case 'article.emptyBody':
      return l10n.errorEmptyBody;
    case 'article.idUpdate':
      return l10n.errorArticleIdUpdate;
    case 'article.idDelete':
      return l10n.errorArticleIdDelete;
    case 'article.deletedCacheFailed':
      return l10n.errorArticleDeletedCacheFailed;
    case 'article.deleteFailed':
      return l10n.errorArticleDeleteFailed;
    case 'article.idRestore':
      return l10n.errorArticleIdRestore;

    // Feature-specific failures.
    case 'feed.sourceChanged':
      return l10n.feedSourceChanged;
    case 'comments.load':
      return l10n.errorCommentsLoad;
    case 'comments.send':
      return l10n.errorCommentsSend;
    case 'comments.sendOffline':
      return l10n.errorCommentsSendOffline;
    case 'comments.delete':
      return l10n.errorCommentsDelete;
    case 'comments.deleteOffline':
      return l10n.errorCommentsDeleteOffline;
    case 'comments.tooLong':
      return l10n.errorCommentTooLong;
    case 'likes.sync':
      return l10n.errorLikesSync;
    case 'likes.toggle':
      return l10n.errorLikesToggle;
    case 'likes.status':
      return l10n.errorLikesStatus;
    case 'likes.list':
      return l10n.errorLikesList;
    case 'related.load':
      return l10n.errorRelatedLoad;
    case 'author.load':
      return l10n.errorAuthorLoad;
    case 'follow.sync':
      return l10n.errorFollowSync;
    case 'unfollow.sync':
      return l10n.errorUnfollowSync;
    case 'follow.toggle':
      return l10n.errorFollowToggle;
    case 'export.failed':
      return l10n.exportFailed;
    case 'unknown':
      return l10n.errorUnknown;
  }
  if (l10n.localeName.startsWith('zh') &&
      RegExp(r'[\u4e00-\u9fff]').hasMatch(failure.message)) {
    return failure.message;
  }
  return switch (failure.kind) {
    FailureKind.network => l10n.errorNetworkOffline,
    FailureKind.timeout => l10n.errorTimeout,
    FailureKind.auth => l10n.errorAuthRequired,
    FailureKind.permission => l10n.errorPermission,
    FailureKind.validation => l10n.errorBadInput,
    FailureKind.storage => l10n.errorStorage,
    FailureKind.server => l10n.errorServer,
    FailureKind.unknown => l10n.errorUnknown,
  };
}

/// [localizedFailure] for states that carry an optional failure next to a
/// legacy message string: the failure wins when present, otherwise the
/// (display-safe, Chinese) fallback message is shown as-is.
String localizedFailureOr(
  AppLocalizations l10n,
  Failure? failure,
  String fallback,
) {
  if (failure == null && fallback.isEmpty) return '';
  return localizedFailure(l10n, failure ?? Failure(fallback));
}

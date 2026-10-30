/// The category of a failure.
///
/// UI layers may match on [Failure.kind] to choose wording or actions
/// (retry button for network, re-login for auth). [Failure.message] is
/// always safe to show to the user: Chinese, actionable, and never contains
/// raw exception dumps, stack traces, tokens or personal data.
enum FailureKind {
  network,
  timeout,
  auth,
  permission,
  validation,
  storage,
  server,
  unknown,
}

/// The single failure type crossing repository boundaries.
///
/// Repositories return `Either<Failure, T>`; [message] is display-safe,
/// [code] is a stable machine-readable identifier for logs, and [cause]
/// holds the original error for diagnostics only - it must never be
/// rendered in the UI.
class Failure {
  final FailureKind kind;
  final String message;
  final String? code;

  /// Optional presentation key when one machine code needs a more specific
  /// localized message (for example, an offline follow versus a failed send).
  /// It does not replace [code], which remains stable for callers.
  final String? l10nKey;
  final Object? cause;

  const Failure(
    this.message, {
    this.kind = FailureKind.unknown,
    this.code,
    this.l10nKey,
    this.cause,
  });

  /// Device is offline or the socket layer refused to connect.
  factory Failure.networkOffline({Object? cause}) => Failure(
    '无法连接到网络，请检查网络设置',
    kind: FailureKind.network,
    code: 'network.offline',
    cause: cause,
  );

  /// A request timed out.
  factory Failure.timeout({Object? cause}) => Failure(
    '请求超时，请稍后重试',
    kind: FailureKind.timeout,
    code: 'network.timeout',
    cause: cause,
  );

  /// Session missing/expired or credentials rejected.
  factory Failure.auth(String message, {Object? cause}) => Failure(
    message,
    kind: FailureKind.auth,
    code: 'auth.rejected',
    cause: cause,
  );

  /// Row-level security or missing grants denied the operation.
  factory Failure.permission({Object? cause}) => Failure(
    '没有权限执行此操作',
    kind: FailureKind.permission,
    code: 'server.permission',
    cause: cause,
  );

  /// Malformed input or data.
  factory Failure.validation(String message, {Object? cause}) => Failure(
    message,
    kind: FailureKind.validation,
    code: 'client.validation',
    cause: cause,
  );

  /// Local cache/database could not be read or written.
  factory Failure.storage({Object? cause}) => Failure(
    '本地存储读写失败',
    kind: FailureKind.storage,
    code: 'storage.io',
    cause: cause,
  );

  /// The backend rejected or failed the request.
  factory Failure.server(String message, {Object? cause}) => Failure(
    message,
    kind: FailureKind.server,
    code: 'server.error',
    cause: cause,
  );

  /// Anything unclassified. [message] stays generic by design.
  factory Failure.unknown({Object? cause}) => Failure(
    '发生未知错误，请稍后重试',
    kind: FailureKind.unknown,
    code: 'unknown',
    cause: cause,
  );

  /// Drops the diagnostic-only cause before a failure is stored in UI state.
  Failure forPresentation() => Failure(
    message,
    kind: kind,
    code: code,
    l10nKey: l10nKey,
  );

  @override
  String toString() =>
      'Failure($kind, $code, $message)'
      '${cause == null ? '' : ' cause=$cause'}';
}

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/auth/auth_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Source of incoming app links, abstracted so the handler can be tested
/// without platform channels.
abstract interface class DeepLinkSource {
  /// Link the app was launched with, if any.
  Future<Uri?> initialLink();

  /// Broadcast stream of links received while the app is running.
  Stream<Uri> get links;
}

/// [DeepLinkSource] backed by the app_links plugin.
class AppLinksDeepLinkSource implements DeepLinkSource {
  AppLinksDeepLinkSource([AppLinks? appLinks])
    : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> initialLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get links => _appLinks.uriLinkStream;
}

/// Outcome of handling an auth deep link.
enum AuthLinkResult { accepted, rejected }

/// Resolution of a Supabase auth callback URL: the established session
/// plus the auth event the exchange produced, which identifies the flow
/// type ([AuthChangeEvent.signedIn] for e-mail confirmation,
/// [AuthChangeEvent.passwordRecovery] for password-reset links).
typedef AuthCallbackResolver =
    Future<({AuthSessionUrlResponse response, AuthChangeEvent? event})>
    Function(Uri url);

/// Handles Supabase auth callback links (e-mail confirmation, password
/// recovery) sent to [kAuthCallbackUrl].
///
/// The session is established by the resolver (gotrue's
/// `getSessionFromUrl`); the downstream user-state update happens through
/// the auth state stream, which [AuthSessionSync] observes.
class AuthLinkHandler {
  AuthLinkHandler({
    required DeepLinkSource links,
    required AuthCallbackResolver resolveCallbackUrl,
    required void Function(AuthLinkResult result, String message) onResult,
  }) : _links = links,
       _resolveCallbackUrl = resolveCallbackUrl,
       _onResult = onResult;

  final DeepLinkSource _links;
  final AuthCallbackResolver _resolveCallbackUrl;
  final void Function(AuthLinkResult result, String message) _onResult;

  StreamSubscription<Uri>? _subscription;
  bool _started = false;

  /// Starts observing links (cold start + running app). Idempotent.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final initial = await _links.initialLink();
      if (initial != null) {
        // Fire-and-forget: handling must not block startup, and the
        // stream subscription below has to be in place either way.
        unawaited(_handle(initial));
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'reading initial auth link failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
    _subscription = _links.links.listen(
      _handle,
      onError: (Object e, StackTrace stackTrace) {
        AppLogger.error(
          'auth link stream failed',
          error: e,
          stackTrace: stackTrace,
        );
      },
    );
  }

  /// Releases the subscription; safe to call multiple times.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }

  Future<void> _handle(Uri uri) async {
    if (uri.scheme != kAuthCallbackScheme) {
      // Not ours; other plugins may own the link.
      return;
    }
    try {
      // The resolver throws for invalid/expired links; a returned
      // response always carries an established session.
      final resolution = await _resolveCallbackUrl(uri);
      switch (resolution.event) {
        case AuthChangeEvent.passwordRecovery:
          _onResult(AuthLinkResult.accepted, '身份验证成功，请前往「我的-账号安全」设置新密码');
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.userUpdated:
          _onResult(AuthLinkResult.accepted, '邮箱验证成功，已为你登录');
        default:
          _onResult(AuthLinkResult.accepted, '链接验证成功，已为你登录');
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'auth callback link failed',
        error: e,
        stackTrace: stackTrace,
      );
      _onResult(AuthLinkResult.rejected, _kRejectedMessage);
    }
  }
}

const String _kRejectedMessage = '链接无效或已过期，请重新获取邮件后重试';

import 'dart:async';

import 'package:belog/features/auth/auth_link_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves a Supabase auth callback URL with gotrue's
/// `getSessionFromUrl` and reports the auth event the exchange produced,
/// so callers can tell the flow types apart (e-mail confirmation vs
/// password recovery).
///
/// The auth state stream is a replay subject: a fresh subscription first
/// receives every buffered historical event. The subscription below is
/// armed only after one event-loop turn, by which time the replay has been
/// flushed, so only events produced by the exchange itself are captured.
Future<({AuthSessionUrlResponse? response, AuthChangeEvent? event})>
resolveSupabaseAuthCallback({required GoTrueClient auth, required Uri url}) async {
  AuthChangeEvent? event;
  var armed = false;
  final subscription = auth.onAuthStateChange.listen((state) {
    if (armed) {
      event ??= state.event;
    }
  });
  try {
    // Let the replay of historical events flush before arming.
    await Future<void>.delayed(Duration.zero);
    armed = true;
    final response = await auth.getSessionFromUrl(url);
    // The exchange notifies subscribers asynchronously; one event-loop
    // turn is enough for the notification to be delivered.
    await Future<void>.delayed(Duration.zero);
    return (response: response, event: event);
  } finally {
    unawaited(subscription.cancel());
  }
}

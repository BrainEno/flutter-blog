import 'dart:async';

import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/data/publish/publish_queue_runner.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:flutter/widgets.dart';

/// Wires the publish queue into the app's life (issue #23).
///
/// It repairs what a killed process left behind and drains whenever the signed
/// in account changes - a sign-in restores the queue, and a different account
/// gets its own entries - and when the app returns to the foreground, which is
/// the moment a device that was offline tends to be online again. It
/// deliberately does not poll: the queue is also drained by opening the queue
/// screen and by asking for it.
class PublishQueueService with WidgetsBindingObserver {
  PublishQueueService({
    required this.store,
    required this.runner,
    required this.identity,
  });

  final PublishQueueStore store;
  final PublishQueueRunner runner;
  final NowaveSessionIdentity identity;

  StreamSubscription<void>? _identitySubscription;
  bool _started = false;

  /// Safe to call more than once; only the first call does anything.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      // Anything left `uploading` belongs to a process that died mid-send.
      await store.recoverInterrupted();
    } catch (error) {
      AppLogger.error('the publish queue could not be repaired', error: error);
    }
    _identitySubscription = identity.identityChanges.listen((_) {
      unawaited(drain());
    });
    unawaited(drain());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_started) return;
    unawaited(drain());
  }

  /// Sends what is due for the active account; see [PublishQueueRunner.drain].
  Future<int> drain() => runner.drain();

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _identitySubscription?.cancel();
    _identitySubscription = null;
    _started = false;
  }
}

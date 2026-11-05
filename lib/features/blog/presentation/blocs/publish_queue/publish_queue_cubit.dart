import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_drainer.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class PublishQueueState {
  const PublishQueueState();
}

final class PublishQueueLoading extends PublishQueueState {
  const PublishQueueLoading();
}

final class PublishQueueFailure extends PublishQueueState {
  final Failure failure;

  const PublishQueueFailure(this.failure);

  /// Display-safe fallback; the UI localizes via `localizedFailure`.
  String get error => failure.message;
}

final class PublishQueueLoaded extends PublishQueueState {
  final List<PublishQueueEntry> entries;

  /// True while a drain is in flight, so the list can say it is sending.
  final bool sending;

  /// False when nobody is signed in: the queue exists but has no owner to
  /// send for, and the page asks the user to sign in.
  final bool signedIn;

  const PublishQueueLoaded({
    required this.entries,
    this.sending = false,
    this.signedIn = true,
  });

  bool get isEmpty => entries.isEmpty;

  PublishQueueLoaded copyWith({
    List<PublishQueueEntry>? entries,
    bool? sending,
    bool? signedIn,
  }) {
    return PublishQueueLoaded(
      entries: entries ?? this.entries,
      sending: sending ?? this.sending,
      signedIn: signedIn ?? this.signedIn,
    );
  }
}

/// Drives the publish queue screen (issue #23).
///
/// The list is the account's own; every action goes through the store, and the
/// actual sending stays in the runner, so the screen cannot publish anything
/// the automatic drain would not.
class PublishQueueCubit extends Cubit<PublishQueueState> {
  PublishQueueCubit({
    required this.store,
    required this.drainer,
    required this.identity,
  }) : super(const PublishQueueLoading()) {
    _identitySubscription = identity.identityChanges.listen((_) {
      unawaited(load(silent: true));
    });
    unawaited(load());
  }

  final PublishQueueStore store;
  final PublishQueueDrainer drainer;
  final NowaveSessionIdentity identity;

  StreamSubscription<void>? _identitySubscription;

  Future<void> load({bool silent = false}) async {
    final userId = identity.activeUserId;
    if (userId == null || userId.isEmpty) {
      emit(const PublishQueueLoaded(entries: [], signedIn: false));
      return;
    }
    if (!silent) emit(const PublishQueueLoading());
    try {
      final entries = await store.entries(userId: userId);
      final current = state;
      final sending = current is PublishQueueLoaded && current.sending;
      emit(
        PublishQueueLoaded(entries: entries, signedIn: true, sending: sending),
      );
    } catch (error) {
      emit(
        PublishQueueFailure(
          Failure(
            '发布队列读取失败',
            kind: FailureKind.storage,
            code: 'publish_queue.read_failed',
            cause: error,
          ),
        ),
      );
    }
  }

  /// Sends what is due, then shows the new state.
  Future<void> sendNow() async {
    final current = state;
    if (current is PublishQueueLoaded) {
      emit(current.copyWith(sending: true));
    }
    try {
      await drainer.drain();
    } finally {
      await load(silent: true);
    }
  }

  /// Puts a failed entry back in line and sends it right away.
  Future<bool> retry(String id) async {
    try {
      await store.retry(id);
    } catch (_) {
      return false;
    }
    await load(silent: true);
    unawaited(sendNow());
    return true;
  }

  /// Deletes an entry (and its stored cover) for good.
  Future<bool> remove(String id) async {
    try {
      await store.remove(id);
    } catch (_) {
      return false;
    }
    await load(silent: true);
    return true;
  }

  @override
  Future<void> close() async {
    await _identitySubscription?.cancel();
    _identitySubscription = null;
    return super.close();
  }
}

import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/auth/domain/account_editorial_capacity.dart';
import 'package:belog/features/auth/domain/repository/account_editorial_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Whether this account should be offered the editorial screens, for the
/// profile menu.
///
/// The cold state is [AccountEditorialCapacity.denied]: an entry that appears
/// and then vanishes reads as a glitch, while one that appears once the account
/// has been identified reads as what it is. A failed read keeps the last answer
/// rather than inventing one - the same rule the unread badges follow, where a
/// number is only ever replaced by a better number.
///
/// It reads once when the profile opens, when the account changes, and when the
/// caller asks. It does not poll: the answer comes from `GET /me`, and a timer
/// would spend a session-scoped request to learn what the next screen opening
/// would learn anyway.
class EditorialCapacityCubit extends Cubit<AccountEditorialCapacity> {
  EditorialCapacityCubit({required this.repository, required this.identity})
    : super(AccountEditorialCapacity.denied) {
    _identitySubscription = identity.identityChanges.listen((_) {
      // A different account must not inherit the previous one's role, not even
      // for the moment the request takes.
      if (!isClosed) emit(AccountEditorialCapacity.denied);
      unawaited(refresh());
    });
    unawaited(refresh());
  }

  final AccountEditorialRepository repository;
  final NowaveSessionIdentity identity;

  StreamSubscription<void>? _identitySubscription;
  int _refreshGeneration = 0;

  NowaveSessionFence? get _fence {
    final userId = identity.activeUserId;
    final token = identity.accessToken;
    if (userId == null || userId.isEmpty) return null;
    if (token == null || token.isEmpty) return null;
    return NowaveSessionFence(
      userId: userId,
      generation: identity.sessionGeneration,
    );
  }

  bool _stillCurrent(NowaveSessionFence fence) {
    return identity.activeUserId == fence.userId &&
        identity.sessionGeneration == fence.generation;
  }

  /// Asks again. Only the latest started refresh may update the state: an
  /// answer for a previous account must never land on top of a newer one.
  Future<void> refresh() async {
    final requestGeneration = ++_refreshGeneration;
    final fence = _fence;
    if (fence == null) {
      if (!isClosed) emit(AccountEditorialCapacity.denied);
      return;
    }
    final result = await repository.readCapacity(fence);
    if (isClosed ||
        requestGeneration != _refreshGeneration ||
        !_stillCurrent(fence)) {
      return;
    }
    result.fold<void>((_) {}, _emit);
  }

  void _emit(AccountEditorialCapacity capacity) {
    if (!isClosed) emit(capacity);
  }

  @override
  Future<void> close() {
    _identitySubscription?.cancel();
    _identitySubscription = null;
    return super.close();
  }
}

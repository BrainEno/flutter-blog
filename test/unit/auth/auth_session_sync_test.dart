import 'dart:async';
import 'dart:collection';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart' as app;
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/usecase/usecase.dart' show NoParams;
import 'package:belog/features/auth/auth_session_sync.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

/// Scriptable stand-in for the CurrentUser usecase.
class FakeCurrentUser implements CurrentUser {
  FakeCurrentUser(this._results);

  final Queue<Either<Failure, app.User>> _results;

  /// When set, the in-flight call waits for this completer.
  Completer<Either<Failure, app.User>>? gate;

  int calls = 0;

  // CurrentUser exposes its repository as a public getter; the interface
  // requires it but the fake never touches it.
  @override
  AuthRepository get authRepository => throw UnimplementedError();

  @override
  Future<Either<Failure, app.User>> call(NoParams params) async {
    calls++;
    if (gate != null) {
      return gate!.future;
    }
    if (_results.isEmpty) {
      return Left(Failure('请登录账户'));
    }
    return _results.removeFirst();
  }
}

NowaveSessionData _session(String userId) => NowaveSessionData(
  userId: userId,
  email: 'user@example.invalid',
  accessToken: 'access-$userId',
  refreshToken: 'refresh-$userId',
  accessExpiresAt: DateTime.utc(2030),
  refreshExpiresAt: DateTime.utc(2030),
);

app.User _appUser(String id) => app.User(
  id: id,
  email: 'user@example.invalid',
  name: '测试用户',
  updatedAt: DateTime.utc(2024),
);

void main() {
  late StreamController<NowaveAuthStatus> statusEvents;
  late AppUserCubit appUserCubit;
  NowaveSessionData? currentSession;

  AuthSessionSync buildSync(FakeCurrentUser currentUser) => AuthSessionSync(
    statusStream: statusEvents.stream,
    currentSession: () => currentSession,
    currentUser: currentUser,
    appUserCubit: appUserCubit,
  );

  setUp(() {
    statusEvents = StreamController<NowaveAuthStatus>.broadcast();
    appUserCubit = AppUserCubit();
    currentSession = null;
  });

  tearDown(() async {
    await statusEvents.close();
    await appUserCubit.close();
  });

  test('a revoked session (signedOut) clears the logged-in state', () async {
    final sync = buildSync(FakeCurrentUser(Queue()));
    appUserCubit.updateUser(_appUser('u1'));
    sync.start();

    statusEvents.add(const NowaveAuthSignedOut());
    await Future<void>.delayed(Duration.zero);

    expect(appUserCubit.state, isA<AppUserInitial>());
    await sync.dispose();
  });

  test('signedIn refreshes the profile and updates the cubit', () async {
    final fakeCurrentUser = FakeCurrentUser(
      Queue<Either<Failure, app.User>>()..add(Right(_appUser('u1'))),
    );
    final sync = buildSync(fakeCurrentUser);
    currentSession = _session('u1');
    sync.start();

    statusEvents.add(const NowaveAuthSignedIn('u1'));
    await Future<void>.delayed(Duration.zero);

    expect(appUserCubit.state, isA<AppUserLoggedIn>());
    expect((appUserCubit.state as AppUserLoggedIn).user.id, 'u1');
    expect(fakeCurrentUser.calls, 1);
    await sync.dispose();
  });

  test(
    'a refresh finishing after sign-out does not resurrect the login',
    () async {
      // The user refresh hangs until the gate is released.
      final gate = Completer<Either<Failure, app.User>>();
      final fakeCurrentUser = FakeCurrentUser(
        Queue<Either<Failure, app.User>>()..add(Right(_appUser('u1'))),
      );
      fakeCurrentUser.gate = gate;
      final sync = buildSync(fakeCurrentUser);
      currentSession = _session('u1');
      sync.start();

      statusEvents.add(const NowaveAuthSignedIn('u1'));
      // The session is revoked while the refresh is still in flight.
      currentSession = null;
      statusEvents.add(const NowaveAuthSignedOut());
      await Future<void>.delayed(Duration.zero);
      expect(appUserCubit.state, isA<AppUserInitial>());

      gate.complete(Right(_appUser('u1')));
      await Future<void>.delayed(Duration.zero);

      expect(appUserCubit.state, isA<AppUserInitial>());
      await sync.dispose();
    },
  );

  test('a delayed sign-out event does not clear a newer session', () async {
    final sync = buildSync(FakeCurrentUser(Queue()));
    currentSession = _session('u2');
    appUserCubit.updateUser(_appUser('u2'));
    sync.start();

    statusEvents.add(const NowaveAuthSignedOut());
    await Future<void>.delayed(Duration.zero);

    expect((appUserCubit.state as AppUserLoggedIn).user.id, 'u2');
    await sync.dispose();
  });

  test('start() is idempotent (only one subscription)', () async {
    final fakeCurrentUser = FakeCurrentUser(
      Queue<Either<Failure, app.User>>()..add(Right(_appUser('u1'))),
    );
    final sync = buildSync(fakeCurrentUser);
    currentSession = _session('u1');
    sync.start();
    sync.start();

    statusEvents.add(const NowaveAuthSignedIn('u1'));
    await Future<void>.delayed(Duration.zero);

    expect(fakeCurrentUser.calls, 1);
    await sync.dispose();
  });
}

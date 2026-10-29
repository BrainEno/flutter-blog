import 'dart:async';
import 'dart:collection';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart' as app;
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart' show NoParams;
import 'package:belog/features/auth/auth_session_sync.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

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

sb.Session _session(String userId) => sb.Session(
  accessToken: 'token-$userId',
  tokenType: 'bearer',
  user: sb.User(
    id: userId,
    appMetadata: {},
    userMetadata: {},
    aud: '',
    createdAt: '2024-01-01T00:00:00Z',
  ),
);

app.User _appUser(String id) => app.User(
  id: id,
  email: 'user@example.invalid',
  name: '测试用户',
  updatedAt: DateTime.utc(2024),
);

void main() {
  late StreamController<sb.AuthState> authEvents;
  late AppUserCubit appUserCubit;
  sb.Session? currentSession;

  AuthSessionSync buildSync(FakeCurrentUser currentUser) => AuthSessionSync(
    authStateStream: authEvents.stream,
    currentSession: () => currentSession,
    currentUser: currentUser,
    appUserCubit: appUserCubit,
  );

  setUp(() {
    authEvents = StreamController<sb.AuthState>.broadcast();
    appUserCubit = AppUserCubit();
    currentSession = null;
  });

  tearDown(() async {
    await authEvents.close();
    await appUserCubit.close();
  });

  test('signedOut clears the logged-in state', () async {
    final sync = buildSync(FakeCurrentUser(Queue()));
    appUserCubit.updateUser(_appUser('u1'));
    sync.start();

    authEvents.add(const sb.AuthState(sb.AuthChangeEvent.signedOut, null));
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

    authEvents.add(sb.AuthState(sb.AuthChangeEvent.signedIn, currentSession));
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

      authEvents.add(sb.AuthState(sb.AuthChangeEvent.signedIn, currentSession));
      // Sign out while the refresh is still in flight.
      currentSession = null;
      authEvents.add(const sb.AuthState(sb.AuthChangeEvent.signedOut, null));
      await Future<void>.delayed(Duration.zero);
      expect(appUserCubit.state, isA<AppUserInitial>());

      gate.complete(Right(_appUser('u1')));
      await Future<void>.delayed(Duration.zero);

      expect(appUserCubit.state, isA<AppUserInitial>());
      await sync.dispose();
    },
  );

  test('tokenRefreshed does not trigger a profile refresh', () async {
    final fakeCurrentUser = FakeCurrentUser(Queue<Either<Failure, app.User>>());
    final sync = buildSync(fakeCurrentUser);
    currentSession = _session('u1');
    sync.start();

    authEvents.add(
      sb.AuthState(sb.AuthChangeEvent.tokenRefreshed, currentSession),
    );
    await Future<void>.delayed(Duration.zero);

    expect(fakeCurrentUser.calls, 0);
    await sync.dispose();
  });

  test('userUpdated refreshes the profile', () async {
    final fakeCurrentUser = FakeCurrentUser(
      Queue<Either<Failure, app.User>>()..add(Right(_appUser('u1'))),
    );
    final sync = buildSync(fakeCurrentUser);
    currentSession = _session('u1');
    sync.start();

    authEvents.add(
      sb.AuthState(sb.AuthChangeEvent.userUpdated, currentSession),
    );
    await Future<void>.delayed(Duration.zero);

    expect(appUserCubit.state, isA<AppUserLoggedIn>());
    await sync.dispose();
  });

  test('initialSession is ignored', () async {
    final fakeCurrentUser = FakeCurrentUser(Queue<Either<Failure, app.User>>());
    final sync = buildSync(fakeCurrentUser);
    currentSession = _session('u1');
    sync.start();

    authEvents.add(
      sb.AuthState(sb.AuthChangeEvent.initialSession, currentSession),
    );
    await Future<void>.delayed(Duration.zero);

    expect(fakeCurrentUser.calls, 0);
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

    authEvents.add(sb.AuthState(sb.AuthChangeEvent.signedIn, currentSession));
    await Future<void>.delayed(Duration.zero);

    expect(fakeCurrentUser.calls, 1);
    await sync.dispose();
  });
}

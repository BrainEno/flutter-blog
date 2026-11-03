import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/auth/domain/auth_intent_gate.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:belog/features/auth/domain/usecases/user_login.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_out.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_up.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockUserSignUp extends Mock implements UserSignUp {}

class _MockUserLogin extends Mock implements UserLogin {}

class _MockUserSignOut extends Mock implements UserSignOut {}

class _MockCurrentUser extends Mock implements CurrentUser {}

User _user(String id) => User(
  id: id,
  email: '$id@example.invalid',
  name: '测试用户 $id',
  updatedAt: DateTime.utc(2024),
);

/// Blocks the response of a mocked use case until the test releases it, so
/// two intents can be in flight at once and answer in any order.
class _Pending {
  final completer = Completer<Either<Failure, User>>();

  Future<Either<Failure, User>> get future => completer.future;

  void succeed(String id) => completer.complete(Right(_user(id)));
}

void main() {
  late _MockUserSignUp userSignUp;
  late _MockUserLogin userLogin;
  late _MockUserSignOut userSignOut;
  late _MockCurrentUser currentUser;
  late AppUserCubit appUserCubit;
  late AuthIntentGate intentGate;
  late AuthBloc bloc;
  late String? currentSessionUserId;

  setUpAll(() {
    registerFallbackValue(UserSignUpParams(email: '', name: '', password: ''));
    registerFallbackValue(UserLoginParams(email: '', password: ''));
    registerFallbackValue(NoParams());
  });

  setUp(() {
    userSignUp = _MockUserSignUp();
    userLogin = _MockUserLogin();
    userSignOut = _MockUserSignOut();
    currentUser = _MockCurrentUser();
    appUserCubit = AppUserCubit();
    intentGate = AuthIntentGate();
    currentSessionUserId = null;
    bloc = AuthBloc(
      userSignUp: userSignUp,
      userLogin: userLogin,
      userSignOut: userSignOut,
      currentUser: currentUser,
      appUserCubit: appUserCubit,
      intentGate: intentGate,
      sessionGeneration: () => 0,
      hasActiveSession: () => currentSessionUserId != null,
      isCurrentSessionUser: (user) =>
          currentSessionUserId == null || currentSessionUserId == user.id,
    );
    addTearDown(bloc.close);
    addTearDown(appUserCubit.close);
  });

  String? signedInId() {
    final state = appUserCubit.state;
    return state is AppUserLoggedIn ? state.user.id : null;
  }

  test('the sign-in started last wins when the first answers last', () async {
    final first = _Pending();
    final second = _Pending();
    var calls = 0;
    when(() => userLogin(any())).thenAnswer((_) {
      calls++;
      return calls == 1 ? first.future : second.future;
    });

    bloc.add(AuthLogin(email: 'a@example.invalid', password: 'first'));
    await pumpEventQueue();
    bloc.add(AuthLogin(email: 'b@example.invalid', password: 'second'));
    await pumpEventQueue();

    currentSessionUserId = 'b';
    second.succeed('b');
    await pumpEventQueue();
    expect(signedInId(), 'b');

    // The slow first attempt answers after the user already switched.
    first.succeed('a');
    await pumpEventQueue();

    expect(signedInId(), 'b');
    expect((bloc.state as AuthSuccess).user.id, 'b');
  });

  test('a newer sign-in replaces an earlier one that answered first', () async {
    final first = _Pending();
    final second = _Pending();
    var calls = 0;
    when(() => userLogin(any())).thenAnswer((_) {
      calls++;
      return calls == 1 ? first.future : second.future;
    });

    bloc.add(AuthLogin(email: 'a@example.invalid', password: 'first'));
    await pumpEventQueue();
    bloc.add(AuthLogin(email: 'b@example.invalid', password: 'second'));
    await pumpEventQueue();

    currentSessionUserId = 'a';
    first.succeed('a');
    await pumpEventQueue();
    expect(signedInId(), 'a');

    currentSessionUserId = 'b';
    second.succeed('b');
    await pumpEventQueue();

    expect(signedInId(), 'b');
  });

  test('a late sign-up cannot replace a newer sign-in', () async {
    final pendingSignUp = _Pending();
    when(() => userSignUp(any())).thenAnswer((_) => pendingSignUp.future);
    when(() => userLogin(any())).thenAnswer((_) async => Right(_user('b')));

    bloc.add(
      AuthSignUp(
        email: 'a@example.invalid',
        name: 'A',
        password: 'a-12-char-secret',
      ),
    );
    await pumpEventQueue();
    currentSessionUserId = 'b';
    bloc.add(AuthLogin(email: 'b@example.invalid', password: 'second'));
    await pumpEventQueue();
    expect(signedInId(), 'b');

    pendingSignUp.succeed('a');
    await pumpEventQueue();

    expect(signedInId(), 'b');
    expect((bloc.state as AuthSuccess).user.id, 'b');
  });

  test('a sign-out drops a sign-in that answers afterwards', () async {
    final pendingLogin = _Pending();
    when(() => userLogin(any())).thenAnswer((_) => pendingLogin.future);
    when(() => userSignOut(any())).thenAnswer((_) async => const Right(null));

    bloc.add(AuthLogin(email: 'a@example.invalid', password: 'first'));
    await pumpEventQueue();
    bloc.add(AuthLogout());
    await pumpEventQueue();

    expect(bloc.state, isA<AuthLogoutSuccess>());
    expect(signedInId(), isNull);

    pendingLogin.succeed('a');
    await pumpEventQueue();

    expect(signedInId(), isNull);
    expect(bloc.state, isA<AuthLogoutSuccess>());
  });

  test('a restore started earlier cannot replace a newer sign-in', () async {
    final pendingRestore = _Pending();
    when(() => currentUser(any())).thenAnswer((_) => pendingRestore.future);
    when(() => userLogin(any())).thenAnswer((_) async => Right(_user('b')));

    bloc.add(AuthIsUserLoggedIn());
    await pumpEventQueue();
    currentSessionUserId = 'b';
    bloc.add(AuthLogin(email: 'b@example.invalid', password: 'second'));
    await pumpEventQueue();
    expect(signedInId(), 'b');

    pendingRestore.succeed('a');
    await pumpEventQueue();

    expect(signedInId(), 'b');
    expect((bloc.state as AuthSuccess).user.id, 'b');
  });

  test('the gate hands out increasing ids and keeps the newest', () {
    expect(intentGate.current, 0);
    expect(intentGate.isCurrent(0), isFalse);
    final first = intentGate.begin();
    expect(intentGate.isCurrent(first), isTrue);
    final second = intentGate.begin();
    expect(second, greaterThan(first));
    expect(intentGate.isCurrent(first), isFalse);
    expect(intentGate.isCurrent(second), isTrue);
    // Callers that do not take part in intent ordering are never blocked.
    expect(intentGate.allows(null), isTrue);
  });
}

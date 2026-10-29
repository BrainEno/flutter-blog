import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:belog/features/auth/domain/usecases/user_login.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_out.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_up.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class MockUserSignUp extends Mock implements UserSignUp {}

class MockUserLogin extends Mock implements UserLogin {}

class MockUserSignOut extends Mock implements UserSignOut {}

class MockCurrentUser extends Mock implements CurrentUser {}

User _user([String id = 'u1']) => User(
  id: id,
  email: 'user@example.invalid',
  name: '测试用户',
  updatedAt: DateTime.utc(2024),
);

void main() {
  late MockUserSignUp userSignUp;
  late MockUserLogin userLogin;
  late MockUserSignOut userSignOut;
  late MockCurrentUser currentUser;
  late AppUserCubit appUserCubit;
  late AuthBloc bloc;

  setUpAll(() {
    registerFallbackValue(UserSignUpParams(email: '', name: '', password: ''));
    registerFallbackValue(UserLoginParams(email: '', password: ''));
    registerFallbackValue(NoParams());
  });

  setUp(() {
    userSignUp = MockUserSignUp();
    userLogin = MockUserLogin();
    userSignOut = MockUserSignOut();
    currentUser = MockCurrentUser();
    appUserCubit = AppUserCubit();
    bloc = AuthBloc(
      userSignUp: userSignUp,
      userLogin: userLogin,
      userSignOut: userSignOut,
      currentUser: currentUser,
      appUserCubit: appUserCubit,
    );
    addTearDown(bloc.close);
    addTearDown(appUserCubit.close);
  });

  Future<List<AuthState>> capture(void Function() trigger) async {
    final done = Completer<void>();
    final states = <AuthState>[];
    late final StreamSubscription<AuthState> sub;
    sub = bloc.stream.listen(states.add, onDone: done.complete);
    trigger();
    await bloc.close();
    await done.future;
    await sub.cancel();
    return states;
  }

  group('AuthSignUp', () {
    test('a successful sign-up logs the user in immediately '
        '(no e-mail confirmation step)', () async {
      when(() => userSignUp(any())).thenAnswer((_) async => Right(_user()));

      final states = await capture(
        () => bloc.add(
          AuthSignUp(
            email: 'user@example.invalid',
            name: '测试用户',
            password: 'a-12-char-secret',
          ),
        ),
      );

      expect(states, [isA<AuthLoading>(), isA<AuthSuccess>()]);
      expect(appUserCubit.state, isA<AppUserLoggedIn>());
    });

    test('a failed sign-up emits a failure and does not log in', () async {
      when(() => userSignUp(any())).thenAnswer(
        (_) async => Left(Failure('该邮箱已被注册，请直接登录')),
      );

      final states = await capture(
        () => bloc.add(
          AuthSignUp(
            email: 'user@example.invalid',
            name: '测试用户',
            password: 'a-12-char-secret',
          ),
        ),
      );

      expect(states, [isA<AuthLoading>(), isA<AuthFailure>()]);
      expect(appUserCubit.state, isA<AppUserInitial>());
    });
  });

  group('AuthLogin', () {
    test('a successful login fetches the profile and logs in', () async {
      when(
        () => userLogin(
          UserLoginParams(email: 'user@example.invalid', password: 'secret'),
        ),
      ).thenAnswer((_) async => Right(_user()));
      when(() => currentUser(NoParams())).thenAnswer(
        (_) async => Right(
          _user(),
        ),
      );

      final states = await capture(
        () => bloc.add(
          AuthLogin(email: 'user@example.invalid', password: 'secret'),
        ),
      );

      expect(states, [isA<AuthLoading>(), isA<AuthSuccess>()]);
      expect(appUserCubit.state, isA<AppUserLoggedIn>());
    });

    test('a rejected login emits a failure', () async {
      when(
        () => userLogin(
          UserLoginParams(email: 'user@example.invalid', password: 'wrong'),
        ),
      ).thenAnswer(
        (_) async => Left(Failure.auth('邮箱或密码不正确')),
      );

      final states = await capture(
        () => bloc.add(
          AuthLogin(email: 'user@example.invalid', password: 'wrong'),
        ),
      );

      expect(states, [isA<AuthLoading>(), isA<AuthFailure>()]);
      expect(appUserCubit.state, isA<AppUserInitial>());
      verifyNever(() => currentUser(NoParams()));
    });
  });

  group('AuthLogout', () {
    test('logout clears the identity even when the server call fails',
        () async {
      appUserCubit.updateUser(_user());
      when(() => userSignOut(NoParams())).thenAnswer(
        (_) async => Left(Failure('无法连接到网络')),
      );

      final states = await capture(() => bloc.add(AuthLogout()));

      expect(states.last, isA<AuthLogoutFailure>());
      expect(appUserCubit.state, isA<AppUserInitial>());
    });

    test('a successful logout emits success', () async {
      appUserCubit.updateUser(_user());
      when(
        () => userSignOut(NoParams()),
      ).thenAnswer((_) async => Right<Failure, void>(null));

      final states = await capture(() => bloc.add(AuthLogout()));

      expect(states.last, isA<AuthLogoutSuccess>());
      expect(appUserCubit.state, isA<AppUserInitial>());
    });
  });

  group('AuthIsUserLoggedIn', () {
    test('a restored session logs the user in without a loading state',
        () async {
      when(
        () => currentUser(NoParams()),
      ).thenAnswer((_) async => Right(_user()));

      final states = await capture(() => bloc.add(AuthIsUserLoggedIn()));

      expect(states, [isA<AuthSuccess>()]);
      expect(appUserCubit.state, isA<AppUserLoggedIn>());
    });

    test('a missing session emits a failure', () async {
      when(
        () => currentUser(NoParams()),
      ).thenAnswer((_) async => Left(Failure('登录状态已失效，请重新登录')));

      final states = await capture(() => bloc.add(AuthIsUserLoggedIn()));

      expect(states, [isA<AuthFailure>()]);
      expect(appUserCubit.state, isA<AppUserInitial>());
    });
  });
}

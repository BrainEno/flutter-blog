import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/auth/domain/entities/sign_up_outcome.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:belog/features/auth/domain/usecases/resend_confirmation_email.dart';
import 'package:belog/features/auth/domain/usecases/send_password_reset_email.dart';
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

class MockResendConfirmationEmail extends Mock
    implements ResendConfirmationEmail {}

class MockSendPasswordResetEmail extends Mock
    implements SendPasswordResetEmail {}

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
  late MockResendConfirmationEmail resendConfirmationEmail;
  late MockSendPasswordResetEmail sendPasswordResetEmail;
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
    resendConfirmationEmail = MockResendConfirmationEmail();
    sendPasswordResetEmail = MockSendPasswordResetEmail();
    appUserCubit = AppUserCubit();
    bloc = AuthBloc(
      userSignUp: userSignUp,
      userLogin: userLogin,
      userSignOut: userSignOut,
      currentUser: currentUser,
      resendConfirmationEmail: resendConfirmationEmail,
      sendPasswordResetEmail: sendPasswordResetEmail,
      appUserCubit: appUserCubit,
    );
    addTearDown(bloc.close);
    addTearDown(appUserCubit.close);
  });

  Future<List<AuthState>> capture(Future<void> Function() trigger) async {
    final done = Completer<void>();
    final states = <AuthState>[];
    late final StreamSubscription<AuthState> sub;
    sub = bloc.stream.listen(states.add, onDone: done.complete);
    await trigger();
    await bloc.close();
    await done.future;
    await sub.cancel();
    return states;
  }

  group('AuthSignUp', () {
    test('a sign-up without a session (e-mail confirmation required) does NOT '
        'log the user in', () async {
      when(() => userSignUp(any())).thenAnswer(
        (_) async => Right(SignUpOutcome(email: 'user@example.invalid')),
      );

      final states = await capture(
        () => bloc.add(
          AuthSignUp(
            email: 'user@example.invalid',
            name: '测试用户',
            password: 'secret',
          ),
        ),
      );

      expect(states.where((s) => s is! AuthLoading), [
        isA<AuthNeedsEmailConfirmation>(),
      ]);
      final pending = states.whereType<AuthNeedsEmailConfirmation>().single;
      expect(pending.email, 'user@example.invalid');
      // The identity cubit must stay logged out: an unconfirmed auth
      // user is not a signed-in user.
      expect(appUserCubit.state, isA<AppUserInitial>());
    });

    test('a sign-up with a session logs the user in', () async {
      when(() => userSignUp(any())).thenAnswer(
        (_) async =>
            Right(SignUpOutcome(email: 'user@example.invalid', user: _user())),
      );

      final states = await capture(
        () => bloc.add(
          AuthSignUp(
            email: 'user@example.invalid',
            name: '测试用户',
            password: 'secret',
          ),
        ),
      );

      expect(states.last, isA<AuthSuccess>());
      expect(appUserCubit.state, isA<AppUserLoggedIn>());
    });

    test('a failing sign-up surfaces the failure message', () async {
      when(
        () => userSignUp(any()),
      ).thenAnswer((_) async => Left(Failure('User already registered')));

      final states = await capture(
        () => bloc.add(
          AuthSignUp(
            email: 'user@example.invalid',
            name: '测试用户',
            password: 'secret',
          ),
        ),
      );

      expect(states.last, isA<AuthFailure>());
      expect((states.last as AuthFailure).message, 'User already registered');
      expect(appUserCubit.state, isA<AppUserInitial>());
    });
  });

  group('AuthResendConfirmationEmail', () {
    test('re-send succeeds without flipping the UI into a loader', () async {
      when(
        () => resendConfirmationEmail('user@example.invalid'),
      ).thenAnswer((_) async => Right(null));

      final states = await capture(
        () => bloc.add(
          AuthResendConfirmationEmail(email: 'user@example.invalid'),
        ),
      );

      expect(states, [isA<AuthConfirmationEmailSent>()]);
      expect(states.whereType<AuthLoading>(), isEmpty);
    });

    test('re-send failure propagates to the UI', () async {
      when(() => resendConfirmationEmail('user@example.invalid')).thenAnswer(
        (_) async => Left(
          Failure(
            'For security purposes, you can only '
            'request this once every 60 seconds',
          ),
        ),
      );

      final states = await capture(
        () => bloc.add(
          AuthResendConfirmationEmail(email: 'user@example.invalid'),
        ),
      );

      expect(states.last, isA<AuthFailure>());
    });
  });

  group('AuthForgotPassword', () {
    test('requests the recovery e-mail and reports that it was sent', () async {
      when(
        () => sendPasswordResetEmail('user@example.invalid'),
      ).thenAnswer((_) async => Right(null));

      final states = await capture(
        () => bloc.add(AuthForgotPassword(email: 'user@example.invalid')),
      );

      expect(states.last, isA<AuthPasswordResetEmailSent>());
      verify(() => sendPasswordResetEmail('user@example.invalid')).called(1);
    });

    test(
      'an unknown address also resolves to "sent" (no user enumeration)',
      () async {
        when(
          () => sendPasswordResetEmail(any()),
        ).thenAnswer((_) async => Right(null));

        final states = await capture(
          () => bloc.add(AuthForgotPassword(email: 'nobody@example.invalid')),
        );

        expect(states.last, isA<AuthPasswordResetEmailSent>());
      },
    );

    test('transport failures propagate to the UI', () async {
      when(
        () => sendPasswordResetEmail(any()),
      ).thenAnswer((_) async => Left(Failure.networkOffline()));

      final states = await capture(
        () => bloc.add(AuthForgotPassword(email: 'user@example.invalid')),
      );

      expect(states.last, isA<AuthFailure>());
      expect((states.last as AuthFailure).message, contains('网络'));
    });
  });
}

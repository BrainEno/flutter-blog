import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:belog/features/auth/domain/usecases/user_login.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_out.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_up.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/auth/presentation/pages/login_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _AuthRepository extends Mock implements AuthRepository {}

void main() {
  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language login localizes validation and server errors at 2x',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final l10n = lookupAppLocalizations(Locale(language));
          final repo = _AuthRepository();
          when(
            () => repo.currentUser(),
          ).thenAnswer((_) async => left<Failure, User>(Failure.auth('请登录账户')));
          when(
            () => repo.loginWithEmailPassword(
              email: any(named: 'email'),
              password: any(named: 'password'),
            ),
          ).thenAnswer(
            (_) async => left<Failure, User>(
              Failure(
                '邮箱或密码不正确',
                kind: FailureKind.auth,
                code: 'auth.rejected',
                l10nKey: 'auth.invalidCredentials',
              ),
            ),
          );
          final user = AppUserCubit();
          final auth = AuthBloc(
            userSignUp: UserSignUp(repo),
            userLogin: UserLogin(repo),
            userSignOut: UserSignOut(repo),
            currentUser: CurrentUser(repo),
            appUserCubit: user,
          );
          addTearDown(auth.close);
          addTearDown(user.close);
          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>.value(value: auth),
                BlocProvider<AppUserCubit>.value(value: user),
              ],
              child: MaterialApp(
                locale: Locale(language),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: const [Locale('zh'), Locale('en')],
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: const LoginPage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.bySemanticsLabel(RegExp(l10n.fieldEmail)), findsWidgets);
          expect(
            find.bySemanticsLabel(RegExp(l10n.fieldPassword)),
            findsWidgets,
          );
          final signIn = find.widgetWithText(ElevatedButton, l10n.loginTitle);
          await tester.ensureVisible(signIn);
          await tester.tap(signIn);
          await tester.pumpAndSettle();
          expect(
            find.text(l10n.fieldRequiredPrompt(l10n.fieldEmail)),
            findsOneWidget,
          );
          expect(
            find.text(l10n.fieldRequiredPrompt(l10n.fieldPassword)),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          await tester.enterText(
            find.byType(TextFormField).first,
            'test@example.invalid',
          );
          await tester.enterText(
            find.byType(TextFormField).last,
            'wrong password',
          );
          await tester.ensureVisible(signIn);
          await tester.tap(signIn);
          await tester.pumpAndSettle();
          expect(find.text(l10n.errorInvalidCredentials), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}

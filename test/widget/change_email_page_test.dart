import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/auth/domain/repository/account_security_repository.dart';
import 'package:belog/features/auth/presentation/pages/change_email_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

class _Session implements NowaveViewerAuthenticator {
  String? userId = 'user-a';
  String? token = 'access-a';
  int generation = 1;

  @override
  String? get activeUserId => userId;
  @override
  String? get accessToken => token;
  @override
  int get sessionGeneration => generation;
  @override
  Future<bool> refresh() async => false;
}

class _Repository implements AccountSecurityRepository {
  final calls =
      <({String userId, int generation, String password, String email})>[];
  Completer<Either<Failure, String>>? pending;
  Either<Failure, String> result = right('new@example.invalid');

  @override
  Future<Either<Failure, void>> changePassword({
    required String expectedUserId,
    required int expectedSessionGeneration,
    required String currentPassword,
    required String newPassword,
  }) async => throw UnimplementedError('not asked from the e-mail form');

  @override
  Future<Either<Failure, String>> changeEmail({
    required String expectedUserId,
    required int expectedSessionGeneration,
    required String currentPassword,
    required String newEmail,
  }) {
    calls.add((
      userId: expectedUserId,
      generation: expectedSessionGeneration,
      password: currentPassword,
      email: newEmail,
    ));
    return pending?.future ?? Future.value(result);
  }
}

User _user({String email = 'old@example.invalid'}) => User(
  id: 'user-a',
  email: email,
  name: 'user-a',
  updatedAt: DateTime.utc(2025),
);

Future<void> _pump(
  WidgetTester tester, {
  required _Repository repository,
  required _Session session,
  required AppUserCubit user,
  Locale locale = const Locale('en'),
  ThemeMode mode = ThemeMode.light,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    BlocProvider<AppUserCubit>.value(
      value: user,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightThemeMode,
        darkTheme: AppTheme.darkThemeMode,
        themeMode: mode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ChangeEmailPage(repository: repository, session: session),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, int index, String value) async {
  final field = find.byType(TextFormField).at(index);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
}

Future<void> _tapSubmit(WidgetTester tester, AppLocalizations l10n) async {
  final button = find.widgetWithText(FilledButton, l10n.accountEmailAction);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

const _taken = Failure(
  '该邮箱已被其他账户使用',
  kind: FailureKind.validation,
  code: 'account.emailTaken',
);
const _rejected = Failure(
  '当前密码可能不正确，或登录已失效',
  kind: FailureKind.auth,
  code: 'account.emailRejected',
);

void main() {
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the form fits 320px at 2x: $locale ${mode.name}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final user = AppUserCubit()..updateUser(_user());
        addTearDown(user.close);
        final repository = _Repository();
        final l10n = lookupAppLocalizations(locale);

        await _pump(
          tester,
          repository: repository,
          session: _Session(),
          user: user,
          locale: locale,
          mode: mode,
          scale: 2,
        );

        expect(find.text(l10n.accountEmailCurrent), findsOneWidget);
        expect(find.text('old@example.invalid'), findsOneWidget);
        await _tapSubmit(tester, l10n);
        await tester.pumpAndSettle();

        // Nothing typed: the form explains itself and nothing is sent.
        expect(find.text(l10n.accountEmailRequired), findsOneWidget);
        expect(repository.calls, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a changed address is shown as the server stored it', (
    tester,
  ) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
      locale: const Locale('en'),
    );

    await _enter(tester, 0, '  New@Example.INVALID  ');
    await _enter(tester, 1, 'current password');
    await _tapSubmit(tester, l10n);
    await tester.pumpAndSettle();

    expect(repository.calls.single.email, 'new@example.invalid');
    expect(repository.calls.single.password, 'current password');
    expect(repository.calls.single.userId, 'user-a');
    // The account object is what the rest of the app shows.
    final state = user.state;
    expect(state, isA<AppUserLoggedIn>());
    expect((state as AppUserLoggedIn).user.email, 'new@example.invalid');
    expect(
      find.text(l10n.accountEmailSuccess('new@example.invalid')),
      findsOneWidget,
    );
    // The server sends no mail, and the screen must not imply that it does.
    expect(find.text(l10n.accountEmailUnverified), findsOneWidget);
  });

  testWidgets('the password never stays in the field after a submit', (
    tester,
  ) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository()..result = left(_rejected);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
      locale: const Locale('en'),
    );

    await _enter(tester, 0, 'new@example.invalid');
    await _enter(tester, 1, 'current password');
    await _tapSubmit(tester, l10n);
    await tester.pumpAndSettle();

    expect(repository.calls, hasLength(1));
    expect(find.text(l10n.accountEmailRejected), findsOneWidget);
    final password = tester.widget<TextFormField>(
      find.byType(TextFormField).at(1),
    );
    expect(password.controller?.text, isEmpty);
    // The address is not a secret: it stays so a typo can be corrected.
    final address = tester.widget<TextFormField>(
      find.byType(TextFormField).at(0),
    );
    expect(address.controller?.text, 'new@example.invalid');
  });

  testWidgets('an address another account holds is named', (tester) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository()..result = left(_taken);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
      locale: const Locale('en'),
    );

    await _enter(tester, 0, 'new@example.invalid');
    await _enter(tester, 1, 'current password');
    await _tapSubmit(tester, l10n);
    await tester.pumpAndSettle();

    expect(find.text(l10n.accountEmailTaken), findsOneWidget);
    // A refused change must not rewrite the account object.
    expect((user.state as AppUserLoggedIn).user.email, 'old@example.invalid');
  });

  testWidgets('the address already on the account is not resubmitted', (
    tester,
  ) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
      locale: const Locale('en'),
    );

    await _enter(tester, 0, '  OLD@example.invalid ');
    await _enter(tester, 1, 'current password');
    await _tapSubmit(tester, l10n);
    await tester.pumpAndSettle();

    expect(repository.calls, isEmpty);
    expect(find.text(l10n.accountEmailUnchanged), findsOneWidget);
  });

  testWidgets('a malformed address never reaches the repository', (
    tester,
  ) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
      locale: const Locale('en'),
    );

    await _enter(tester, 0, 'no-at-sign');
    await _enter(tester, 1, 'current password');
    await _tapSubmit(tester, l10n);
    await tester.pumpAndSettle();

    expect(find.text(l10n.accountEmailInvalid), findsOneWidget);
    expect(repository.calls, isEmpty);
  });

  testWidgets('a submit in flight disables the form', (tester) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository()..pending = Completer();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
      locale: const Locale('en'),
    );

    await _enter(tester, 0, 'new@example.invalid');
    await _enter(tester, 1, 'current password');
    await _tapSubmit(tester, l10n);
    await tester.pump();

    expect(find.text(l10n.accountEmailUpdating), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    repository.pending!.complete(right('new@example.invalid'));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.accountEmailSuccess('new@example.invalid')),
      findsOneWidget,
    );
  });

  testWidgets('an account switch locks the form before any request', (
    tester,
  ) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository();
    final session = _Session();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: session,
      user: user,
      locale: const Locale('en'),
    );
    await _enter(tester, 0, 'new@example.invalid');
    await _enter(tester, 1, 'current password');

    // A same-account re-login also moves the generation: the form belongs to
    // the session that opened it.
    session.generation = 2;
    user.updateUser(_user());
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorAuthSessionChanged), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    await _tapSubmit(tester, l10n);
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
  });
}

import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/auth/domain/repository/account_security_repository.dart';
import 'package:belog/features/auth/presentation/pages/change_password_page.dart';
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
      <({String userId, int generation, String current, String next})>[];
  Completer<Either<Failure, void>>? pending;
  Either<Failure, void> result = right(null);

  @override
  Future<Either<Failure, void>> changePassword({
    required String expectedUserId,
    required int expectedSessionGeneration,
    required String currentPassword,
    required String newPassword,
  }) {
    calls.add((
      userId: expectedUserId,
      generation: expectedSessionGeneration,
      current: currentPassword,
      next: newPassword,
    ));
    return pending?.future ?? Future.value(result);
  }
}

User _user(String id) => User(
  id: id,
  email: '$id@example.invalid',
  name: id,
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
        home: ChangePasswordPage(repository: repository, session: session),
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
  final button = find.widgetWithText(FilledButton, l10n.passwordChangeAction);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

void main() {
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('localized validation and visibility at 2x: $locale $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        final user = AppUserCubit()..updateUser(_user('user-a'));
        addTearDown(user.close);
        final repository = _Repository();
        final session = _Session();
        final l10n = lookupAppLocalizations(locale);
        try {
          await _pump(
            tester,
            repository: repository,
            session: session,
            user: user,
            locale: locale,
            mode: mode,
            scale: 2,
          );
          expect(find.text(l10n.passwordChangeInfo), findsOneWidget);
          expect(find.byType(TextFormField), findsNWidgets(3));
          for (final field in tester.widgetList<TextField>(
            find.byType(TextField),
          )) {
            expect(field.obscureText, isTrue);
            expect(field.enableSuggestions, isFalse);
            expect(field.enableIMEPersonalizedLearning, isFalse);
          }
          expect(
            find.byTooltip(l10n.passwordShowField(l10n.passwordCurrent)),
            findsOneWidget,
          );
          // Scroll the actual field icon into the real ListView viewport;
          // a tooltip's surrogate render box can be outside it at 2x text.
          final showIcon = find.byIcon(Icons.visibility).first;
          await tester.scrollUntilVisible(
            showIcon,
            140,
            scrollable: find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(showIcon);
          await tester.pump();
          expect(
            tester.widget<TextField>(find.byType(TextField).first).obscureText,
            isFalse,
          );
          expect(
            find.byTooltip(l10n.passwordHideField(l10n.passwordCurrent)),
            findsOneWidget,
          );
          await tester.tap(find.byIcon(Icons.visibility_off).first);
          await tester.pump();

          await _tapSubmit(tester, l10n);
          expect(find.text(l10n.passwordRequired), findsNWidgets(3));
          expect(repository.calls, isEmpty);
          await _enter(tester, 0, 'old password');
          await _enter(tester, 1, '😀' * 11);
          await _enter(tester, 2, '😀' * 11);
          await _tapSubmit(tester, l10n);
          expect(find.text(l10n.passwordMinLength), findsOneWidget);
          expect(repository.calls, isEmpty);
          await _enter(tester, 1, 'long enough password');
          await _enter(tester, 2, 'different password');
          await _tapSubmit(tester, l10n);
          expect(find.text(l10n.passwordConfirmMismatch), findsOneWidget);
          expect(repository.calls, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets(
    'one submit keeps exact spaces, blocks repeats and clears secrets',
    (tester) async {
      final user = AppUserCubit()..updateUser(_user('user-a'));
      addTearDown(user.close);
      final repository = _Repository()
        ..pending = Completer<Either<Failure, void>>();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pump(
        tester,
        repository: repository,
        session: _Session(),
        user: user,
      );
      await _enter(tester, 0, ' current password ');
      await _enter(tester, 1, '  new password  ');
      await _enter(tester, 2, '  new password  ');
      await _tapSubmit(tester, l10n);
      expect(repository.calls, hasLength(1));
      expect(repository.calls.single.userId, 'user-a');
      expect(repository.calls.single.generation, 1);
      expect(repository.calls.single.current, ' current password ');
      expect(repository.calls.single.next, '  new password  ');
      final updating = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.passwordChanging),
      );
      expect(updating.onPressed, isNull);
      expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .every((f) => !f.enabled),
        isTrue,
      );
      repository.pending!.complete(right(null));
      await tester.pumpAndSettle();
      expect(find.text(l10n.passwordChangeSuccess), findsOneWidget);
      for (final field in tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      )) {
        expect(field.controller!.text, isEmpty);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('uncertain outcome is visible and credentials are cleared', (
    tester,
  ) async {
    final user = AppUserCubit()..updateUser(_user('user-a'));
    addTearDown(user.close);
    final repository = _Repository()
      ..result = left(
        const Failure(
          'fixture',
          code: 'auth.passwordOutcomeUnknown',
          cause: 'sensitive diagnostic',
        ),
      );
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
    );
    await _enter(tester, 0, 'current password');
    await _enter(tester, 1, 'a new password');
    await _enter(tester, 2, 'a new password');
    await _tapSubmit(tester, l10n);
    await tester.pumpAndSettle();
    expect(find.text(l10n.errorPasswordOutcomeUnknown), findsOneWidget);
    expect(find.text('sensitive diagnostic'), findsNothing);
    for (final field in tester.widgetList<TextFormField>(
      find.byType(TextFormField),
    )) {
      expect(field.controller!.text, isEmpty);
    }
  });

  testWidgets('account switch during a write never displays the old success', (
    tester,
  ) async {
    final user = AppUserCubit()..updateUser(_user('user-a'));
    addTearDown(user.close);
    final session = _Session();
    final repository = _Repository()
      ..pending = Completer<Either<Failure, void>>();
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _pump(tester, repository: repository, session: session, user: user);
    await _enter(tester, 0, 'current password');
    await _enter(tester, 1, 'a new password');
    await _enter(tester, 2, 'a new password');
    await _tapSubmit(tester, l10n);
    session.userId = 'user-b';
    session.generation++;
    user.updateUser(_user('user-b'));
    await tester.pump();
    repository.pending!.complete(right(null));
    await tester.pumpAndSettle();
    expect(find.text(l10n.passwordChangeSuccess), findsNothing);
    expect(find.text(l10n.errorAuthSessionChanged), findsOneWidget);
    expect(repository.calls.single.userId, 'user-a');
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.passwordChangeAction),
    );
    expect(button.onPressed, isNull);
    for (final field in tester.widgetList<TextFormField>(
      find.byType(TextFormField),
    )) {
      expect(field.controller!.text, isEmpty);
    }
  });

  testWidgets('same-account re-login invalidates the old form', (tester) async {
    final user = AppUserCubit()..updateUser(_user('user-a'));
    addTearDown(user.close);
    final session = _Session();
    final repository = _Repository();
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _pump(tester, repository: repository, session: session, user: user);
    await _enter(tester, 0, 'current password');
    await _enter(tester, 1, 'a new password');
    await _enter(tester, 2, 'a new password');
    session.generation++;
    await _tapSubmit(tester, l10n);
    expect(repository.calls, isEmpty);
    expect(find.text(l10n.errorAuthSessionChanged), findsOneWidget);
  });
}

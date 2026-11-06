import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/auth/domain/email_verification.dart';
import 'package:belog/features/auth/domain/repository/account_security_repository.dart';
import 'package:belog/features/auth/presentation/pages/email_verification_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

const _token = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_aBcD0';

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
  final statusCalls = <({String userId, int generation})>[];
  final sendCalls = <({String userId, int generation})>[];
  final tokenCalls = <String>[];
  Either<Failure, AccountEmailStatus> status = right(_unverified);
  Either<Failure, EmailVerificationRequest> send =
      right(EmailVerificationRequest.sent);
  Either<Failure, void> token = right(null);
  void Function()? afterSend;
  void Function()? afterToken;

  @override
  Future<Either<Failure, void>> changePassword({
    required String expectedUserId,
    required int expectedSessionGeneration,
    required String currentPassword,
    required String newPassword,
  }) async => throw UnimplementedError('not asked from this page');

  @override
  Future<Either<Failure, String>> changeEmail({
    required String expectedUserId,
    required int expectedSessionGeneration,
    required String currentPassword,
    required String newEmail,
  }) async => throw UnimplementedError('not asked from this page');

  @override
  Future<Either<Failure, AccountEmailStatus>> readEmailStatus({
    required String expectedUserId,
    required int expectedSessionGeneration,
  }) async {
    statusCalls.add((
      userId: expectedUserId,
      generation: expectedSessionGeneration,
    ));
    return status;
  }

  @override
  Future<Either<Failure, EmailVerificationRequest>>
  requestEmailVerification({
    required String expectedUserId,
    required int expectedSessionGeneration,
  }) async {
    sendCalls.add((
      userId: expectedUserId,
      generation: expectedSessionGeneration,
    ));
    afterSend?.call();
    return send;
  }

  @override
  Future<Either<Failure, void>> verifyEmailToken({
    required String token,
  }) async {
    tokenCalls.add(token);
    afterToken?.call();
    return this.token;
  }
}

const _unverified = AccountEmailStatus(
  email: 'old@example.invalid',
  verifiedAt: null,
);
final _verified = AccountEmailStatus(
  email: 'old@example.invalid',
  verifiedAt: DateTime.utc(2025, 1, 2),
);

User _user() => User(
  id: 'user-a',
  email: 'old@example.invalid',
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
        home: EmailVerificationPage(repository: repository, session: session),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('unverified state fits 320px at 2x: $locale ${mode.name}', (
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

        expect(find.text('old@example.invalid'), findsOneWidget);
        expect(find.text(l10n.emailVerifyUnverified), findsOneWidget);
        expect(find.text(l10n.emailVerifySend), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a verified address reports the date and offers no mail', (
    tester,
  ) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository()..status = right(_verified);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
    );

    expect(find.textContaining('2025'), findsOneWidget);
    final send = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(send.onPressed, isNull);
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.enabled, isFalse);
    expect(find.text(l10n.emailVerifyAlreadyVerified), findsNothing);
  });

  testWidgets('sending says only that the server accepted the request', (
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
    );
    await _tap(tester, find.text(l10n.emailVerifySend));

    expect(repository.sendCalls.single.userId, 'user-a');
    expect(repository.sendCalls.single.generation, 1);
    expect(find.text(l10n.emailVerifySent), findsOneWidget);
    expect(repository.statusCalls, hasLength(1));
  });

  testWidgets('an already verified account refreshes instead of mailing', (
    tester,
  ) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository()
      ..send = right(EmailVerificationRequest.alreadyVerified);
    repository.afterSend = () => repository.status = right(_verified);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
    );
    await _tap(tester, find.text(l10n.emailVerifySend));

    expect(find.text(l10n.emailVerifyAlreadyVerified), findsOneWidget);
    // The screen replaces the stale "unverified" fact with the server's.
    expect(repository.statusCalls, hasLength(2));
    expect(find.text(l10n.emailVerifyUnverified), findsNothing);
  });

  testWidgets('a deployment without mail says so instead of implying a mail', (
    tester,
  ) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository()
      ..send = left(
        const Failure(
          'fixture',
          kind: FailureKind.server,
          code: 'account.verificationMailDisabled',
        ),
      );
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
    );
    await _tap(tester, find.text(l10n.emailVerifySend));

    expect(find.text(l10n.emailVerifyMailDisabled), findsOneWidget);
    expect(find.text(l10n.emailVerifySent), findsNothing);
  });

  testWidgets('a pasted link confirms in the app and is never echoed', (
    tester,
  ) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository();
    repository.afterToken = () => repository.status = right(_verified);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
    );
    await tester.enterText(
      find.byType(TextFormField),
      '请打开下面的链接确认这个邮箱属于你。\n'
      'https://wave.example.invalid/verify-email?token=$_token',
    );
    await _tap(tester, find.text(l10n.emailVerifyTokenConfirm));

    expect(repository.tokenCalls, [_token]);
    expect(find.text(l10n.emailVerifyTokenDone), findsOneWidget);
    // The code is a one-time credential: it does not stay on screen.
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller?.text, isEmpty);
    expect(find.textContaining(_token), findsNothing);
    expect(repository.statusCalls, hasLength(2));
  });

  testWidgets('text without a code never reaches the server', (tester) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
    );
    await tester.enterText(find.byType(TextFormField), 'confirm your address');
    await _tap(tester, find.text(l10n.emailVerifyTokenConfirm));

    expect(repository.tokenCalls, isEmpty);
    expect(find.text(l10n.emailVerifyTokenMalformed), findsOneWidget);
  });

  testWidgets('a spent code is reported as such, not as a retry', (
    tester,
  ) async {
    final user = AppUserCubit()..updateUser(_user());
    addTearDown(user.close);
    final repository = _Repository()
      ..token = left(
        const Failure(
          'fixture',
          kind: FailureKind.auth,
          code: 'account.verificationTokenRejected',
        ),
      );
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pump(
      tester,
      repository: repository,
      session: _Session(),
      user: user,
    );
    await tester.enterText(find.byType(TextFormField), _token);
    await _tap(tester, find.text(l10n.emailVerifyTokenConfirm));

    expect(find.text(l10n.emailVerifyTokenRejected), findsOneWidget);
    expect(find.text(l10n.emailVerifyTokenDone), findsNothing);
  });

  testWidgets('an account switch locks the page before anything is sent', (
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
    );
    await tester.enterText(find.byType(TextFormField), _token);

    session.generation = 2;
    user.updateUser(_user());
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorAuthSessionChanged), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    // Nothing typed survives the switch.
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller?.text, isEmpty);
    expect(repository.sendCalls, isEmpty);
    expect(repository.tokenCalls, isEmpty);
  });
}

import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/auth/domain/repository/password_recovery_repository.dart';
import 'package:belog/features/auth/domain/usecases/request_password_reset.dart';
import 'package:belog/features/auth/domain/usecases/reset_password.dart';
import 'package:belog/features/auth/presentation/pages/password_recovery_page.dart';
import 'package:belog/features/auth/presentation/pages/password_reset_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

const _token = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_aBcD0';
const _password = '  a secure reset phrase  ';

class _Repository implements PasswordRecoveryRepository {
  final requestedEmails = <String>[];
  final resetTokens = <String>[];
  final resetPasswords = <String>[];
  Either<Failure, void> requestResult = right(null);
  Either<Failure, void> resetResult = right(null);

  @override
  Future<Either<Failure, void>> requestPasswordReset({
    required String email,
  }) async {
    requestedEmails.add(email);
    return requestResult;
  }

  @override
  Future<Either<Failure, void>> resetPassword({
    required String token,
    required String password,
  }) async {
    resetTokens.add(token);
    resetPasswords.add(password);
    return resetResult;
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: child,
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
  testWidgets(
    'accepted recovery copy does not reveal whether the e-mail exists',
    (tester) async {
      final repository = _Repository();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pump(
        tester,
        PasswordRecoveryPage(
          requestPasswordReset: RequestPasswordReset(repository),
        ),
      );

      await tester.enterText(
        find.byType(TextFormField),
        'reader@example.invalid',
      );
      await _tap(
        tester,
        find.widgetWithText(NoWaveButton, l10n.passwordRecoverySend),
      );

      expect(repository.requestedEmails, ['reader@example.invalid']);
      expect(find.text(l10n.passwordRecoveryRequestAccepted), findsOneWidget);
      expect(find.textContaining('reader@example.invalid'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('MAIL_DISABLED is shown as temporarily unavailable', (
    tester,
  ) async {
    final repository = _Repository()
      ..requestResult = left(
        const Failure(
          'ignored fallback',
          code: 'auth.passwordRecoveryMailDisabled',
        ),
      );
    final l10n = lookupAppLocalizations(const Locale('zh'));
    await _pump(
      tester,
      PasswordRecoveryPage(
        requestPasswordReset: RequestPasswordReset(repository),
      ),
      locale: const Locale('zh'),
    );

    await tester.enterText(
      find.byType(TextFormField),
      'reader@example.invalid',
    );
    await _tap(
      tester,
      find.widgetWithText(NoWaveButton, l10n.passwordRecoverySend),
    );

    expect(find.text('暂不提供'), findsOneWidget);
    expect(
      find.widgetWithText(NoWaveButton, l10n.passwordRecoverySend),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pasting a complete link sends only its token and exact password',
    (tester) async {
      final repository = _Repository();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pump(
        tester,
        PasswordResetPage(resetPassword: ResetPassword(repository)),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(
        fields.at(0),
        'https://site.example/reset-password?token=$_token',
      );
      await tester.enterText(fields.at(1), _password);
      await tester.enterText(fields.at(2), _password);
      await _tap(
        tester,
        find.widgetWithText(NoWaveButton, l10n.passwordRecoveryReset),
      );

      expect(repository.resetTokens, [_token]);
      expect(repository.resetPasswords, [_password]);
      expect(find.text(l10n.passwordRecoveryResetSuccess), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mismatched passwords are rejected before the repository', (
    tester,
  ) async {
    final repository = _Repository();
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _pump(
      tester,
      PasswordResetPage(resetPassword: ResetPassword(repository)),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), _token);
    await tester.enterText(fields.at(1), _password);
    await tester.enterText(fields.at(2), 'a different password');
    await _tap(
      tester,
      find.widgetWithText(NoWaveButton, l10n.passwordRecoveryReset),
    );

    expect(repository.resetTokens, isEmpty);
    expect(find.text(l10n.passwordConfirmMismatch), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an uncertain reset result cannot be resubmitted with the same link',
    (tester) async {
      final repository = _Repository()
        ..resetResult = left(
          const Failure(
            'ignored fallback',
            code: 'auth.passwordRecoveryResetOutcomeUnknown',
          ),
        );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pump(
        tester,
        PasswordResetPage(resetPassword: ResetPassword(repository)),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), _token);
      await tester.enterText(fields.at(1), _password);
      await tester.enterText(fields.at(2), _password);
      await _tap(
        tester,
        find.widgetWithText(NoWaveButton, l10n.passwordRecoveryReset),
      );

      expect(
        find.text(l10n.passwordRecoveryResetOutcomeUnknown),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNothing);
      expect(
        find.widgetWithText(NoWaveButton, l10n.passwordRecoveryReset),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reset form remains scrollable at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      PasswordResetPage(resetPassword: ResetPassword(_Repository())),
      locale: const Locale('zh'),
      scale: 2,
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}

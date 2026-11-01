import 'package:belog/features/auth/domain/password_rules.dart';
import 'package:belog/l10n/app_localizations.dart';

/// Localizes the same code-point and byte rules used before sending.
String? passwordProblemMessage(AppLocalizations l10n, PasswordProblem? issue) =>
    switch (issue) {
      null => null,
      PasswordProblem.required => l10n.passwordRequired,
      PasswordProblem.tooShort => l10n.passwordMinLength,
      PasswordProblem.tooLong => l10n.passwordMaxLength,
    };

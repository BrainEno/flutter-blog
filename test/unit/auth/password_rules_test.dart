import 'package:belog/features/auth/domain/password_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new passwords follow the no-wave code-point bounds', () {
    expect(validateNewPassword(''), PasswordProblem.required);
    expect(validateNewPassword('a' * 11), PasswordProblem.tooShort);
    expect(validateNewPassword('a' * 12), isNull);
    expect(validateNewPassword('😀' * 11), PasswordProblem.tooShort);
    expect(validateNewPassword('😀' * 12), isNull);
    expect(validateNewPassword('😀' * 128), isNull);
    expect(validateNewPassword('😀' * 129), PasswordProblem.tooLong);
    expect(validateNewPassword('a' * 129), PasswordProblem.tooLong);
  });

  test('current passwords use login bounds and are never trimmed', () {
    expect(validateCurrentPassword(''), PasswordProblem.required);
    expect(validateCurrentPassword(' '), isNull);
    expect(validateCurrentPassword('a' * 128), isNull);
    expect(validateCurrentPassword('a' * 129), PasswordProblem.tooLong);
    expect(validateNewPassword(' 1234567890 '), isNull);
  });
}

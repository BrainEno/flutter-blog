import 'dart:convert';

/// no-wave counts Unicode code points, not UTF-16 code units or graphemes.
/// Passwords are never trimmed or otherwise normalized by these checks.
enum PasswordProblem { required, tooShort, tooLong }

PasswordProblem? validateCurrentPassword(String? value) =>
    _validate(value, minimum: 1);

PasswordProblem? validateNewPassword(String? value) =>
    _validate(value, minimum: 12);

PasswordProblem? _validate(String? value, {required int minimum}) {
  if (value == null || value.isEmpty) return PasswordProblem.required;
  final length = value.runes.length;
  if (length < minimum) return PasswordProblem.tooShort;
  if (length > 128 || utf8.encode(value).length > 512) {
    return PasswordProblem.tooLong;
  }
  return null;
}

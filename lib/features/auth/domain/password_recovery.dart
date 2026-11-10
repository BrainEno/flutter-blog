import 'dart:convert';

/// The one-time credential returned in a no-wave password-reset link.
///
/// The API creates 32 random bytes and encodes them as unpadded base64url. A
/// link points at the web front end, so the app accepts either the bare token
/// or the complete pasted URL, but only sends the extracted token in the JSON
/// request body.
final RegExp _passwordResetToken = RegExp(r'^[A-Za-z0-9_-]{43}$');
final RegExp _passwordResetTokenInText = RegExp(
  r'token=([A-Za-z0-9_-]{43})(?![A-Za-z0-9_-])',
);

bool isPasswordResetToken(String value) {
  if (!_passwordResetToken.hasMatch(value)) return false;
  try {
    final decoded = base64Url.decode(base64Url.normalize(value));
    return decoded.length == 32 &&
        base64Url.encode(decoded).replaceAll('=', '') == value;
  } on FormatException {
    return false;
  }
}

/// Returns the exact token the server accepts, or null if [input] has none.
String? extractPasswordResetToken(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  if (isPasswordResetToken(text)) return text;

  final match = _passwordResetTokenInText.firstMatch(text);
  final pastedToken = match?.group(1);
  if (pastedToken != null && isPasswordResetToken(pastedToken)) {
    return pastedToken;
  }

  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  final queryToken = uri.queryParameters['token'];
  if (queryToken != null && isPasswordResetToken(queryToken)) {
    return queryToken;
  }
  for (final segment in uri.pathSegments) {
    if (isPasswordResetToken(segment)) return segment;
  }
  return null;
}

/// The address rules no-wave applies before it looks at an account.
///
/// These mirror `normalizeEmail` in the API: the server trims, lowercases, and
/// then refuses anything that is not a single `local@domain` pair of at most
/// 254 characters. Checking the same shape here turns a typo into an inline
/// error instead of a round trip that consumes a rate-limit slot - and it is
/// deliberately not stricter than the server, so a legal address is never
/// rejected by the client alone.
enum EmailProblem { required, tooLong, malformed }

/// Exactly what the server will store: trimmed and lowercased.
///
/// Sending this instead of the raw field keeps the confirmation on screen
/// identical to the address on the account.
String normalizeEmailAddress(String value) => value.trim().toLowerCase();

/// The first problem with [value], or null when the server would accept it.
EmailProblem? validateEmailAddress(String? value) {
  if (value == null || value.trim().isEmpty) return EmailProblem.required;
  final email = normalizeEmailAddress(value);
  if (email.length > 254) return EmailProblem.tooLong;
  final parts = email.split('@');
  if (parts.length != 2) return EmailProblem.malformed;
  final local = parts[0];
  final domain = parts[1];
  if (local.isEmpty || local.length > 64) return EmailProblem.malformed;
  if (!_localPart.hasMatch(local) ||
      local.startsWith('.') ||
      local.endsWith('.') ||
      local.contains('..')) {
    return EmailProblem.malformed;
  }
  final labels = domain.split('.');
  if (labels.length < 2) return EmailProblem.malformed;
  for (final label in labels) {
    if (label.isEmpty || label.length > 63 || !_domainLabel.hasMatch(label)) {
      return EmailProblem.malformed;
    }
  }
  return null;
}

final RegExp _localPart = RegExp(r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$");

final RegExp _domainLabel = RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$');

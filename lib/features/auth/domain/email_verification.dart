/// What the account says about its own address, and how to prove it.
///
/// Verification is a claim about the address, not a permission: nothing in the
/// app is gated on it. These types exist so the screen can state the fact and
/// offer the two ways to change it: ask the server to mail a link, or hand back
/// a token that arrived some other way.
library;

/// The address on file and the moment the server accepted proof of it.
class AccountEmailStatus {
  const AccountEmailStatus({required this.email, required this.verifiedAt});

  /// The server's address for this account; empty when it has none.
  final String email;

  /// When the address was verified, or null while it is unverified.
  final DateTime? verifiedAt;

  bool get isVerified => verifiedAt != null;

  /// Reads `GET /me`, whose payload is
  /// `{id, email, emailVerifiedAt, isEditor}`.
  ///
  /// An address with no `emailVerifiedAt` is *unverified*, not unknown: the
  /// server omits nothing here, and treating a parse gap as "verified" would be
  /// the one direction that lies to the reader.
  factory AccountEmailStatus.fromMe(Object? data) {
    if (data is! Map) {
      return const AccountEmailStatus(email: '', verifiedAt: null);
    }
    final email = data['email'];
    final verifiedAt = data['emailVerifiedAt'];
    return AccountEmailStatus(
      email: email is String ? email : '',
      verifiedAt: verifiedAt is String ? DateTime.tryParse(verifiedAt) : null,
    );
  }
}

/// The server's answer to "send me a verification link".
enum EmailVerificationRequest {
  /// Accepted: a fresh one-time link is on its way (202).
  sent,

  /// The account was already verified, so nothing was sent.
  alreadyVerified,
}

/// A no-wave verification token: 32 random bytes, base64url, no padding.
///
/// The server accepts exactly this shape (`tokenInput`), so a paste that is
/// merely close is refused here instead of spending one of the 30 per-window
/// attempts the endpoint allows per caller.
final _token = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// The `token=` value inside a mailed link, wherever it appears in a paste.
final _tokenInText = RegExp(r'token=([A-Za-z0-9_-]{43})(?![A-Za-z0-9_-])');

bool isVerificationToken(String value) => _token.hasMatch(value);

/// Pulls the token out of whatever the reader pasted.
///
/// The mailed link points at the web front end, so the app cannot claim it: the
/// address is verified in a browser unless the reader brings the code back by
/// hand. Accepting the whole link, a `token=` fragment or the bare code means
/// they can copy whichever part they have, and a paste that contains none of
/// them returns null rather than a guess.
String? extractVerificationToken(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  if (isVerificationToken(text)) return text;
  final found = _tokenInText.firstMatch(text);
  if (found != null) return found.group(1);
  // A single-line URL whose token survived as the last path segment, or a link
  // mangled by a mail client that dropped the `?token=`.
  final uri = Uri.tryParse(text);
  if (uri != null) {
    final fromQuery = uri.queryParameters['token'];
    if (fromQuery != null && isVerificationToken(fromQuery)) return fromQuery;
    for (final segment in uri.pathSegments) {
      if (isVerificationToken(segment)) return segment;
    }
  }
  return null;
}

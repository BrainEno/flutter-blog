import 'dart:convert';

/// A persisted no-wave session: the rotated token pair plus the identity
/// the app caches locally. The current backend can return an e-mail and
/// verification status in `GET /me`, but this client only reads the id;
/// the UI still uses the address entered at sign-in.
class NowaveSessionData {
  const NowaveSessionData({
    required this.userId,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    this.refreshTokenSpent = false,
  });

  final String userId;
  final String email;
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;

  /// Whether [refreshToken] may already have been rotated server-side.
  ///
  /// A rotation whose response never arrived (timeout, dropped connection,
  /// 5xx) cannot be told apart from a rotation that committed, and the
  /// backend revokes the whole session family when a rotated token is
  /// replayed. Once this is true the token is never sent again - not even
  /// after a restart - and the session can only continue on its access token
  /// until the user signs in again (#101).
  final bool refreshTokenSpent;

  /// Copy with the fields that change over a session's lifetime.
  NowaveSessionData copyWith({
    String? userId,
    String? email,
    String? accessToken,
    String? refreshToken,
    DateTime? accessExpiresAt,
    DateTime? refreshExpiresAt,
    bool? refreshTokenSpent,
  }) {
    return NowaveSessionData(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accessExpiresAt: accessExpiresAt ?? this.accessExpiresAt,
      refreshExpiresAt: refreshExpiresAt ?? this.refreshExpiresAt,
      refreshTokenSpent: refreshTokenSpent ?? this.refreshTokenSpent,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'userId': userId,
    'email': email,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'accessExpiresAt': accessExpiresAt.toIso8601String(),
    'refreshExpiresAt': refreshExpiresAt.toIso8601String(),
    'refreshTokenSpent': refreshTokenSpent,
  };

  static NowaveSessionData fromJson(Map<String, dynamic> map) =>
      NowaveSessionData(
        userId: map['userId'] as String? ?? '',
        email: map['email'] as String? ?? '',
        accessToken: map['accessToken'] as String? ?? '',
        refreshToken: map['refreshToken'] as String? ?? '',
        accessExpiresAt:
            DateTime.tryParse(map['accessExpiresAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        refreshExpiresAt:
            DateTime.tryParse(map['refreshExpiresAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        refreshTokenSpent: map['refreshTokenSpent'] as bool? ?? false,
      );
}

/// The token pair returned by `POST /auth/{register,login,refresh}`.
class NowaveTokenPair {
  const NowaveTokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;

  static NowaveTokenPair fromDataMap(Map<String, dynamic> map) {
    DateTime parse(String key) =>
        DateTime.tryParse(map[key] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return NowaveTokenPair(
      accessToken: map['accessToken'] as String? ?? '',
      refreshToken: map['refreshToken'] as String? ?? '',
      accessExpiresAt: parse('accessExpiresAt'),
      refreshExpiresAt: parse('refreshExpiresAt'),
    );
  }
}

/// Encodes [session] for a store that can only keep a string.
String encodeNowaveSession(NowaveSessionData session) =>
    jsonEncode(session.toJson());

/// Reads a session written by [encodeNowaveSession].
///
/// A corrupt payload (bad JSON, unparsable dates) reads as "no session"
/// rather than crashing every launch.
NowaveSessionData? decodeNowaveSession(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return NowaveSessionData.fromJson(decoded);
  } on FormatException {
    return null;
  }
}

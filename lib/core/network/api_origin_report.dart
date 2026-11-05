/// One line that answers "which backend is this binary actually talking to, and
/// may it use plain HTTP here?".
///
/// `API_BASE_URL` is compiled in with `--dart-define` (see `AppSecrets`), so
/// the origin is a property of the installed build, not of any file the user
/// can edit afterwards. When someone reports "it cannot reach the backend", the
/// first two questions are always the same - which origin did this build bake
/// in, and is cleartext allowed in this build mode - and both are answered by
/// this line, on the console and in the in-app diagnostics report.
///
/// Only the origin is printed: no userinfo, query, fragment or credentials.
String describeApiOrigin(Uri base, {required bool debugBuild}) {
  final origin = _originOf(base);
  if (base.scheme == 'https') return 'api origin: $origin (https)';
  final cleartext = debugBuild
      ? 'http, debug build allows cleartext'
      : 'http, release/profile builds block cleartext on Android and iOS';
  return 'api origin: $origin ($cleartext)';
}

/// `scheme://host:port` plus the configured path prefix, with everything that
/// could carry a secret removed.
String _originOf(Uri base) {
  // `Uri.host` strips the brackets an IPv6 literal needs in a URL.
  final host = base.host.contains(':') ? '[${base.host}]' : base.host;
  final authority = base.hasPort ? '$host:${base.port}' : host;
  final path = base.path.endsWith('/') && base.path.length > 1
      ? base.path.substring(0, base.path.length - 1)
      : (base.path == '/' ? '' : base.path);
  return '${base.scheme}://$authority$path';
}

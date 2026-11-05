/// The namespace a locally stored row belongs to.
///
/// Local data is scoped to the API origin it was created against, so an install
/// that is repointed at another backend cannot read, overwrite or send the
/// previous backend's rows. The convention matches the API client: scheme, host,
/// port and base path, never URL user-info, query strings or fragments.
String backendKeyOf(Uri uri) {
  if (!uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) {
    throw ArgumentError('A valid HTTP(S) API base URL is required.');
  }
  final path = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

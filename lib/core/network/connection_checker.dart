/// Signals whether the configured backend can be reached right now.
///
/// Every repository gates a request on this before falling back to a cached
/// answer, so the question it must answer is "can this device reach *our*
/// API" - never "can it reach some public endpoint". A public-internet probe
/// answered the second question and turned a blocked public internet (LAN,
/// emulator, private deployment, offline demo) into a pre-flight "no network"
/// without a single request being sent; that was issue #105.
///
/// [ApiConnectionChecker] is the only implementation wired into the app: it
/// asks `GET /api/v1/health` on the configured origin without credentials
/// when recent HTTP evidence is unavailable. A short positive lease is not a
/// guarantee that the next business request will succeed.
abstract interface class ConnectionChecker {
  Future<bool> get isConnected;
}

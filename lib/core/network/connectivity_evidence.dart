/// Non-authoritative evidence that the configured backend was reachable.
///
/// A completed HTTP response says nothing about credentials, authorization,
/// the next request, or whether a previous write committed. Transport errors
/// invalidate the optimistic hint; neither operation retries a request.
abstract interface class ConnectivityEvidence {
  void recordResponse(Uri requestUri);
  void recordTransportFailure(Uri requestUri);
}

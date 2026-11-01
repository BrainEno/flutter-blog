/// Identity snapshot for a multi-step operation. It contains no bearer token
/// and is a local safety fence, never an authorization claim sent to the API.
class NowaveSessionFence {
  const NowaveSessionFence({required this.userId, required this.generation});

  final String userId;
  final int generation;
}

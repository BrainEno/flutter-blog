/// The identity captured when a Markdown editor opens. Matching both the UI's
/// logged-in user and the authentication session prevents a late callback
/// from crossing an account or generation change. No token value is retained.
final class EditorSessionFence {
  const EditorSessionFence({required this.userId, required this.generation});

  final String? userId;
  final int generation;

  bool matches({
    required String? displayedUserId,
    required String? activeUserId,
    required String? accessToken,
    required int currentGeneration,
  }) {
    final owner = userId;
    return owner != null &&
        owner.isNotEmpty &&
        owner == owner.trim() &&
        displayedUserId == owner &&
        activeUserId == owner &&
        currentGeneration == generation &&
        !(accessToken?.isEmpty ?? true);
  }
}

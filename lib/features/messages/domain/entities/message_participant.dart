/// The public identity behind a user id, as far as a conversation needs it.
///
/// A conversation only carries ids. [MessageParticipantNames] resolves them to
/// names, and a name it could not resolve is `null` - the UI then says it does
/// not know who this is instead of printing a UUID as if it were a name.
class MessageParticipant {
  const MessageParticipant({
    required this.userId,
    required this.displayName,
    this.avatarUrl = '',
  });

  final String userId;

  /// Empty when the server has a profile but no name for it.
  final String displayName;

  final String avatarUrl;

  bool get hasName => displayName.trim().isNotEmpty;
}

import 'dart:async';

/// One article saved or unsaved by [userId], as the server confirmed it.
class SavedArticleChange {
  const SavedArticleChange({
    required this.userId,
    required this.blogId,
    required this.saved,
    required this.source,
  });

  /// The account the change belongs to.
  final String userId;

  final String blogId;

  /// The server's state after the change: true when the article is saved.
  final bool saved;

  /// Who published the change, so a page does not react to its own tap.
  final Object source;
}

/// App-wide news that the reader's saved articles changed.
///
/// Every page that shows like state owns its own `BlogLikedBloc`, and the
/// tabs are kept alive side by side. Without this, saving an article in the
/// home tab left the saved tab - built earlier and still on its old list -
/// saying "you have not saved anything" until the app was restarted.
class SavedArticlesChanges {
  final StreamController<SavedArticleChange> _changes =
      StreamController<SavedArticleChange>.broadcast();

  Stream<SavedArticleChange> get stream => _changes.stream;

  void publish(SavedArticleChange change) {
    if (!_changes.isClosed) _changes.add(change);
  }

  Future<void> dispose() => _changes.close();
}

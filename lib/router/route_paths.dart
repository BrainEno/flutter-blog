/// Every route address the app knows, in one place (#295).
///
/// Two kinds of value live here:
///
/// * [RouteSegments] are the `path:` patterns of the `GoRoute` tree in
///   `app_router.dart`. A nested route's pattern is relative to its parent.
/// * [RoutePaths] are the absolute locations pages navigate to. Builders such
///   as [RoutePaths.view] percent-encode every dynamic segment, so an id with a
///   reserved character can never split into two path segments or smuggle in
///   a query string.
///
/// A page never writes a location string itself:
/// `test/unit/core/route_paths_guard_test.dart` fails on a `context.push('/…')`
/// or `context.go('/…')` literal outside this file.
library;

/// `path:` patterns of the route tree, relative to the parent route.
abstract final class RouteSegments {
  /// The article reader. `:id` is the article's public slug.
  static const view = 'view/:id';

  /// A public author profile. `:userId` is the stable user id, not a slug.
  static const author = 'author/:userId';

  /// The public category catalog (search tab).
  static const categories = 'categories';

  /// One category's articles. `:slug` is the server's opaque taxonomy slug.
  static const category = 'category/:slug';

  /// One tag's articles. `:name` is the stored tag value.
  static const tag = 'tag/:name';

  /// The article editor (feed FAB and "my articles").
  static const editor = 'editor';

  /// Articles saved for offline reading (search tab).
  static const offlineLibrary = 'offline-library';

  /// The author directory (search tab).
  static const authors = 'authors';

  /// The signed-in user's own articles (profile tab).
  static const myArticles = 'my-articles';

  /// Deleted articles awaiting purge, below "my articles".
  static const recycleBin = 'recycle-bin';

  /// Editing the signed-in user's profile.
  static const editProfile = 'edit';

  static const changePassword = 'change-password';
  static const changeEmail = 'change-email';
  static const emailVerification = 'email-verification';

  /// The profile-tab copy of the About page (the public one is [RoutePaths.about]).
  static const about = 'about';

  static const notifications = 'notifications';
  static const messages = 'messages';

  /// One conversation below [messages]. `:id` is the conversation id.
  static const messageThread = ':id';

  static const history = 'history';
  static const publishQueue = 'publish-queue';
  static const sessions = 'sessions';

  /// Path parameter names, shared by the patterns above and their builders.
  static const idParam = 'id';
  static const userIdParam = 'userId';
  static const slugParam = 'slug';
  static const nameParam = 'name';
}

/// Absolute locations to navigate to.
abstract final class RoutePaths {
  // --- Root navigator (outside the tab shell) -----------------------------

  static const about = '/about';
  static const login = '/login';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';

  /// The public About page with the diagnostics report already open; the
  /// failed-sign-in snackbar links here.
  static const aboutDiagnostics = '$about?$diagnosticsQuery=1';

  /// The query parameter that opens the diagnostics report on [about].
  static const diagnosticsQuery = 'diagnostics';

  /// The query parameter carrying where to return after signing in.
  static const redirectQuery = 'redirect';

  /// The query parameter that asks the inbox to open a conversation with a
  /// user (an author page's "send a message").
  static const messageRecipientQuery = 'to';

  /// The pages that make up the sign-in flow. A redirect never points back
  /// into one of these, and a signed-in user is sent away from them.
  static const authFlow = [login, signup, forgotPassword, resetPassword];

  // --- Tab roots -----------------------------------------------------------

  static const feed = '/';
  static const search = '/search';
  static const saved = '/saved';
  static const profile = '/profile';

  /// Route prefixes that require a signed-in user. Everything else (feed,
  /// search, viewer, about and the auth pages) stays public.
  static const protectedPrefixes = [saved, profile, editor];

  // --- Feed branch (canonical, unprefixed) ---------------------------------

  /// The editor in the feed branch: a new article from the FAB.
  static const editor = '/${RouteSegments.editor}';

  /// The reader for article [id] in the feed branch. Resolve it with
  /// `shellBranchLocation` to keep a push inside the tab the reader is in.
  static String view(String id) => '/view/${Uri.encodeComponent(id)}';

  /// The public profile of [userId] in the feed branch.
  static String author(String userId) =>
      '/author/${Uri.encodeComponent(userId)}';

  /// The article list of tag [name] in the feed branch.
  static String tag(String name) => '/tag/${Uri.encodeComponent(name)}';

  /// The follower or following list of [userId]; [kind] is the
  /// `AuthorRelationshipKind` name, which is also the route segment.
  static String authorRelationships(String userId, String kind) =>
      '${author(userId)}/${Uri.encodeComponent(kind)}';

  // --- Search branch --------------------------------------------------------

  static const searchOfflineLibrary = '$search/${RouteSegments.offlineLibrary}';
  static const searchAuthors = '$search/${RouteSegments.authors}';
  static const searchCategories = '$search$categories';

  /// The category catalog relative to a branch; resolve it with
  /// `shellBranchLocation`. Only the search branch defines it.
  static const categories = '/${RouteSegments.categories}';

  /// One category's article list. Category routes only exist in the search
  /// branch; resolve it with `shellBranchLocation` for a nested push.
  static String category(String slug) =>
      '/category/${Uri.encodeComponent(slug)}';

  /// The reader opened from search results, inside the search tab.
  static String searchView(String id) => '$search${view(id)}';

  /// The reader opened from the offline library, so back returns to it.
  static String offlineLibraryView(String id) =>
      '$searchOfflineLibrary${view(id)}';

  // --- Saved branch ----------------------------------------------------------

  /// The reader opened from the saved list, inside the saved tab.
  static String savedView(String id) => '$saved${view(id)}';

  // --- Profile branch --------------------------------------------------------

  /// The editor in the profile branch: editing one of the user's articles or
  /// resuming a queued publish.
  static const profileEditor = '$profile/${RouteSegments.editor}';

  static const myArticles = '$profile/${RouteSegments.myArticles}';
  static const recycleBin = '$myArticles/${RouteSegments.recycleBin}';
  static const editProfile = '$profile/${RouteSegments.editProfile}';
  static const changePassword = '$profile/${RouteSegments.changePassword}';
  static const changeEmail = '$profile/${RouteSegments.changeEmail}';
  static const emailVerification =
      '$profile/${RouteSegments.emailVerification}';
  static const profileAbout = '$profile/${RouteSegments.about}';
  static const notifications = '$profile/${RouteSegments.notifications}';
  static const messages = '$profile/${RouteSegments.messages}';
  static const history = '$profile/${RouteSegments.history}';
  static const publishQueue = '$profile/${RouteSegments.publishQueue}';
  static const sessions = '$profile/${RouteSegments.sessions}';

  /// One conversation of the inbox.
  static String messageThread(String conversationId) =>
      '$messages/${Uri.encodeComponent(conversationId)}';

  /// The inbox, asked to open (or offer to start) a conversation with
  /// [userId] instead of creating a duplicate.
  static String messagesWith(String userId) =>
      '$messages?$messageRecipientQuery=${Uri.encodeComponent(userId)}';

  /// The reader inside the profile tab (notifications, history).
  static String profileView(String id) => '$profile${view(id)}';

  /// An author profile inside the profile tab.
  static String profileAuthor(String userId) => '$profile${author(userId)}';

  // --- Helpers -----------------------------------------------------------

  /// [path] with a `redirect` query naming where to return to afterwards.
  /// A `null` [target] leaves [path] untouched.
  static String withRedirect(String path, String? target) => target == null
      ? path
      : '$path?$redirectQuery=${Uri.encodeComponent(target)}';

  /// Whether [matchedLocation] sits below a route that needs a signed-in user.
  static bool isProtected(String matchedLocation) =>
      protectedPrefixes.any(matchedLocation.startsWith);
}

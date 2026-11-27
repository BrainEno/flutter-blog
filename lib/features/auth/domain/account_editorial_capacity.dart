/// Whether the signed-in account may arrange the editorial structures the
/// server treats as editorial: the featured shelf today, and the public
/// category taxonomy (`POST /taxonomies`) whenever the app grows that screen.
///
/// The three cases exist because the answer is not a boolean. no-wave added
/// `isEditor` to `GET /me` for exactly this purpose - its own comment says a
/// screen that offers editorial buttons and then answers `403` on click is a
/// worse answer than one that never offered them - and a deployment predating
/// that field answers `GET /me` perfectly well without it. Treating "absent"
/// as "denied" would silently lock an editor out of a server that would have
/// accepted them; treating it as "granted" would promise an entry that the
/// server may reject. So the client keeps the distinction and says so.
enum AccountEditorialCapacity {
  /// The server said this account is an editor.
  granted,

  /// The server said this account is not one.
  denied,

  /// The server answered without naming an editorial role at all: an older
  /// deployment, or one whose identity service cannot tell. An editorial
  /// screen may still be offered, but it must present the server as the one
  /// who decides, not this app.
  unknown,
}

/// Whether an editorial entry may be offered for [capacity].
///
/// Kept next to the enum so the entry point and any later one ask the same
/// question: `unknown` opens the screen - with its own caveat line - because
/// nobody has been told "no" yet.
bool offersEditorialEntry(AccountEditorialCapacity capacity) {
  return capacity != AccountEditorialCapacity.denied;
}

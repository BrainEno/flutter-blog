/// Resolves an author or article destination inside the active tab's branch.
/// The feed is the canonical root; the other three branches have their own
/// viewer and author routes so pushes do not switch tabs or lose their stacks.
String shellBranchLocation(Uri current, String destination) {
  assert(destination.startsWith('/') && !destination.startsWith('//'));
  final segments = current.pathSegments;
  final first = segments.isEmpty ? '' : segments.first;
  final prefix = switch (first) {
    'search' || 'saved' || 'profile' => '/$first',
    _ => '',
  };
  return '$prefix$destination';
}

import 'dart:io';

/// Every `.dart` file under [directory], sorted by path.
///
/// The source-scanning tests (`layering`, `service_locator_registration`,
/// `ui_copy_literals`, `a11y_text_scale`) each carried their own copy of this
/// walk. Sorting is part of the contract: offenders end up in assertion
/// messages, and a stable order keeps a failure diff readable across runs.
///
/// A missing directory yields an empty list, so a rule can assert on the
/// absence of its scope instead of throwing on a machine where the directory
/// was never checked out.
List<File> dartFilesUnder(String directory) {
  final root = Directory(directory);
  if (!root.existsSync()) return const [];
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

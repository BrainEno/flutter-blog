import 'dart:convert';
import 'dart:typed_data';

import 'package:belog/core/config/app_limits.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_local_images.dart';
import 'package:belog/features/blog/domain/notion_import/notion_markdown.dart';
import 'package:belog/features/blog/domain/notion_import/notion_zip.dart';

/// A file the author chose on the device: a no-wave JSON bundle, a Markdown
/// page exported from Notion, a database CSV or an image beside it, or the
/// ZIP Notion's "Export → Markdown & CSV" produces.
class NotionImportFile {
  const NotionImportFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Why a choice could not become a bundle at all. The sheet words each kind;
/// [name] is the file it is about, when there is one.
enum NotionImportSourceError {
  /// More than may be chosen at once, more Markdown and CSV than one
  /// request carries, or a converted bundle too large for a request.
  tooLarge,

  /// Not `.json`, `.md`, `.csv`, `.zip` or an image - or more than one JSON
  /// bundle, or a JSON bundle mixed with other files.
  unsupportedFile,

  /// A JSON file that is not a no-wave bundle.
  invalidBundle,

  /// A ZIP that is cut short, split, encrypted, ZIP64 or otherwise unreadable.
  invalidZip,

  /// A ZIP listing more entries than the reader opens.
  tooManyEntries,

  /// More than 200 Markdown pages.
  tooManyPages,

  /// A Markdown file that is not UTF-8 text.
  invalidText,

  /// Two pages with the same identity: the same export chosen twice.
  duplicatePage,

  /// Nothing that can become an article: no page has a title.
  noPages,

  /// Only database CSVs: they carry properties, not articles.
  csvOnly,
}

class NotionImportSourceException implements Exception {
  const NotionImportSourceException(this.error, {this.name = ''});

  final NotionImportSourceError error;
  final String name;

  @override
  String toString() => 'NotionImportSourceException(${error.name}, $name)';
}

/// What was read: the bundle to preview, how many Markdown files went into
/// it (zero for a JSON bundle), what the conversion could not carry, and the
/// local images its pages use, which are uploaded before a preview.
class NotionImportSource {
  const NotionImportSource({
    required this.bundle,
    this.warnings = const [],
    this.markdownFiles = 0,
    this.images = const {},
  });

  final NotionBundle bundle;
  final List<NotionMarkdownWarning> warnings;
  final int markdownFiles;
  final Map<String, NotionLocalImage> images;
}

/// Reads the author's chosen files into one bundle, the way the no-wave
/// desk does: a single `.json` is a bundle as it is; any number of `.md`,
/// `.csv` and `.zip` files are converted on the device, with the images
/// chosen beside them or inside the ZIPs. Nothing is uploaded here.
NotionImportSource readNotionImportFiles(List<NotionImportFile> files) {
  final total = files.fold<int>(0, (sum, file) => sum + file.bytes.length);
  if (total > AppLimits.notionImportMaxSourceBytes) {
    throw const NotionImportSourceException(NotionImportSourceError.tooLarge);
  }
  bool named(NotionImportFile file, String extension) =>
      file.name.toLowerCase().endsWith(extension);
  if (files.length == 1 && named(files.single, '.json')) {
    final file = files.single;
    final String text;
    try {
      text = utf8.decode(file.bytes);
    } on FormatException {
      throw NotionImportSourceException(
        NotionImportSourceError.invalidBundle,
        name: file.name,
      );
    }
    return NotionImportSource(bundle: _parseBundle(text, file.name));
  }
  final entries = <NotionMarkdownEntry>[];
  final images = <String, NotionLocalImage>{};
  var text = 0;
  for (final file in files) {
    if (named(file, '.md') || named(file, '.csv')) {
      // The same budget a ZIP's Markdown and CSV have.
      text += file.bytes.length;
      if (text > NotionBundle.maxRequestBytes) {
        throw const NotionImportSourceException(
          NotionImportSourceError.tooLarge,
        );
      }
      entries.add(NotionMarkdownEntry(file.name, decodeMarkdown(file)));
    } else if (named(file, '.zip')) {
      final contents = readNotionZip(file.bytes, name: file.name);
      entries.addAll(contents.entries);
      for (final MapEntry(:key, :value) in contents.images.entries) {
        images.putIfAbsent(key, () => value);
      }
    } else if (isNotionImageFileName(file.name)) {
      images.putIfAbsent(
        file.name,
        () => NotionLocalImage(
          name: file.name,
          size: file.bytes.length,
          read: () => file.bytes,
        ),
      );
    } else {
      throw NotionImportSourceException(
        NotionImportSourceError.unsupportedFile,
        name: file.name,
      );
    }
  }
  final converted = markdownEntriesToBundle(entries, images: images);
  return NotionImportSource(
    bundle: converted.bundle,
    warnings: converted.warnings,
    markdownFiles: entries
        .where((entry) => !entry.name.toLowerCase().endsWith('.csv'))
        .length,
    images: converted.images,
  );
}

/// Reads pasted text: a JSON bundle when it is one, otherwise one Markdown
/// page - what Notion puts on the clipboard when a page's blocks are copied.
///
/// A pasted page has no file name, so its identity is its title: pasting
/// the same title again previews an update of the same article, and a new
/// title is a new article.
NotionImportSource readPastedNotionText(String input) {
  final text = input.replaceFirst('\uFEFF', '').trim();
  if (text.startsWith('{')) {
    return NotionImportSource(bundle: _parseBundle(text, ''));
  }
  final converted = markdownEntriesToBundle([
    NotionMarkdownEntry(pastedMarkdownName(text), text, pasted: true),
  ]);
  return NotionImportSource(
    bundle: converted.bundle,
    warnings: converted.warnings,
    markdownFiles: 1,
  );
}

NotionBundle _parseBundle(String text, String name) {
  try {
    return NotionBundle.parse(text);
  } on FormatException catch (error) {
    throw NotionImportSourceException(
      error.message == 'size'
          ? NotionImportSourceError.tooLarge
          : NotionImportSourceError.invalidBundle,
      name: name,
    );
  }
}

/// Strict UTF-8, like the desk: a mis-encoded file is refused rather than
/// imported with replacement characters in it.
String decodeMarkdown(NotionImportFile file) {
  try {
    return utf8.decode(file.bytes);
  } on FormatException {
    throw NotionImportSourceException(
      NotionImportSourceError.invalidText,
      name: file.name,
    );
  }
}

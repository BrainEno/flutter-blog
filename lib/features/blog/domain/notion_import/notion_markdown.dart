import 'dart:convert';

import 'package:belog/core/config/app_limits.dart';
import 'package:belog/features/blog/domain/notion_import/notion_csv.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_source.dart';
import 'package:belog/features/blog/domain/notion_import/notion_local_images.dart';
import 'package:belog/features/blog/domain/notion_import/notion_markdown_warning.dart';
import 'package:belog/features/blog/domain/notion_import/notion_values.dart';
import 'package:markdown/markdown.dart' as md;

export 'package:belog/features/blog/domain/notion_import/notion_markdown_warning.dart';
export 'package:belog/features/blog/domain/notion_import/notion_values.dart';

/// One Markdown page: the file it came from, or the name a pasted page is
/// given, and its text.
class NotionMarkdownEntry {
  const NotionMarkdownEntry(this.name, this.text, {this.pasted = false});

  final String name;
  final String text;

  /// Pasted rather than read from a file: identified by its title.
  final bool pasted;
}

class NotionMarkdownBundle {
  const NotionMarkdownBundle(
    this.bundle,
    this.warnings, {
    this.images = const {},
  });

  final NotionBundle bundle;
  final List<NotionMarkdownWarning> warnings;

  /// The local images the pages use, by the key their blocks carry
  /// (see `notionLocalImageKey`). They are uploaded before a preview.
  final Map<String, NotionLocalImage> images;
}

/// The image a page's local reference [src] means: the path relative to the
/// page's own folder, as Notion writes it, or - for pages and images chosen
/// as separate files - the file name alone, when only one image has it.
NotionLocalImage? resolveNotionLocalImage(
  Map<String, NotionLocalImage> images,
  String page,
  String src,
) {
  if (images.isEmpty) return null;
  var path = src.split(RegExp('[?#]')).first;
  try {
    path = Uri.decodeComponent(path);
  } catch (_) {
    // Not percent-encoded after all: use it as written.
  }
  final normalPage = page.replaceAll(r'\', '/');
  final slash = normalPage.lastIndexOf('/');
  final folder = slash < 0 ? '' : normalPage.substring(0, slash + 1);
  final relative = path.replaceAll(r'\', '/');
  final parts = <String>[];
  for (final part in '$folder$relative'.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  final exact = images[parts.join('/')];
  if (exact != null || parts.isEmpty) return exact;
  final same = images.values
      .where((image) => notionBaseName(image.name) == parts.last)
      .take(2)
      .toList();
  return same.length == 1 ? same.single : null;
}

/// The name a pasted page goes by: its title, as if it were a file, so the
/// server scopes it to the author like any Markdown file without a page ID.
String pastedMarkdownName(String text) {
  final first = text
      .replaceAll('\r\n', '\n')
      .split('\n')
      .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
  final heading = _heading.firstMatch(first);
  final title = (heading?.group(1) ?? first).trim().replaceAll(
    RegExp(r'[\\/]'),
    '-',
  );
  // Leaves room for the extension inside the file-name limit.
  const room = AppLimits.notionMarkdownMaxFileName - 8;
  final short = title.length > room ? title.substring(0, room) : title;
  return '${short.isEmpty ? 'untitled' : short}.md';
}

final _heading = RegExp(r'^#\s+(.+?)\s*#*\s*$');
final _pageId = RegExp(r'(?:^|\s)([a-f0-9]{32})\.md$', caseSensitive: false);
final _relationId = RegExp(r'\b([a-f0-9]{32})\.md\b', caseSensitive: false);
final _property = RegExp(r'^([^:]+):\s*(.*)$');
final _notionImageHost = RegExp(
  r'^prod-files-secure\.s3(?:\.us-west-2)?\.amazonaws\.com$',
  caseSensitive: false,
);
final _web = RegExp(r'^https?://', caseSensitive: false);
const _knownProperties = {
  'Date',
  'Excerpt',
  'FeaturedImage',
  'Published',
  'Rank',
  'Slug',
  'Tags',
  'English',
  'Parent item',
};

String _canonical(String id) =>
    '${id.substring(0, 8)}-${id.substring(8, 12)}-${id.substring(12, 16)}-'
    '${id.substring(16, 20)}-${id.substring(20)}';

/// Converts Markdown pages - Notion's own "Markdown & CSV" export, or text
/// copied out of a page - into the bundle the import endpoint takes, exactly
/// as the no-wave desk does (`packages/web-ui/src/lib/notion-markdown.ts`),
/// so the same file gets the same identity from the web and from the app.
///
/// Each page needs `# Title` on its first line. A leading run of Notion
/// properties (`Date:`, `Tags:`, `Published:` ...) is read as properties;
/// ordinary prose is never taken for one. A Notion page ID at the end of the
/// file name is the page's identity; without one the file name is, scoped to
/// the author by the server.
NotionMarkdownBundle markdownEntriesToBundle(
  List<NotionMarkdownEntry> entries, {
  Map<String, NotionLocalImage> images = const {},
}) {
  final markdown = [
    for (final entry in entries)
      if (!entry.name.toLowerCase().endsWith('.csv')) entry,
  ];
  if (markdown.length > NotionBundle.maxPages) {
    throw const NotionImportSourceException(
      NotionImportSourceError.tooManyPages,
    );
  }
  final warnings = <NotionMarkdownWarning>[];
  final tables = indexNotionTables(notionTablesOf(entries), warnings);
  final used = <String, NotionLocalImage>{};
  final pages = <Map<String, dynamic>>[];
  final ids = <String>{};
  for (final entry in markdown) {
    final page = _MarkdownPage(entry, warnings, images, used).read();
    if (page == null) continue;
    final properties = page['properties'] as Map<String, dynamic>;
    fillNotionPageFromTables(
      properties: properties,
      title: (properties['Name']['title'][0]['plain_text'] as String).trim(),
      source: entry.name,
      tables: tables,
      warnings: warnings,
    );
    final id = page['id'] as String;
    if (!ids.add(id)) {
      throw NotionImportSourceException(
        NotionImportSourceError.duplicatePage,
        name: entry.name,
      );
    }
    pages.add(page);
  }
  for (final page in pages) {
    final properties = page['properties'] as Map<String, dynamic>;
    for (final key in const ['English', 'Parent item']) {
      final relation = properties[key];
      if (relation is Map<String, dynamic> &&
          (relation['relation'] as List).any(
            (link) => !ids.contains((link as Map)['id']),
          )) {
        warnings.add(
          NotionMarkdownWarning(
            NotionMarkdownWarningKind.relationMissing,
            page['source'] as String,
            detail: key,
          ),
        );
      }
    }
  }
  if (pages.isEmpty) {
    throw NotionImportSourceException(
      markdown.isEmpty
          ? NotionImportSourceError.csvOnly
          : NotionImportSourceError.noPages,
    );
  }
  final bundle = {
    'version': 1,
    'database': {'id': '', 'title': 'Notion Markdown export'},
    'pages': [
      for (final page in pages)
        {
          'id': page['id'],
          'properties': page['properties'],
          'blocks': page['blocks'],
        },
    ],
  };
  try {
    return NotionMarkdownBundle(
      NotionBundle.parse(jsonEncode(bundle)),
      warnings,
      images: used,
    );
  } on FormatException {
    throw const NotionImportSourceException(NotionImportSourceError.tooLarge);
  }
}

class _MarkdownPage {
  _MarkdownPage(this.entry, this.warnings, this.images, this.used);

  final NotionMarkdownEntry entry;
  final List<NotionMarkdownWarning> warnings;
  final Map<String, NotionLocalImage> images;
  final Map<String, NotionLocalImage> used;
  final blocks = <Map<String, dynamic>>[];

  void _warn(NotionMarkdownWarningKind kind, {String detail = ''}) =>
      warnings.add(NotionMarkdownWarning(kind, entry.name, detail: detail));

  void _block(String type, Map<String, dynamic> data) =>
      blocks.add({'type': type, type: data});

  Map<String, dynamic>? read() {
    final lines = entry.text
        .replaceFirst('\uFEFF', '')
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .split('\n');
    // A pasted page may start after blank lines; a file must not.
    var first = 0;
    if (entry.pasted) {
      while (first < lines.length && lines[first].trim().isEmpty) {
        first++;
      }
    }
    final heading = first < lines.length
        ? _heading.firstMatch(lines[first])
        : null;
    // A page exported without its "# title" line still has a name: the
    // file's. It is used, and said so; only a page with neither is skipped.
    // Pasted text has no file name to fall back on.
    final headingTitle = heading?.group(1)?.trim() ?? '';
    final title = headingTitle.isNotEmpty
        ? headingTitle
        : entry.pasted
        ? ''
        : notionFileTitle(entry.name);
    if (title.isEmpty) {
      _warn(NotionMarkdownWarningKind.missingTitle);
      return null;
    }
    final basename = notionBaseName(entry.name);
    final id = _pageId.firstMatch(basename)?.group(1)?.toLowerCase();
    if (id == null &&
        (basename.isEmpty ||
            basename.length > AppLimits.notionMarkdownMaxFileName)) {
      _warn(NotionMarkdownWarningKind.invalidFileName);
      return null;
    }
    if (heading == null) {
      _warn(NotionMarkdownWarningKind.titleFromFileName, detail: title);
    }
    if (id == null) {
      _warn(
        entry.pasted
            ? NotionMarkdownWarningKind.pastedIdentity
            : NotionMarkdownWarningKind.fileNameIdentity,
      );
    }
    final properties = <String, dynamic>{
      'Name': {
        'type': 'title',
        'title': [notionRichText(title)],
      },
    };
    var i = heading == null ? first : first + 1;
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
    var inProperties = false;
    for (; i < lines.length; i++) {
      final match = _property.firstMatch(lines[i]);
      if (match == null ||
          (!inProperties && !_knownProperties.contains(match.group(1)))) {
        break;
      }
      inProperties = true;
      final key = match.group(1)!;
      final value = match.group(2)!.trim();
      if (!_knownProperties.contains(key)) {
        _warn(NotionMarkdownWarningKind.propertyIgnored, detail: key);
        continue;
      }
      _readProperty(properties, key, value);
    }
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    _emit(document.parseLines(lines.sublist(i)));
    return {
      'id': id != null
          ? _canonical(id)
          : 'markdown-file:${Uri.encodeComponent(basename)}',
      'source': entry.name,
      'properties': properties,
      'blocks': blocks,
    };
  }

  void _readProperty(
    Map<String, dynamic> properties,
    String key,
    String value,
  ) {
    switch (key) {
      case 'Slug' || 'Excerpt':
        properties[key] = notionTextProperty(value);
      case 'Published':
        final checked = notionBoolean(value);
        if (checked != null) {
          properties[key] = {'type': 'checkbox', 'checkbox': checked};
        } else {
          _warn(NotionMarkdownWarningKind.publishedUnrecognized);
        }
      case 'Tags':
        properties[key] = {
          'type': 'multi_select',
          'multi_select': [
            for (final name in value.split(','))
              if (name.trim().isNotEmpty) {'name': name.trim()},
          ],
        };
      case 'Date':
        final date = notionDateStart(value);
        if (date != null) {
          properties[key] = {
            'type': 'date',
            'date': {'start': date.start},
          };
          if (date.range) _warn(NotionMarkdownWarningKind.dateRange);
        } else {
          _warn(NotionMarkdownWarningKind.dateUnrecognized);
        }
      case 'FeaturedImage' when value.isNotEmpty:
        properties[key] = {
          'type': 'files',
          'files': [
            {
              'type': 'external',
              'external': {'url': value},
            },
          ],
        };
      case 'English' || 'Parent item' when value.isNotEmpty:
        var decoded = value;
        try {
          decoded = Uri.decodeComponent(value);
        } on ArgumentError {
          // Keep the original text.
        }
        final ids = [
          for (final match in _relationId.allMatches(decoded))
            {'id': _canonical(match.group(1)!.toLowerCase())},
        ];
        if (ids.isNotEmpty) {
          properties[key] = {'type': 'relation', 'relation': ids};
        } else {
          _warn(NotionMarkdownWarningKind.relationUnrecognized, detail: key);
        }
      default:
        // Rank has no field on an article; it is read and ignored.
        break;
    }
  }

  void _emit(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is md.Text) {
        final text = _stripTags(node.text).trim();
        if (text.isEmpty) continue;
        _warn(NotionMarkdownWarningKind.otherFlattened);
        _block('paragraph', {
          'rich_text': [notionRichText(text)],
        });
        continue;
      }
      if (node is! md.Element) continue;
      final children = node.children ?? const <md.Node>[];
      switch (node.tag) {
        case 'p':
          if (children.length == 1 &&
              children.single is md.Element &&
              (children.single as md.Element).tag == 'img') {
            _image(children.single as md.Element);
          } else {
            _block('paragraph', {'rich_text': _inline(children, const {})});
          }
        case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
          final depth = int.parse(node.tag.substring(1));
          if (depth > 3) _warn(NotionMarkdownWarningKind.headingLowered);
          _block('heading_${depth > 3 ? 3 : depth}', {
            'rich_text': _inline(children, const {}),
          });
        case 'pre':
          final code = children.whereType<md.Element>().firstOrNull;
          final text = (code ?? node).textContent.replaceFirst(
            RegExp(r'\n$'),
            '',
          );
          final language = RegExp(
            r'language-(\S+)',
          ).firstMatch(code?.attributes['class'] ?? '')?.group(1);
          if (text.length > AppLimits.notionMarkdownMaxCodeChars) {
            _warn(NotionMarkdownWarningKind.codeTooLong);
          }
          _block('code', {
            'rich_text': [notionRichText(text)],
            'language': language ?? 'text',
          });
        case 'blockquote':
          _block('quote', {
            'rich_text': [notionRichText(_plainBlocks(children))],
          });
        case 'ul' || 'ol':
          _list(node, ordered: node.tag == 'ol');
        case 'hr':
          _block('divider', {});
        case 'table':
          _warn(NotionMarkdownWarningKind.tableFlattened);
          for (final row in _rows(node)) {
            _block('paragraph', {
              'rich_text': [notionRichText(row)],
            });
          }
        default:
          final text = node.textContent.trim();
          _warn(NotionMarkdownWarningKind.otherFlattened);
          if (text.isNotEmpty) {
            _block('paragraph', {
              'rich_text': [notionRichText(text)],
            });
          }
      }
    }
  }

  void _image(md.Element image) {
    final src = image.attributes['src'] ?? '';
    final alt = image.attributes['alt'] ?? '';
    final url = _web.hasMatch(src) ? Uri.tryParse(src) : null;
    if (url == null) {
      _localImage(src, alt);
      return;
    }
    if (_notionImageHost.hasMatch(url.host)) {
      _block('image', {
        'type': 'file',
        'file': {'url': src},
        'caption': [notionRichText(alt)],
      });
    } else if (url.queryParameters.keys.any(
      (key) => key.toLowerCase().startsWith('x-amz-'),
    )) {
      _warn(NotionMarkdownWarningKind.signedImageDropped);
    } else {
      _block('image', {
        'type': 'external',
        'external': {'url': src},
        'caption': [notionRichText(alt)],
      });
    }
  }

  /// An image file of the export: kept as a stand-in the app uploads before
  /// a preview, or reported when it cannot be.
  void _localImage(String src, String alt) {
    final image = resolveNotionLocalImage(images, entry.name, src);
    if (image == null) {
      _warn(
        NotionMarkdownWarningKind.localImageMissing,
        detail: alt.isNotEmpty ? alt : notionBaseName(src),
      );
      return;
    }
    final name = notionBaseName(image.name);
    if (!isNotionUploadableImageName(image.name)) {
      _warn(NotionMarkdownWarningKind.localImageUnsupported, detail: name);
      return;
    }
    if (image.size > AppLimits.mediaUploadMaxBytes) {
      _warn(NotionMarkdownWarningKind.localImageTooLarge, detail: name);
      return;
    }
    used[image.name] = image;
    _block('image', {
      'type': 'external',
      'external': {'url': notionLocalImageUrl(image.name)},
      'caption': [notionRichText(alt)],
    });
  }

  void _list(md.Element list, {required bool ordered}) {
    var simplified = false;
    for (final item
        in (list.children ?? const <md.Node>[]).whereType<md.Element>().where(
          (child) => child.tag == 'li',
        )) {
      final children = item.children ?? const <md.Node>[];
      final blockChildren = children.whereType<md.Element>().where(
        (child) =>
            const {'p', 'ul', 'ol', 'pre', 'blockquote'}.contains(child.tag),
      );
      if (blockChildren.any((child) => child.tag != 'p') ||
          blockChildren.length > 1) {
        simplified = true;
      }
      final text = _plainBlocks(children);
      if (text.trim().isNotEmpty) {
        _block(ordered ? 'numbered_list_item' : 'bulleted_list_item', {
          'rich_text': [notionRichText(text)],
        });
      }
    }
    if (simplified) _warn(NotionMarkdownWarningKind.listSimplified);
  }

  /// Rows of a table as `cell | cell`, header first.
  static List<String> _rows(md.Element table) {
    final rows = <String>[];
    void walk(md.Element element) {
      if (element.tag == 'tr') {
        rows.add(
          (element.children ?? const <md.Node>[])
              .map((cell) => cell.textContent.trim())
              .join(' | '),
        );
        return;
      }
      for (final child
          in (element.children ?? const <md.Node>[]).whereType<md.Element>()) {
        walk(child);
      }
    }

    walk(table);
    return rows.where((row) => row.trim().isNotEmpty).toList();
  }

  /// The text of block children, one line per block.
  static String _plainBlocks(List<md.Node> nodes) {
    final parts = <String>[];
    final inline = StringBuffer();
    for (final node in nodes) {
      if (node is md.Element &&
          const {
            'p',
            'ul',
            'ol',
            'li',
            'pre',
            'blockquote',
          }.contains(node.tag)) {
        if (inline.isNotEmpty) {
          parts.add(inline.toString());
          inline.clear();
        }
        parts.add(
          node.tag == 'ul' || node.tag == 'ol'
              ? _plainBlocks(node.children ?? const [])
              : node.textContent,
        );
      } else if (node is md.Element && node.tag == 'input') {
        // A task-list checkbox: its state has nowhere to live.
        continue;
      } else {
        inline.write(node.textContent);
      }
    }
    if (inline.isNotEmpty) parts.add(inline.toString());
    return parts
        .map((part) => part.trim())
        .where((p) => p.isNotEmpty)
        .join('\n');
  }

  List<Map<String, dynamic>> _inline(
    List<md.Node> nodes,
    Map<String, bool> marks,
  ) {
    final runs = <Map<String, dynamic>>[];
    for (final node in nodes) {
      if (node is md.Text) {
        if (node.text.isNotEmpty) {
          runs.add({'plain_text': node.text, 'annotations': marks});
        }
        continue;
      }
      if (node is! md.Element) continue;
      final children = node.children ?? const <md.Node>[];
      switch (node.tag) {
        case 'img':
          _warn(NotionMarkdownWarningKind.inlineImageDropped);
        case 'br':
          runs.add({'plain_text': '\n', 'annotations': marks});
        case 'a':
          final href = node.attributes['href'] ?? '';
          final safe = _web.hasMatch(href) ? href : null;
          if (safe == null) {
            _warn(NotionMarkdownWarningKind.relativeLinkDropped);
          }
          for (final run in _inline(children, marks)) {
            runs.add(safe == null ? run : {...run, 'href': safe});
          }
        case 'code':
          final text = node.textContent;
          if (text.isNotEmpty) {
            runs.add({
              'plain_text': text,
              'annotations': {...marks, 'code': true},
            });
          }
        case 'strong':
          runs.addAll(_inline(children, {...marks, 'bold': true}));
        case 'em':
          runs.addAll(_inline(children, {...marks, 'italic': true}));
        case 'del':
          runs.addAll(_inline(children, {...marks, 'strikethrough': true}));
        default:
          runs.addAll(_inline(children, marks));
      }
    }
    return runs;
  }

  static String _stripTags(String html) => html
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ');
}

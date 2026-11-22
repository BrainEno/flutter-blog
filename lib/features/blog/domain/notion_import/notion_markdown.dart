import 'dart:convert';

import 'package:belog/core/config/app_limits.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_source.dart';
import 'package:markdown/markdown.dart' as md;

/// One Markdown page: the file it came from, or the name a pasted page is
/// given, and its text.
class NotionMarkdownEntry {
  const NotionMarkdownEntry(this.name, this.text, {this.pasted = false});

  final String name;
  final String text;

  /// Pasted rather than read from a file: identified by its title.
  final bool pasted;
}

/// Something the conversion could not carry exactly. The import still goes
/// ahead; the sheet lists these before the preview so nothing is lost
/// silently.
enum NotionMarkdownWarningKind {
  /// Skipped: the first line is not a `# Title`.
  missingTitle,

  /// Skipped: no Notion page ID and an unusable file name.
  invalidFileName,

  /// No Notion page ID in the file name: identified by the name instead,
  /// so a renamed file imports as a new article.
  fileNameIdentity,

  /// Pasted: identified by its title, so a new title is a new article.
  pastedIdentity,

  /// A Notion property the site has no field for ([detail] names it).
  propertyIgnored,

  /// `Published` was neither yes nor no: treated as a draft.
  publishedUnrecognized,

  /// `Date` could not be read: the server's default applies.
  dateUnrecognized,

  /// `English` or `Parent item` ([detail]) named no page this reader knows.
  relationUnrecognized,

  /// `English` or `Parent item` ([detail]) points to a page not chosen.
  relationMissing,

  /// An image inside a line of text was left out.
  inlineImageDropped,

  /// A link to another page of the export, not a web address: the text
  /// stays, the link does not.
  relativeLinkDropped,

  /// A fourth-level or deeper heading was raised to the third level.
  headingLowered,

  /// A code block longer than the site keeps.
  codeTooLong,

  /// An image file inside the export ([detail] is its caption): images in
  /// the ZIP are not uploaded yet.
  localImageDropped,

  /// A signed image address that cannot be copied safely.
  signedImageDropped,

  /// A nested list or a list item with several paragraphs was flattened.
  listSimplified,

  /// A table became one paragraph per row.
  tableFlattened,

  /// A callout, HTML or other construct was kept as plain text.
  otherFlattened,
}

class NotionMarkdownWarning {
  const NotionMarkdownWarning(this.kind, this.source, {this.detail = ''});

  final NotionMarkdownWarningKind kind;

  /// The file (or pasted title) it is about.
  final String source;
  final String detail;
}

class NotionMarkdownBundle {
  const NotionMarkdownBundle(this.bundle, this.warnings);

  final NotionBundle bundle;
  final List<NotionMarkdownWarning> warnings;
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
final _monthDay = RegExp(r'^([A-Za-z]+)\.?\s+(\d{1,2}),?\s+(\d{4})\b');
const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];
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

String _basename(String name) => name.split(RegExp(r'[\\/]')).last;

Map<String, dynamic> _rich(String text) => {'plain_text': text};

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
  List<NotionMarkdownEntry> entries,
) {
  if (entries.length > NotionBundle.maxPages) {
    throw const NotionImportSourceException(
      NotionImportSourceError.tooManyPages,
    );
  }
  final warnings = <NotionMarkdownWarning>[];
  final pages = <Map<String, dynamic>>[];
  final ids = <String>{};
  for (final entry in entries) {
    final page = _MarkdownPage(entry, warnings).read();
    if (page == null) continue;
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
    throw const NotionImportSourceException(NotionImportSourceError.noPages);
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
    );
  } on FormatException {
    throw const NotionImportSourceException(NotionImportSourceError.tooLarge);
  }
}

class _MarkdownPage {
  _MarkdownPage(this.entry, this.warnings);

  final NotionMarkdownEntry entry;
  final List<NotionMarkdownWarning> warnings;
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
    if (heading == null) {
      _warn(NotionMarkdownWarningKind.missingTitle);
      return null;
    }
    final basename = _basename(entry.name);
    final id = _pageId.firstMatch(basename)?.group(1)?.toLowerCase();
    if (id == null &&
        (basename.isEmpty ||
            basename.length > AppLimits.notionMarkdownMaxFileName)) {
      _warn(NotionMarkdownWarningKind.invalidFileName);
      return null;
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
        'title': [_rich(heading.group(1)!.trim())],
      },
    };
    var i = first + 1;
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
        properties[key] = {
          'type': 'rich_text',
          'rich_text': [_rich(value)],
        };
      case 'Published':
        if (RegExp(r'^(yes|true)$', caseSensitive: false).hasMatch(value)) {
          properties[key] = {'type': 'checkbox', 'checkbox': true};
        } else if (RegExp(
          r'^(no|false)$',
          caseSensitive: false,
        ).hasMatch(value)) {
          properties[key] = {'type': 'checkbox', 'checkbox': false};
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
        final date = _date(value);
        if (date != null) {
          properties[key] = {
            'type': 'date',
            'date': {'start': date.toIso8601String()},
          };
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

  /// Notion writes a day as `October 8, 2026`, with no zone: the calendar
  /// day is the fact, read as UTC midnight so every reader sees that day. A
  /// time after it is ignored for the same reason. Anything else ISO-like is
  /// read as written.
  static DateTime? _date(String value) {
    final match = _monthDay.firstMatch(value);
    if (match != null) {
      final name = match.group(1)!.toLowerCase();
      final month = name.length < 3
          ? -1
          : _months.indexOf(name.substring(0, 3));
      final day = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      if (month < 0) return null;
      final date = DateTime.utc(year, month + 1, day);
      return date.day == day ? date : null;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    final zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
    return zoned
        ? parsed.toUtc()
        : DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
          );
  }

  void _emit(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is md.Text) {
        final text = _stripTags(node.text).trim();
        if (text.isEmpty) continue;
        _warn(NotionMarkdownWarningKind.otherFlattened);
        _block('paragraph', {
          'rich_text': [_rich(text)],
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
            'rich_text': [_rich(text)],
            'language': language ?? 'text',
          });
        case 'blockquote':
          _block('quote', {
            'rich_text': [_rich(_plainBlocks(children))],
          });
        case 'ul' || 'ol':
          _list(node, ordered: node.tag == 'ol');
        case 'hr':
          _block('divider', {});
        case 'table':
          _warn(NotionMarkdownWarningKind.tableFlattened);
          for (final row in _rows(node)) {
            _block('paragraph', {
              'rich_text': [_rich(row)],
            });
          }
        default:
          final text = node.textContent.trim();
          _warn(NotionMarkdownWarningKind.otherFlattened);
          if (text.isNotEmpty) {
            _block('paragraph', {
              'rich_text': [_rich(text)],
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
      _warn(NotionMarkdownWarningKind.localImageDropped, detail: alt);
      return;
    }
    if (_notionImageHost.hasMatch(url.host)) {
      _block('image', {
        'type': 'file',
        'file': {'url': src},
        'caption': [_rich(alt)],
      });
    } else if (url.queryParameters.keys.any(
      (key) => key.toLowerCase().startsWith('x-amz-'),
    )) {
      _warn(NotionMarkdownWarningKind.signedImageDropped);
    } else {
      _block('image', {
        'type': 'external',
        'external': {'url': src},
        'caption': [_rich(alt)],
      });
    }
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
          'rich_text': [_rich(text)],
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

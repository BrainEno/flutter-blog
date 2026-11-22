import 'package:belog/features/blog/domain/notion_import/notion_markdown.dart';

/// One CSV export of a Notion database view: the first column is the title
/// property.
class NotionTable {
  const NotionTable(this.name, this.header, this.rows);

  final String name;
  final List<String> header;
  final List<List<String>> rows;
}

/// RFC 4180 as Notion writes it: a UTF-8 BOM, CRLF line ends, quoted cells
/// that may contain commas, doubled quotes and line breaks. Blank lines are
/// dropped.
List<List<String>> parseNotionCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  final src = text.replaceFirst('\uFEFF', '');
  void endRow() {
    row.add(cell.toString());
    cell.clear();
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < src.length; i++) {
    final c = src[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < src.length && src[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"' && cell.isEmpty) {
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\r') {
      if (i + 1 < src.length && src[i + 1] == '\n') i++;
      endRow();
    } else if (c == '\n') {
      endRow();
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// The database CSVs among [entries]. Notion writes two per database:
/// "X.csv" with the view's visible columns and "X_all.csv" with every
/// property; when both are present only `_all` is read, so a hidden Date
/// column is not mistaken for none.
List<NotionTable> notionTablesOf(List<NotionMarkdownEntry> entries) {
  final csv = entries.where((e) => _isCsv(e.name)).toList();
  final allSuffix = RegExp(r'_all\.csv$', caseSensitive: false);
  String keyOf(String name) =>
      name.replaceFirst(allSuffix, '.csv').toLowerCase();
  final hasAll = {
    for (final e in csv)
      if (allSuffix.hasMatch(e.name)) keyOf(e.name),
  };
  return [
    for (final e in csv)
      if (allSuffix.hasMatch(e.name) || !hasAll.contains(keyOf(e.name)))
        if (parseNotionCsv(e.text) case [final header, ...final rows])
          NotionTable('${notionFileTitle(e.name)}.csv', [
            for (final h in header) h.trim(),
          ], rows),
  ];
}

bool _isCsv(String name) => name.toLowerCase().endsWith('.csv');

/// Property -> the column names a Notion database or a Chinese spreadsheet
/// uses for it, as the desk reads them. Matched trimmed and lower-cased.
const _columnNames = <String, List<String>>{
  'Date': [
    'date',
    '\u65e5\u671f',
    '\u53d1\u5e03\u65e5\u671f',
    '\u53d1\u8868\u65e5\u671f',
    '\u521b\u4f5c\u65e5\u671f',
  ],
  'Excerpt': [
    'excerpt',
    'summary',
    '\u6458\u8981',
    '\u6458\u5f55',
    '\u7b80\u4ecb',
  ],
  'FeaturedImage': [
    'featuredimage',
    'featured image',
    'cover',
    '\u5c01\u9762',
    '\u5c01\u9762\u56fe',
    '\u9898\u56fe',
  ],
  'Published': [
    'published',
    '\u5df2\u53d1\u5e03',
    '\u53d1\u5e03',
    '\u662f\u5426\u53d1\u5e03',
    '\u5df2\u53d1\u8868',
  ],
  'Slug': ['slug', '\u522b\u540d', '\u7f51\u5740\u522b\u540d', '\u77ed\u94fe'],
  'Tags': ['tags', 'tag', '\u6807\u7b7e'],
};

/// Columns that are known and deliberately not carried, so they are not
/// reported as unknown.
const _ignoredColumns = {'rank', '\u6392\u5e8f'};

/// One table with its header mapped once.
class NotionTableIndex {
  const NotionTableIndex(this.table, this.columns, {required this.checkbox});

  final NotionTable table;

  /// Property -> column index.
  final Map<String, int> columns;

  /// Whether the Published column holds only checkbox values.
  final bool checkbox;
}

/// Map each table's header once, and say once which of its columns are not
/// imported.
List<NotionTableIndex> indexNotionTables(
  List<NotionTable> tables,
  List<NotionMarkdownWarning> warnings,
) {
  return [for (final table in tables) _index(table, warnings)];
}

NotionTableIndex _index(
  NotionTable table,
  List<NotionMarkdownWarning> warnings,
) {
  final columns = <String, int>{};
  final unknown = <String>[];
  for (var index = 1; index < table.header.length; index++) {
    // Column 0 is the title property.
    final name = table.header[index];
    final lower = name.trim().toLowerCase();
    final key = _columnNames.entries
        .where((entry) => entry.value.contains(lower))
        .map((entry) => entry.key)
        .firstOrNull;
    if (key != null && !columns.containsKey(key)) {
      columns[key] = index;
    } else if (!_ignoredColumns.contains(lower)) {
      unknown.add(name.isEmpty ? '#${index + 1}' : name);
    }
  }
  // Only a column whose every non-empty value is a checkbox value is a
  // checkbox: a Status select named "Published" holding "Draft" is not, and
  // reading its "Yes" rows as published would publish by accident.
  final published = columns['Published'];
  final values = published == null
      ? const <String>[]
      : [
          for (final row in table.rows)
            if (_cell(row, published).isNotEmpty) _cell(row, published),
        ];
  final checkbox =
      values.isNotEmpty && values.every((v) => notionBoolean(v) != null);
  if (published != null && !checkbox) {
    warnings.add(
      NotionMarkdownWarning(
        NotionMarkdownWarningKind.csvPublishedNotCheckbox,
        table.name,
        table: table.name,
        detail: table.header[published],
      ),
    );
  }
  if (unknown.isNotEmpty) {
    warnings.add(
      NotionMarkdownWarning(
        NotionMarkdownWarningKind.csvColumnsIgnored,
        table.name,
        table: table.name,
        detail: unknown.join(', '),
      ),
    );
  }
  return NotionTableIndex(table, columns, checkbox: checkbox);
}

String _cell(List<String> row, int index) =>
    index < row.length ? row[index].trim() : '';

bool _isEmptyProperty(Object? value) {
  if (value is! Map) return true;
  final richText = value['rich_text'];
  if (richText is List) {
    return richText.every(
      (run) => ((run as Map)['plain_text'] as String? ?? '').trim().isEmpty,
    );
  }
  final multiSelect = value['multi_select'];
  if (multiSelect is List) return multiSelect.isEmpty;
  final files = value['files'];
  if (files is List) return files.isEmpty;
  return false;
}

/// Fill a page's *empty* properties from its database row; a value already
/// in the Markdown is never overwritten. The row is found by the page's `#`
/// title, then by the file name without its Notion ID - both trimmed. A name
/// shared by two rows is ambiguous and fills nothing. Every page says what
/// happened.
void fillNotionPageFromTables({
  required Map<String, dynamic> properties,
  required String title,
  required String source,
  required List<NotionTableIndex> tables,
  required List<NotionMarkdownWarning> warnings,
}) {
  if (tables.isEmpty) return;
  void warn(
    NotionMarkdownWarningKind kind, {
    String detail = '',
    String table = '',
  }) => warnings.add(
    NotionMarkdownWarning(kind, source, detail: detail, table: table),
  );

  List<(NotionTableIndex, List<String>)> find(String name) => [
    for (final table in tables)
      for (final row in table.table.rows)
        if (row.isNotEmpty && row.first.trim() == name) (table, row),
  ];
  var hits = title.isEmpty ? <(NotionTableIndex, List<String>)>[] : find(title);
  final base = notionFileTitle(source);
  if (hits.isEmpty && base.isNotEmpty && base != title) hits = find(base);
  if (hits.isEmpty) {
    warn(NotionMarkdownWarningKind.csvNoRow);
    return;
  }
  if (hits.length > 1) {
    warn(NotionMarkdownWarningKind.csvAmbiguousRow, detail: '${hits.length}');
    return;
  }
  final (index, row) = hits.single;
  final filled = <String>[];
  String cell(String key) {
    final column = index.columns[key];
    return column == null ? '' : _cell(row, column);
  }

  for (final key in _columnNames.keys) {
    final value = cell(key);
    if (value.isEmpty || !_isEmptyProperty(properties[key])) continue;
    switch (key) {
      case 'Slug' || 'Excerpt':
        properties[key] = notionTextProperty(value);
      case 'Tags':
        final tags = [
          for (final name in value.split(RegExp('[,\uff0c\u3001]')))
            if (name.trim().isNotEmpty) {'name': name.trim()},
        ];
        if (tags.isNotEmpty) {
          properties[key] = {'type': 'multi_select', 'multi_select': tags};
        }
      case 'Published':
        if (!index.checkbox) continue;
        properties[key] = {
          'type': 'checkbox',
          'checkbox': notionBoolean(value),
        };
      case 'Date':
        final date = notionDateStart(value);
        if (date == null) {
          warn(NotionMarkdownWarningKind.dateUnrecognized, detail: value);
          continue;
        }
        properties[key] = {
          'type': 'date',
          'date': {'start': date.start},
        };
        if (date.range) warn(NotionMarkdownWarningKind.dateRange);
      case 'FeaturedImage':
        if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(value)) {
          warn(NotionMarkdownWarningKind.csvLocalCover);
          continue;
        }
        properties[key] = {
          'type': 'files',
          'files': [
            {
              'type': 'external',
              'external': {'url': value.split(RegExp(r'\s*,\s*')).first},
            },
          ],
        };
    }
    if (properties[key] != null) filled.add(key);
  }
  if (filled.isEmpty) {
    warn(NotionMarkdownWarningKind.csvNothingToFill, table: index.table.name);
  } else {
    warn(
      NotionMarkdownWarningKind.csvFilled,
      detail: filled.join(', '),
      table: index.table.name,
    );
  }
}

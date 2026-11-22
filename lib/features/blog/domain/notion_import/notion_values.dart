// Reading single Notion property values the same way the no-wave desk does,
// shared by the Markdown converter and the database CSV reader.

/// The last path segment of an export entry's name.
String notionBaseName(String name) => name.split(RegExp(r'[\\/]')).last;

/// One plain rich-text part, the shape every Notion text field holds.
Map<String, dynamic> notionRichText(String text) => {'plain_text': text};

/// Notion writes a checkbox as Yes/No; other tools and hand-edited exports
/// use true/false, Y/N, the Chinese yes/no, and Notion's own API dump uses
/// __YES__/__NO__. Anything else is not a checkbox value, so a caller can
/// tell a real checkbox column from a Status select called "Published".
bool? notionBoolean(String value) {
  final v = value.trim();
  if (RegExp(
    '^(yes|true|y|__yes__|\u662f)\$',
    caseSensitive: false,
  ).hasMatch(v)) {
    return true;
  }
  if (RegExp(
    '^(no|false|n|__no__|\u5426)\$',
    caseSensitive: false,
  ).hasMatch(v)) {
    return false;
  }
  return null;
}

const _monthNames = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

/// A calendar day in any of the spellings a Notion export or a Chinese
/// spreadsheet produces, read as **UTC midnight** - the desk's
/// `notionDateStart` and the API's `notionDateToInstant` rule, so the same
/// file gives the same date from the web and from the app. A full ISO
/// timestamp is honoured exactly; one without a zone is UTC. A Notion range
/// ("A -> B") keeps its start and says so. Anything else is not a date.
({String start, bool range})? notionDateStart(String raw) {
  final parts = raw.split(RegExp('\\s*\u2192\\s*'));
  final value = parts.first.trim();
  final range = parts.length > 1;
  ({String start, bool range})? day(int year, int month, int date) {
    final at = DateTime.utc(year, month, date);
    return at.year == year && at.month == month && at.day == date
        ? (start: at.toIso8601String(), range: range)
        : null;
  }

  final numeric =
      RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(value) ??
      RegExp(
        '^(\\d{4})\\s*\u5e74\\s*(\\d{1,2})\\s*\u6708\\s*(\\d{1,2})\\s*\u65e5?\$',
      ).firstMatch(value);
  if (numeric != null) {
    return day(
      int.parse(numeric.group(1)!),
      int.parse(numeric.group(2)!),
      int.parse(numeric.group(3)!),
    );
  }
  final named = RegExp(
    r'^([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})$',
  ).firstMatch(value);
  if (named != null) {
    final name = named.group(1)!.toLowerCase();
    final month = _monthNames.indexWhere(
      (full) => full.startsWith(name.substring(0, 3)),
    );
    if (month < 0 ||
        !(name.length == 3 || _monthNames[month].startsWith(name))) {
      return null;
    }
    return day(
      int.parse(named.group(3)!),
      month + 1,
      int.parse(named.group(2)!),
    );
  }
  if (RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?([zZ]|[+-]\d{2}:?\d{2})?$',
  ).hasMatch(value)) {
    final zoned = RegExp(r'[zZ]$|[+-]\d{2}:?\d{2}$').hasMatch(value);
    final parsed = DateTime.tryParse(zoned ? value : '${value}Z');
    if (parsed == null) return null;
    // Millisecond precision, as JavaScript writes an instant.
    final instant = DateTime.fromMillisecondsSinceEpoch(
      parsed.millisecondsSinceEpoch,
      isUtc: true,
    );
    return (start: instant.toIso8601String(), range: range);
  }
  return null;
}

/// "Wall 0123...cdef.md" -> "Wall": what a person would call the file.
String notionFileTitle(String name) => notionBaseName(name)
    .replaceFirst(RegExp(r'\.(md|csv)$', caseSensitive: false), '')
    .replaceFirst(RegExp(r'_all$', caseSensitive: false), '')
    .replaceFirst(RegExp(r'\s+[a-f0-9]{32}$', caseSensitive: false), '')
    .trim();

Map<String, dynamic> notionTextProperty(String text) => {
  'type': 'rich_text',
  'rich_text': [notionRichText(text)],
};

import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:belog/core/config/app_limits.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_source.dart';
import 'package:belog/features/blog/domain/notion_import/notion_markdown.dart';

const _endOfDirectory = 0x06054b50;
const _directoryEntry = 0x02014b50;
const _localHeader = 0x04034b50;
const _endRecordLength = 22;
const _directoryEntryLength = 46;
const _localHeaderLength = 30;
const _maxComment = 0xffff;
const _stored = 0;
const _deflated = 8;
const _encryptedFlag = 0x1;
const _utf8NameFlag = 0x800;
const _chunk = 64 * 1024;

/// The Markdown pages inside a Notion export ZIP, read in memory.
///
/// Bounded the way the no-wave desk bounds it, so a hostile or broken file
/// costs at most what a real export does: the archive must end in a complete
/// directory (a cut-short download is refused, not read as fewer articles);
/// ZIP64, split and encrypted archives are refused; it may list at most
/// [AppLimits.notionZipMaxEntries] entries and 200 Markdown pages; and all
/// Markdown inflated from it, nested part archives included, stops at the
/// 8 MiB a request can carry - counted while inflating, so a small file that
/// claims to be small but inflates without end is stopped at the limit.
/// Nothing is written to disk and no path inside the archive is used for
/// anything but the page's name. Folders, images and other files are skipped,
/// as are macOS resource forks.
List<NotionMarkdownEntry> readNotionZip(Uint8List bytes, {String name = ''}) {
  final budget = _Budget();
  final entries = <NotionMarkdownEntry>[];
  _readZip(bytes, name, budget, entries, depth: 0);
  return entries;
}

class _Budget {
  int inflated = 0;
}

Never _invalid(String name) => throw NotionImportSourceException(
  NotionImportSourceError.invalidZip,
  name: name,
);

void _readZip(
  Uint8List bytes,
  String name,
  _Budget budget,
  List<NotionMarkdownEntry> entries, {
  required int depth,
}) {
  if (bytes.length > NotionBundle.maxRequestBytes) {
    throw NotionImportSourceException(
      NotionImportSourceError.tooLarge,
      name: name,
    );
  }
  final data = ByteData.sublistView(bytes);
  int u16(int at) => data.getUint16(at, Endian.little);
  int u32(int at) => data.getUint32(at, Endian.little);

  // The end record, whose comment must run exactly to the end of the file.
  var end = -1;
  final lowest = bytes.length - _endRecordLength - _maxComment;
  for (var p = bytes.length - _endRecordLength; p >= 0 && p >= lowest; p--) {
    if (u32(p) == _endOfDirectory &&
        p + _endRecordLength + u16(p + 20) == bytes.length) {
      end = p;
      break;
    }
  }
  if (end < 0) _invalid(name);
  final count = u16(end + 10);
  final directorySize = u32(end + 12);
  final directoryStart = u32(end + 16);
  if (u16(end + 4) != 0 ||
      u16(end + 6) != 0 ||
      u16(end + 8) != count ||
      count == 0xffff ||
      directorySize == 0xffffffff ||
      directoryStart == 0xffffffff ||
      directoryStart + directorySize != end) {
    _invalid(name);
  }
  if (count > AppLimits.notionZipMaxEntries) {
    throw NotionImportSourceException(
      NotionImportSourceError.tooManyEntries,
      name: name,
    );
  }

  var at = directoryStart;
  for (var i = 0; i < count; i++) {
    if (at + _directoryEntryLength > end || u32(at) != _directoryEntry) {
      _invalid(name);
    }
    final flags = u16(at + 8);
    final method = u16(at + 10);
    final compressed = u32(at + 20);
    final size = u32(at + 24);
    final nameLength = u16(at + 28);
    final extraLength = u16(at + 30);
    final commentLength = u16(at + 32);
    final localStart = u32(at + 42);
    final nameEnd = at + _directoryEntryLength + nameLength;
    if (nameEnd > end) _invalid(name);
    final rawName = bytes.sublist(at + _directoryEntryLength, nameEnd);
    final entryName = flags & _utf8NameFlag != 0
        ? utf8.decode(rawName, allowMalformed: true)
        : _decodeName(rawName);
    at = nameEnd + extraLength + commentLength;
    if (at > end) _invalid(name);

    final lower = entryName.toLowerCase();
    final isMarkdown = lower.endsWith('.md');
    final isArchive =
        lower.endsWith('.zip') && depth < AppLimits.notionZipMaxDepth;
    if ((!isMarkdown && !isArchive) ||
        RegExp(r'(^|/)__MACOSX/').hasMatch(entryName)) {
      continue;
    }
    if (flags & _encryptedFlag != 0 ||
        compressed == 0xffffffff ||
        size == 0xffffffff) {
      _invalid(name);
    }
    if (isMarkdown && entries.length >= NotionBundle.maxPages) {
      throw NotionImportSourceException(
        NotionImportSourceError.tooManyPages,
        name: name,
      );
    }

    if (localStart + _localHeaderLength > directoryStart ||
        u32(localStart) != _localHeader) {
      _invalid(name);
    }
    final dataStart =
        localStart +
        _localHeaderLength +
        u16(localStart + 26) +
        u16(localStart + 28);
    final dataEnd = dataStart + compressed;
    if (dataEnd > directoryStart) _invalid(name);
    final payload = Uint8List.sublistView(bytes, dataStart, dataEnd);

    // A nested part archive is read whole, then walked with the same
    // inflation budget; only its Markdown counts toward the budget.
    final limit = isArchive
        ? NotionBundle.maxRequestBytes
        : NotionBundle.maxRequestBytes - budget.inflated;
    final content = switch (method) {
      _stored => payload,
      _deflated => _inflate(payload, limit, name),
      _ => _invalid(name),
    };
    if (content.length != size) _invalid(name);
    if (isArchive) {
      _readZip(content, entryName, budget, entries, depth: depth + 1);
      continue;
    }
    budget.inflated += content.length;
    if (budget.inflated > NotionBundle.maxRequestBytes) {
      throw NotionImportSourceException(
        NotionImportSourceError.tooLarge,
        name: name,
      );
    }
    entries.add(
      NotionMarkdownEntry(
        entryName,
        decodeMarkdown(NotionImportFile(name: entryName, bytes: content)),
      ),
    );
  }
}

/// Names without the UTF-8 flag: Notion writes UTF-8 either way, so try it
/// strictly first and fall back to Latin-1 rather than refusing the file.
String _decodeName(List<int> raw) {
  try {
    return utf8.decode(raw);
  } on FormatException {
    return latin1.decode(raw);
  }
}

/// Raw DEFLATE, fed in pieces, stopped as soon as the output passes [limit].
Uint8List _inflate(Uint8List input, int limit, String name) {
  final sink = _CappedSink(limit, name);
  final conversion = ZLibDecoder(raw: true).startChunkedConversion(sink);
  try {
    for (var offset = 0; offset < input.length; offset += _chunk) {
      final stop = offset + _chunk < input.length
          ? offset + _chunk
          : input.length;
      conversion.add(Uint8List.sublistView(input, offset, stop));
    }
    conversion.close();
  } on NotionImportSourceException {
    rethrow;
  } catch (_) {
    _invalid(name);
  }
  return sink.takeBytes();
}

class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.limit, this.name);

  final int limit;
  final String name;
  final _bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (_bytes.length + chunk.length > limit) {
      throw NotionImportSourceException(
        NotionImportSourceError.tooLarge,
        name: name,
      );
    }
    _bytes.add(chunk);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _bytes.takeBytes();
}

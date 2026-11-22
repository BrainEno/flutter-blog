import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

/// One entry for [buildZip].
class ZipEntry {
  const ZipEntry(
    this.name,
    this.content, {
    this.deflate = true,
    this.encrypted = false,
    this.declaredSize,
  });

  ZipEntry.text(String name, String text, {bool deflate = true})
    : this(name, utf8.encode(text), deflate: deflate);

  final String name;
  final List<int> content;
  final bool deflate;
  final bool encrypted;

  /// Overrides the uncompressed size written to the headers, to build a
  /// file that lies about itself.
  final int? declaredSize;
}

/// A minimal ZIP writer for tests: stored or raw-DEFLATE entries, UTF-8
/// names, a central directory and an end record. No CRCs - the reader under
/// test does not check them.
Uint8List buildZip(List<ZipEntry> entries, {String comment = ''}) {
  final out = BytesBuilder();
  final directory = BytesBuilder();
  void u16(BytesBuilder b, int v) =>
      b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  void u32(BytesBuilder b, int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());

  for (final entry in entries) {
    final name = utf8.encode(entry.name);
    final data = entry.deflate
        ? ZLibEncoder(raw: true).convert(entry.content)
        : entry.content;
    final size = entry.declaredSize ?? entry.content.length;
    final flags = 0x800 | (entry.encrypted ? 0x1 : 0);
    final method = entry.deflate ? 8 : 0;
    final offset = out.length;
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, flags);
    u16(out, method);
    u32(out, 0);
    u32(out, 0);
    u32(out, data.length);
    u32(out, size);
    u16(out, name.length);
    u16(out, 0);
    out
      ..add(name)
      ..add(data);

    u32(directory, 0x02014b50);
    u16(directory, 20);
    u16(directory, 20);
    u16(directory, flags);
    u16(directory, method);
    u32(directory, 0);
    u32(directory, 0);
    u32(directory, data.length);
    u32(directory, size);
    u16(directory, name.length);
    u16(directory, 0);
    u16(directory, 0);
    u16(directory, 0);
    u16(directory, 0);
    u32(directory, 0);
    u32(directory, offset);
    directory.add(name);
  }
  final start = out.length;
  final directoryBytes = directory.takeBytes();
  out.add(directoryBytes);
  final commentBytes = utf8.encode(comment);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, entries.length);
  u16(out, entries.length);
  u32(out, directoryBytes.length);
  u32(out, start);
  u16(out, commentBytes.length);
  out.add(commentBytes);
  return out.takeBytes();
}

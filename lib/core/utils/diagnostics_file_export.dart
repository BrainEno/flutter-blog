import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_logger.dart';

/// What the about page calls when the user taps "export log file". The
/// default is [DiagnosticsFileExporter.exportAndShare]; widget tests inject a
/// recorder instead of touching the file system or the share sheet.
typedef DiagnosticsExportAction =
    Future<void> Function({required String report, required String shareTitle});

/// Hands a prepared file to the platform share sheet.
typedef DiagnosticsFileSharer = Future<void> Function(XFile file, String title);

Future<void> _shareWithSystemSheet(XFile file, String title) async {
  await SharePlus.instance.share(ShareParams(title: title, files: [file]));
}

/// Writes a reviewed diagnostics report to a text file and opens the system
/// share sheet with it (issue #306).
///
/// Privacy contract (AGENTS.md "Secrets, configuration and external
/// services"): this runs only when the user taps the export action in the
/// diagnostics dialog. Nothing is uploaded, scheduled or retried; the user
/// picks the destination in the share sheet, exactly like the profile data
/// export (`UserDataExporter`).
///
/// The file lives in the app's temporary directory - a scratch area the OS
/// may reclaim - because the canonical copy is wherever the user sends it.
/// Earlier exports are deleted before a new one is written, so diagnostics
/// do not pile up on the device. The newest file is kept until the next
/// export because some share targets read it after the sheet has returned.
class DiagnosticsFileExporter {
  DiagnosticsFileExporter({
    Future<Directory> Function()? temporaryDirectory,
    DiagnosticsFileSharer? share,
    DateTime Function()? clock,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _share = share ?? _shareWithSystemSheet,
       _clock = clock ?? DateTime.now;

  /// Every exported file starts with this prefix; it is also how stale
  /// exports are recognised and removed.
  static const String filePrefix = 'nowave-diagnostics-';

  /// Exported files are plain UTF-8 text.
  static const String mimeType = 'text/plain';

  final Future<Directory> Function() _temporaryDirectory;
  final DiagnosticsFileSharer _share;
  final DateTime Function() _clock;

  /// `nowave-diagnostics-YYYYMMDD-HHMMSS.txt`, in local time so the name
  /// matches what the user sees on their clock.
  static String fileNameFor(DateTime instant) {
    String two(int value) => value.toString().padLeft(2, '0');
    final local = instant.toLocal();
    return '$filePrefix'
        '${local.year}${two(local.month)}${two(local.day)}-'
        '${two(local.hour)}${two(local.minute)}${two(local.second)}.txt';
  }

  /// True for a file name this exporter produced.
  static bool isExportFileName(String name) =>
      name.startsWith(filePrefix) && name.endsWith('.txt');

  /// Writes [report] to a fresh file after removing earlier exports.
  Future<File> writeReport(String report) async {
    final directory = await _temporaryDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    await _removeStaleExports(directory);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${fileNameFor(_clock())}',
    );
    await file.writeAsString(report, flush: true);
    return file;
  }

  /// Writes the report and opens the share sheet with it. Failures propagate
  /// so the caller can tell the user; nothing is retried in the background.
  Future<void> exportAndShare({
    required String report,
    required String shareTitle,
  }) async {
    final file = await writeReport(report);
    await _share(XFile(file.path, mimeType: mimeType), shareTitle);
  }

  Future<void> _removeStaleExports(Directory directory) async {
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!isExportFileName(name)) continue;
      try {
        await entity.delete();
      } on FileSystemException catch (error) {
        // Best effort: a leftover scratch file must not block the export the
        // user asked for. The OS reclaims the temporary directory anyway.
        AppLogger.debug('stale diagnostics export kept: ${error.runtimeType}');
      }
    }
  }
}

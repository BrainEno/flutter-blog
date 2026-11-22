import 'dart:async';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/domain/reader/reader_text_size.dart';
import 'package:flutter/foundation.dart';

/// The reader's text size for the whole app: every open article listens to
/// the same value, so a change made in one is already true in the next.
///
/// It starts at [ReaderTextSize.standard] and [load]s the saved choice once;
/// boot starts that read so the first article opens at the right size. A
/// choice made before the read finishes wins over it. Storage failures are
/// logged and otherwise ignored: the size still applies for this session.
class ReaderTextSizeController extends ValueNotifier<ReaderTextSize> {
  ReaderTextSizeController(this._store) : super(ReaderTextSize.standard);

  final ReaderTextSizeStore _store;
  Future<void>? _loading;
  bool _chosen = false;

  /// Reads the saved size; later calls share the first read.
  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final saved = await _store.load();
      if (!_chosen) value = saved;
    } catch (e, stackTrace) {
      AppLogger.error(
        'reading the reader text size failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Applies [size] now and keeps it for next time.
  void select(ReaderTextSize size) {
    _chosen = true;
    if (size == value) return;
    value = size;
    unawaited(_save(size));
  }

  Future<void> _save(ReaderTextSize size) async {
    try {
      await _store.save(size);
    } catch (e, stackTrace) {
      AppLogger.error(
        'saving the reader text size failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}

/// The article body size for [size].
double readerBodySize(ReaderTextSize size) =>
    NoWaveTypeScale.readerBodySizes[size.index];

/// How much larger than standard the text at [size] is set.
double readerTextFactor(ReaderTextSize size) =>
    readerBodySize(size) / NoWaveTypeScale.articleBody;

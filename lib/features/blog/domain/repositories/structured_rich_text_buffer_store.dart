import 'package:belog/features/blog/domain/editing/structured_rich_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';

/// Exact parent plus raw local buffer; neither is a remote concurrency token.
class StructuredRichTextBufferRecovery {
  const StructuredRichTextBufferRecovery({
    required this.parent,
    required this.buffer,
    required this.storageJson,
  });
  final StructuredBodyRecovery parent;
  final StructuredRichTextBuffer buffer;
  final String storageJson;
}

/// A shared exclusive local buffer slot. Callers must separately fence account,
/// route and session, and require an explicit recovery/apply/discard decision.
abstract interface class StructuredRichTextBufferStore {
  Future<StructuredRichTextBufferRecovery?> loadRichTextBuffer(
    StructuredBodyKey key,
  );
  Future<StructuredRichTextBufferRecovery?> createRichTextBuffer({
    required StructuredBodyRecovery expected,
    required StructuredRichTextBuffer buffer,
    required DateTime updatedAt,
  });
  Future<StructuredRichTextBufferRecovery?> replaceRichTextBuffer({
    required StructuredRichTextBufferRecovery expected,
    required StructuredRichTextBuffer buffer,
    required DateTime updatedAt,
  });
  Future<StructuredBodyRecovery?> applyRichTextBuffer({
    required StructuredRichTextBufferRecovery expected,
    required DateTime updatedAt,
  });
  Future<StructuredBodyRecovery?> discardRichTextBuffer({
    required StructuredRichTextBufferRecovery expected,
    required DateTime updatedAt,
  });
}

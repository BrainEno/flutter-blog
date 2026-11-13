import 'package:belog/features/blog/domain/editing/structured_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';

/// One exact local recovery revision and its raw text buffer. The opaque raw
/// value participates in local CAS; it is not a server version or credential.
class StructuredTextBufferRecovery {
  const StructuredTextBufferRecovery({
    required this.parent,
    required this.buffer,
    required this.storageJson,
  });
  final StructuredBodyRecovery parent;
  final StructuredTextBuffer buffer;
  final String storageJson;
}

/// Separate from publication and from the normal editor. All changes must use
/// the exact original backend/account/article/locale, parent revision and raw
/// buffer CAS. Corrupt or unsupported values are never treated as absent.
abstract interface class StructuredTextBufferStore {
  Future<StructuredTextBufferRecovery?> loadTextBuffer(StructuredBodyKey key);
  Future<StructuredTextBufferRecovery?> createTextBuffer({
    required StructuredBodyRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  });
  Future<StructuredTextBufferRecovery?> replaceTextBuffer({
    required StructuredTextBufferRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  });
  Future<StructuredBodyRecovery?> applyTextBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  });
  Future<StructuredBodyRecovery?> discardTextBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  });
}

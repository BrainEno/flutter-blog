import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_rich_text_buffer_store.dart';

/// One backend-scoped object for parent and rich buffer reads and CAS writes.
abstract interface class StructuredRichTextSessionStore
    implements StructuredBodyRecoveryStore, StructuredRichTextBufferStore {}

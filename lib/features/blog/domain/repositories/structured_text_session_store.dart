import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_buffer_store.dart';

/// A single backend-scoped implementation for both snapshots and buffers.
/// Using one object prevents a coordinator from accidentally reading from one
/// backend and writing a buffer into another backend's recovery store.
abstract interface class StructuredTextSessionStore
    implements StructuredBodyRecoveryStore, StructuredTextBufferStore {}

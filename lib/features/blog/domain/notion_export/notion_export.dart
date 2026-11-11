import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:fpdart/fpdart.dart';

/// One exported edition and the origin of its page identifier.
class NotionExportEdition {
  const NotionExportEdition({
    required this.locale,
    required this.fromNotion,
    required this.issues,
  });
  final String locale;
  final bool fromNotion;
  final List<String> issues;
}

/// This is account-private content, held in memory only until the sheet closes.
class NotionExportResult {
  const NotionExportResult({
    required this.missing,
    required this.bundleJson,
    required this.issues,
    required this.editions,
  });
  final bool missing;
  final String bundleJson;
  final List<String> issues;
  final List<NotionExportEdition> editions;
}

abstract interface class NotionExportRepository {
  Future<Either<Failure, NotionExportResult>> export({
    required String slug,
    required NowaveSessionFence sessionFence,
  });
}

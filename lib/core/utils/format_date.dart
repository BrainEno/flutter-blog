/// Locale-aware date label without an intl dependency: Chinese UI, so
/// `2026年10月30日`. Kept dependency-free on purpose (issue #24: no more
/// `DateTime.toString().substring(0, 10)` slicing in widgets).
String formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.year}年${local.month}月${local.day}日';
}

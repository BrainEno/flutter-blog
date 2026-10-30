import 'package:belog/l10n/app_localizations.dart';

/// Reading-time label for an article, localized (issue #24).
///
/// The estimate stays locale-independent - Chinese characters and English
/// words are counted at their own reading speeds - while the label itself
/// comes from the ARB catalogs, including English plural forms. An empty
/// or sub-minute text reads as "约 1 分钟" / "About 1 minute".
String calculateReadingTime(AppLocalizations l10n, String articleText) {
  // Round once before splitting hours/minutes: 59.6 minutes is 1 hour,
  // never "60 minutes" or "1 hour 60 minutes". Keep the existing minimum
  // estimate of one minute for an empty or very short article.
  final rounded = _estimateReadingMinutes(articleText).round();
  final minutes = rounded < 1 ? 1 : rounded;
  if (minutes < 60) return l10n.readingTimeMinutes(minutes);
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (remainder == 0) return l10n.readingTimeHours(hours);
  return l10n.readingTimeHoursAndMinutes(hours, remainder);
}

double _estimateReadingMinutes(String articleText) {
  if (articleText.isEmpty) {
    return 0;
  }

  // Define reading speed for English and Chinese (words/characters per minute)
  const int englishReadingSpeed = 220; // Words per minute
  const int chineseReadingSpeed =
      300; // Characters per minute (Chinese characters are denser)

  // Regular expressions to count words/characters
  final englishWordRegex = RegExp(r'\b\w+\b'); // Matches whole words in English
  final chineseWordRegex = RegExp(
    r'[\u4e00-\u9fa5]',
  ); // Matches Chinese characters

  // Calculate English word count
  int englishWordCount = 0;
  englishWordCount = englishWordRegex.allMatches(articleText).length;

  // Calculate Chinese character count
  int chineseWordCount = 0;
  chineseWordCount = chineseWordRegex.allMatches(articleText).length;

  // Determine if it's likely a Chinese article based on character count
  bool isChineseArticle =
      chineseWordCount > englishWordCount && chineseWordCount > 10;

  if (isChineseArticle) {
    return chineseWordCount / chineseReadingSpeed;
  }
  return englishWordCount / englishReadingSpeed;
}

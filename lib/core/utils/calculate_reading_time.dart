String calculateReadingTime(String articleText) {
  if (articleText.isEmpty) {
    return '约 1 分钟';
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

  double readingTimeInMinutes;
  if (isChineseArticle) {
    readingTimeInMinutes = chineseWordCount / chineseReadingSpeed;
  } else {
    readingTimeInMinutes = englishWordCount / englishReadingSpeed;
  }

  // Localized reading-time labels (issue #24: no English fallbacks).
  if (readingTimeInMinutes < 1) {
    return '约 1 分钟';
  } else if (readingTimeInMinutes < 60) {
    return '约 ${readingTimeInMinutes.round()} 分钟';
  } else {
    int hours = readingTimeInMinutes ~/ 60;
    int minutes = (readingTimeInMinutes % 60).round();
    if (minutes == 0) {
      return '约 $hours 小时';
    } else {
      return '约 $hours 小时 $minutes 分钟';
    }
  }
}

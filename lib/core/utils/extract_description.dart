String extractDescription(
  String content, {
  int maxLines = 5,
  int maxChars = 100,
}) {
  List<String> lines = content.split(RegExp(r'\r?\n'));
  List<String> extractedLines = [];
  int charCount = 0;
  int consecutiveBreaks = 0;

  for (int i = 0; i < lines.length; i++) {
    String trimmedLine = lines[i].trim();

    // Skip completely empty lines, but handle the first empty line correctly
    if (trimmedLine.isEmpty) {
      consecutiveBreaks++;
      if (consecutiveBreaks > 1) {
        // If there are multiple consecutive empty lines, add a break
        extractedLines.add(" // ");
      }
      continue;
    } else {
      consecutiveBreaks = 0;
    }

    // If we've exceeded the max line or character count, stop
    if (extractedLines.length >= maxLines || charCount >= maxChars) {
      break;
    }

    // Trim punctuations like Chinese punctuation (。！)
    if (trimmedLine.endsWith('。') ||
        trimmedLine.endsWith('，') ||
        trimmedLine.endsWith('？') ||
        trimmedLine.endsWith('！')) {
      trimmedLine = trimmedLine.substring(0, trimmedLine.length - 1).trim();
    }

    // Add separator if not the first line
    String separator = extractedLines.isNotEmpty ? "/" : "";

    // Add the line and update character count
    extractedLines.add(separator + trimmedLine);
    charCount += trimmedLine.length + separator.length;
  }

  String description = extractedLines.join("");

  // Ensure we don't exceed maxChars
  if (charCount > maxChars && !description.endsWith('...')) {
    int lastSpace = description.lastIndexOf(' ', maxChars);
    if (lastSpace > 0) {
      description = description.substring(0, lastSpace);
    }
    description += "...";
  }

  // Remove any trailing separators or punctuation before "..."
  while (description.endsWith(" /...") ||
      description.endsWith("//...") ||
      description.endsWith("。...")) {
    if (description.endsWith("/...")) {
      description = "${description.substring(0, description.length - 5)}...";
    } else if (description.endsWith("//...")) {
      description = "${description.substring(0, description.length - 6)}...";
    } else if (description.endsWith("。...")) {
      description = "${description.substring(0, description.length - 4)}...";
    }
  }

  // Remove trailing separators if "..." was not added
  if (!description.endsWith("...")) {
    if (description.endsWith("/")) {
      description = description.substring(0, description.length - 3);
    } else if (description.endsWith("//")) {
      description = description.substring(0, description.length - 4);
    }
  }

  return description;
}

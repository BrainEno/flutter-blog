import 'package:belog/core/config/app_durations.dart';
import 'package:belog/core/config/app_limits.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/utils/diagnostics_buffer.dart';
import 'package:belog/core/utils/search_debounce.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:flutter_test/flutter_test.dart';

/// #295 moved every configured wait and page size into `core/config`. These
/// tests pin the values that existed before the move, so the refactor stays
/// behaviour-neutral, and pin the aliases that older call sites still read.
void main() {
  group('AppDurations', () {
    test('keeps the values the call sites used before #295', () {
      expect(AppDurations.requestTimeout, const Duration(seconds: 30));
      expect(AppDurations.mediaUploadTimeout, const Duration(seconds: 90));
      expect(AppDurations.notionImportTimeout, const Duration(minutes: 2));
      expect(AppDurations.healthProbeTimeout, const Duration(seconds: 3));
      expect(AppDurations.healthProbeSuccessTtl, const Duration(seconds: 2));
      expect(
        AppDurations.connectionRetryInitialDelay,
        const Duration(milliseconds: 500),
      );
      expect(AppDurations.sessionRefreshLead, const Duration(seconds: 30));
      expect(AppDurations.bootSessionRestore, const Duration(seconds: 3));
      expect(AppDurations.bootLanguageRestore, const Duration(seconds: 2));
      expect(AppDurations.packageInfoLookup, const Duration(seconds: 2));
      expect(AppDurations.searchDebounce, const Duration(milliseconds: 300));
      expect(AppDurations.snackBarDefault, const Duration(seconds: 4));
      expect(AppDurations.snackBarShort, const Duration(seconds: 2));
      expect(AppDurations.editorAutoSave, const Duration(seconds: 2));
      expect(AppDurations.diagnosticsMaxAge, const Duration(hours: 24));
    });

    test('the older public names are aliases, not copies', () {
      expect(
        identical(
          NowaveApiClient.notionImportTimeout,
          AppDurations.notionImportTimeout,
        ),
        isTrue,
      );
      expect(DiagnosticsBuffer.defaultMaxAge, AppDurations.diagnosticsMaxAge);
      expect(kSearchDebounceDelay, AppDurations.searchDebounce);
      expect(kDefaultSnackBarDuration, AppDurations.snackBarDefault);
      expect(kShortSnackBarDuration, AppDurations.snackBarShort);
    });

    test('a media upload outlasts an ordinary request', () {
      expect(
        AppDurations.mediaUploadTimeout,
        greaterThan(AppDurations.requestTimeout),
      );
      expect(
        AppDurations.notionImportTimeout,
        greaterThan(AppDurations.mediaUploadTimeout),
      );
    });

    test('the publish retry schedule grows and then holds', () {
      expect(
        [for (var i = 0; i < 7; i++) AppDurations.publishRetryAfter(i)],
        const [
          Duration(minutes: 1),
          Duration(minutes: 5),
          Duration(minutes: 15),
          Duration(minutes: 60),
          Duration(hours: 3),
          Duration(hours: 3),
          Duration(hours: 3),
        ],
      );
      expect(AppDurations.publishRetryAfter(-1), const Duration(minutes: 1));
      final schedule = AppDurations.publishRetrySchedule;
      for (var i = 1; i < schedule.length; i++) {
        expect(schedule[i], greaterThan(schedule[i - 1]));
      }
    });
  });

  group('AppLimits', () {
    test('keeps the values the call sites used before #295', () {
      expect(AppLimits.blogCacheMaxRows, 500);
      expect(AppLimits.structuredRecoveryPageSize, 25);
      expect(AppLimits.readingHistoryPageSize, 200);
      expect(AppLimits.notificationPageSize, 50);
      expect(AppLimits.notificationMaxPageSize, 100);
      expect(AppLimits.conversationPageSize, 50);
      expect(AppLimits.messagePageSize, 100);
      expect(AppLimits.structuredComparisonPageSize, 1000);
    });

    test('a default page never exceeds the cap it is clamped to', () {
      expect(
        AppLimits.notificationPageSize,
        lessThanOrEqualTo(AppLimits.notificationMaxPageSize),
      );
    });
  });
}

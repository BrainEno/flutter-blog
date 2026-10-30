import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/tag_l10n.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('safe server error codes survive and localize in both languages', () {
    final failure = mapErrorToFailure(
      const NowaveApiException(
        statusCode: 403,
        code: 'FORBIDDEN',
        message: 'secret account details from backend',
      ),
    );
    expect(failure.code, 'server.FORBIDDEN');
    expect(localizedFailure(zh, failure), '没有权限执行此操作');
    expect(
      localizedFailure(en, failure),
      'You do not have permission to do this',
    );
    expect(localizedFailure(en, failure), isNot(contains('secret')));
    expect(failure.cause, isNotNull);
    final presented = failure.forPresentation();
    expect(presented.cause, isNull);
    expect(presented.code, failure.code);
    expect(localizedFailure(en, presented), localizedFailure(en, failure));
  });

  test('operation-specific wording retains the stable offline code', () {
    final failure = Failure(
      '无法连接到网络，关注未同步',
      kind: FailureKind.network,
      code: 'network.offline',
      l10nKey: 'follow.sync',
    );
    expect(failure.code, 'network.offline');
    expect(localizedFailure(zh, failure), '无法连接到网络，关注未同步');
    expect(
      localizedFailure(en, failure),
      'Offline — the follow was not synced',
    );
  });

  test(
    'unknown messages do not expose backend details or foreign fallbacks',
    () {
      final failure = Failure('secret backend text', kind: FailureKind.server);
      expect(localizedFailure(zh, failure), zh.errorServer);
      expect(localizedFailure(en, failure), en.errorServer);
      expect(localizedFailure(zh, Failure('网络错误')), '网络错误');
      expect(localizedFailure(en, Failure('网络错误')), en.errorUnknown);
    },
  );

  test('locale resolution preserves English regions and uses Simplified Chinese', () {
    const supported = [Locale('zh'), Locale('en')];
    expect(resolveAppLocale([const Locale('en', 'GB')], supported),
        const Locale('en', 'GB'));
    expect(resolveAppLocale([const Locale('zh', 'TW')], supported),
        const Locale('zh', 'CN'));
    expect(resolveAppLocale([const Locale('ja')], supported),
        const Locale('zh', 'CN'));
  });

  test('built-in tags are translated without changing custom tags', () {
    expect(localizedTag(zh, '诗歌'), '诗歌');
    expect(localizedTag(en, '诗歌'), 'Poetry');
    expect(localizedTag(en, '小说'), 'Fiction');
    expect(localizedTag(en, '自定义'), '自定义');
  });

  test('theme primary text pairs meet 4.5:1 contrast', () {
    double contrast(Color a, Color b) {
      final first = a.computeLuminance();
      final second = b.computeLuminance();
      final lighter = first > second ? first : second;
      final darker = first < second ? first : second;
      return (lighter + 0.05) / (darker + 0.05);
    }

    for (final theme in [AppTheme.lightThemeMode, AppTheme.darkThemeMode]) {
      expect(
        contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      contrast(AppPalette.accessibleGreen, Colors.white),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(AppPalette.greenColor, AppPalette.blackColor),
      greaterThanOrEqualTo(4.5),
    );
  });
}

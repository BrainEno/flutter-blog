import 'dart:async';
import 'dart:convert';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/nowave/transport/api_error.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_plan.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_source.dart';
import 'package:belog/features/blog/presentation/editor/notion_import_file_picker.dart';
import 'package:belog/features/blog/presentation/editor/notion_import_sheet.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

class _Identity implements NowaveSessionIdentity {
  String? user = 'user';
  int generation = 1;
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  String? get activeUserId => user;
  @override
  String? get accessToken => user == null ? null : 'token';
  @override
  int get sessionGeneration => generation;
  @override
  Stream<void> get identityChanges => changes.stream;

  Future<void> close() => changes.close();
}

class _Repo implements NotionImportRepository {
  final calls = <bool>[];
  final bundles = <NotionBundle>[];
  Completer<Either<Failure, NotionImportReport>>? pending;
  bool failApply = false;
  Failure? failure;
  List<NotionImportIssue> issues = const [];
  NotionImportAction action = NotionImportAction.create;
  @override
  Future<Either<Failure, NotionImportReport>> submit({
    required NotionBundle bundle,
    required bool apply,
    required NowaveSessionFence sessionFence,
    NotionImportPlan? plan,
  }) async {
    calls.add(apply);
    bundles.add(bundle);
    if (pending != null) return pending!.future;
    if (failApply && apply) return left(Failure.timeout());
    if (failure != null) return left(failure!);
    return right(
      NotionImportReport(
        applied: apply,
        plan: apply ? null : _planFor(bundle, sessionFence),
        pages: [
          NotionImportPage(
            title: 'My page',
            locale: 'en',
            action: action,
            detail: 'detail',
            issues: issues,
          ),
        ],
      ),
    );
  }
}

NotionImportPlan _planFor(NotionBundle bundle, NowaveSessionFence fence) =>
    NotionImportPlan.fromPreview(
      bundle: bundle,
      fence: fence,
      token: 'payload.${'s' * 43}',
      expiresAt: DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 10))
          .toIso8601String()
          .replaceFirst(RegExp(r'\.\d{6}Z$'), '.000Z'),
    );

const _input =
    '{"version":1,"database":{"id":"db"},"pages":[{"id":"p","properties":{},"blocks":[]}]}';
const _fence = NowaveSessionFence(userId: 'user', generation: 1);

void main() {
  late _Identity identity;
  late AppUserCubit userCubit;
  late _Repo repo;
  final l10n = lookupAppLocalizations(const Locale('en'));
  setUp(() {
    identity = _Identity();
    userCubit = AppUserCubit()
      ..updateUser(
        User(
          id: 'user',
          email: 'a@example.invalid',
          name: 'A',
          updatedAt: DateTime.utc(2024),
        ),
      );
    repo = _Repo();
  });
  tearDown(() async {
    await userCubit.close();
    await identity.close();
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    NotionImportFilePicker? pickFiles,
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NotionImportSheet(
            repository: repo,
            identity: identity,
            userCubit: userCubit,
            fence: _fence,
            pickFiles: pickFiles,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> selectAll(WidgetTester tester) async {
    await tap(tester, l10n.notionImportReadBundle);
    await tap(tester, l10n.notionImportSelectAll);
  }

  testWidgets(
    'previews first, requires explicit confirmation, and applies the same snapshot',
    (tester) async {
      await pumpSheet(tester);
      await tester.enterText(find.byType(TextField), _input);
      await selectAll(tester);
      await tap(tester, l10n.notionImportPreviewSelected);
      expect(repo.calls, [false]);
      expect(find.text(l10n.notionImportPlan), findsOneWidget);
      await tap(tester, l10n.notionImportReviewConfirm);
      expect(repo.calls, [false]);
      await tap(tester, l10n.notionImportConfirm);
      expect(repo.calls, [false, true]);
      expect(identical(repo.bundles.first, repo.bundles.last), isTrue);
      expect(find.text(l10n.notionImportResult), findsOneWidget);
      expect(find.text(l10n.notionImportConfirm), findsNothing);
    },
  );

  testWidgets(
    'version risk stays visible through confirmation in both languages',
    (tester) async {
      for (final locale in [const Locale('en'), const Locale('zh')]) {
        await tester.pumpWidget(const SizedBox.shrink());
        repo.calls.clear();
        repo.action = locale.languageCode == 'en'
            ? NotionImportAction.create
            : NotionImportAction.update;
        final labels = lookupAppLocalizations(locale);
        await pumpSheet(tester, locale: locale);
        await tester.enterText(find.byType(TextField), _input);
        await tap(tester, labels.notionImportReadBundle);
        await tap(tester, labels.notionImportSelectAll);
        await tap(tester, labels.notionImportPreviewSelected);
        expect(find.text(labels.notionImportVersionWarning), findsOneWidget);
        expect(repo.calls, [false]);
        await tap(tester, labels.notionImportReviewConfirm);
        expect(find.text(labels.notionImportVersionWarning), findsOneWidget);
        expect(find.text(labels.notionImportConfirm), findsOneWidget);
        expect(repo.calls, [false]);
        await tap(tester, labels.actionCancel);
        expect(find.text(labels.notionImportVersionWarning), findsOneWidget);
        expect(find.text(labels.notionImportConfirm), findsNothing);
      }
    },
  );

  testWidgets(
    'refreshing a preview discards the old confirmation before the response',
    (tester) async {
      await pumpSheet(tester);
      await tester.enterText(find.byType(TextField), _input);
      await selectAll(tester);
      await tap(tester, l10n.notionImportPreviewSelected);
      await tap(tester, l10n.notionImportReviewConfirm);
      repo.pending = Completer<Either<Failure, NotionImportReport>>();
      await tester.ensureVisible(find.text(l10n.notionImportRefreshPreview));
      await tester.tap(find.text(l10n.notionImportRefreshPreview));
      await tester.pump();
      expect(repo.calls, [false, false]);
      expect(find.text(l10n.notionImportPlan), findsNothing);
      expect(find.text(l10n.notionImportConfirm), findsNothing);
      repo.pending!.complete(
        right(
          NotionImportReport(
            applied: false,
            plan: _planFor(repo.bundles.last, _fence),
            pages: const [
              NotionImportPage(
                title: 'Changed plan',
                locale: 'en',
                action: NotionImportAction.update,
                detail: '',
                issues: [],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.notionImportVersionWarning), findsOneWidget);
      expect(find.text(l10n.notionImportConfirm), findsNothing);
      expect(find.text(l10n.notionImportReviewConfirm), findsOneWidget);
      expect(repo.calls, [false, false]);
      await tap(tester, l10n.notionImportReviewConfirm);
      expect(find.text(l10n.notionImportConfirm), findsOneWidget);
    },
  );

  testWidgets('failed refresh never restores the old plan', (tester) async {
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), _input);
    await selectAll(tester);
    await tap(tester, l10n.notionImportPreviewSelected);
    await tap(tester, l10n.notionImportReviewConfirm);
    repo.pending = Completer<Either<Failure, NotionImportReport>>();
    await tester.ensureVisible(find.text(l10n.notionImportRefreshPreview));
    await tester.tap(find.text(l10n.notionImportRefreshPreview));
    await tester.pump();
    repo.pending!.complete(left(Failure.timeout()));
    await tester.pumpAndSettle();
    expect(find.text(l10n.notionImportPlan), findsNothing);
    expect(find.text(l10n.notionImportReviewConfirm), findsNothing);
    expect(find.text(l10n.notionImportConfirm), findsNothing);
    expect(repo.calls, [false, false]);
  });

  testWidgets('non-writable preview offers no confirmation', (tester) async {
    repo.action = NotionImportAction.skip;
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), _input);
    await selectAll(tester);
    await tap(tester, l10n.notionImportPreviewSelected);
    expect(find.text(l10n.notionImportPlan), findsOneWidget);
    expect(find.text(l10n.notionImportReviewConfirm), findsNothing);
    expect(find.text(l10n.notionImportConfirm), findsNothing);
    expect(repo.calls, [false]);
  });

  testWidgets('editing the bundle invalidates its preview and confirmation', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), _input);
    await selectAll(tester);
    await tap(tester, l10n.notionImportPreviewSelected);
    await tap(tester, l10n.notionImportReviewConfirm);
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.pumpAndSettle();
    expect(find.text(l10n.notionImportConfirm), findsNothing);
    await tap(tester, l10n.notionImportReadBundle);
    expect(find.text(l10n.notionImportInvalid), findsOneWidget);
    expect(repo.calls, [false]);
  });

  testWidgets('an uncertain apply cannot be repeated without a new preview', (
    tester,
  ) async {
    repo.failApply = true;
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), _input);
    await selectAll(tester);
    await tap(tester, l10n.notionImportPreviewSelected);
    await tap(tester, l10n.notionImportReviewConfirm);
    await tap(tester, l10n.notionImportConfirm);
    expect(find.text(l10n.notionImportOutcomeUnknown), findsOneWidget);
    expect(find.text(l10n.notionImportConfirm), findsNothing);
    expect(repo.calls, [false, true]);
  });

  testWidgets(
    'only selected source pages are previewed and changing selection invalidates the plan',
    (tester) async {
      const input =
          '{"version":1,"database":{"id":"db"},"pages":['
          '{"id":"a","properties":{"Page":{"type":"title","title":[{"plain_text":"First"}]},"English":{"relation":[{"id":"b"}]}},"blocks":[]},'
          '{"id":"b","properties":{"Page":{"type":"title","title":[{"plain_text":"Second"}]}},"blocks":[]},'
          '{"id":"c","properties":{},"blocks":[]}]}';
      await pumpSheet(tester);
      await tester.enterText(find.byType(TextField), input);
      await tap(tester, l10n.notionImportReadBundle);
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(find.text(l10n.notionImportUntitledPage(3)), findsOneWidget);
      expect(find.text(l10n.notionImportSelectionCount(0, 3)), findsOneWidget);
      await tap(tester, 'First');
      await tap(tester, l10n.notionImportUntitledPage(3));
      await tap(tester, l10n.notionImportPreviewSelected);
      final pages = repo.bundles.single.json['pages'] as List;
      expect(pages.map((page) => page['id']).toList(), ['a', 'c']);
      expect(pages.first['properties']['English']['relation'][0]['id'], 'b');
      await tap(tester, l10n.notionImportReviewConfirm);
      await tap(tester, 'Second');
      expect(find.text(l10n.notionImportConfirm), findsNothing);
      expect(find.text(l10n.notionImportPlan), findsNothing);
      await tap(tester, l10n.notionImportPreviewSelected);
      expect((repo.bundles.last.json['pages'] as List).length, 3);
      expect(repo.calls, [false, false]);
    },
  );

  testWidgets('empty selection and empty bundles do not issue a request', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tester.enterText(
      find.byType(TextField),
      '{"version":1,"pages":['
      '{"id":"a","properties":{},"blocks":[]},'
      '{"id":"b","properties":{},"blocks":[]}]}',
    );
    await tap(tester, l10n.notionImportReadBundle);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.notionImportPreviewSelected),
    );
    expect(button.onPressed, isNull);
    await tester.enterText(find.byType(TextField), '{"version":1,"pages":[]}');
    await tap(tester, l10n.notionImportReadBundle);
    expect(find.text(l10n.notionImportNoPages), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('session replacement hides input and drops a late preview', (
    tester,
  ) async {
    repo.pending = Completer<Either<Failure, NotionImportReport>>();
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), _input);
    await selectAll(tester);
    await tester.ensureVisible(find.text(l10n.notionImportPreviewSelected));
    await tester.tap(find.text(l10n.notionImportPreviewSelected));
    await tester.pump();
    identity.generation++;
    identity.changes.add(null);
    await tester.pump();
    repo.pending!.complete(
      right(const NotionImportReport(applied: false, pages: [])),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text(l10n.editorSessionChanged), findsOneWidget);
    expect(find.text(l10n.notionImportPlan), findsNothing);
    expect(repo.calls, [false]);
  });
  testWidgets(
    'expiry removes an open confirmation and requires a new preview',
    (tester) async {
      await pumpSheet(tester);
      await tester.enterText(find.byType(TextField), _input);
      await selectAll(tester);
      await tap(tester, l10n.notionImportPreviewSelected);
      await tap(tester, l10n.notionImportReviewConfirm);
      await tester.pump(const Duration(minutes: 11));
      expect(find.text(l10n.notionImportPlanInvalid), findsOneWidget);
      expect(find.text(l10n.notionImportConfirm), findsNothing);
      expect(repo.calls, [false]);
      await tap(tester, l10n.notionImportPreviewSelected);
      expect(repo.calls, [false, false]);
      expect(find.text(l10n.notionImportReviewConfirm), findsOneWidget);
    },
  );

  testWidgets('legacy preview cannot expose a confirmation', (tester) async {
    repo.pending = Completer<Either<Failure, NotionImportReport>>();
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), _input);
    await selectAll(tester);
    await tester.ensureVisible(find.text(l10n.notionImportPreviewSelected));
    await tester.tap(find.text(l10n.notionImportPreviewSelected));
    await tester.pump();
    repo.pending!.complete(
      right(const NotionImportReport(applied: false, pages: [])),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.notionImportReviewConfirm), findsNothing);
    expect(find.text(l10n.notionImportConfirm), findsNothing);
  });

  testWidgets(
    'a chosen Notion export is converted, reported and previewed as one bundle',
    (tester) async {
      const id = '0123456789abcdef0123456789abcdef';
      await pumpSheet(
        tester,
        pickFiles: () async => [
          NotionImportFile(
            name: 'Wall $id.md',
            bytes: utf8.encode('# Wall\n\nRank: 1\nMood: calm\n\nFirst line.'),
          ),
          NotionImportFile(
            name: 'Notes.md',
            bytes: utf8.encode('# Notes\n\nBody'),
          ),
        ],
      );
      await tester.enterText(find.byType(TextField), 'left over');
      await tester.tap(find.byKey(const ValueKey('notion-import-choose')));
      await tester.pumpAndSettle();

      // One source at a time: the pasted text gives way to the files.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(
        find.text(l10n.notionImportFilesRead('Wall $id.md, Notes.md', 2)),
        findsOneWidget,
      );
      expect(find.text('Wall'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('notion-import-warnings')),
        findsOneWidget,
      );
      expect(find.text(l10n.notionImportWarningsTitle(2)), findsOneWidget);
      expect(
        find.text(l10n.notionImportWarnPropertyIgnored('Mood')),
        findsOneWidget,
      );
      expect(find.text(l10n.notionImportWarnFileNameIdentity), findsOneWidget);
      // Several pages: the author chooses.
      expect(find.text(l10n.notionImportSelectionCount(0, 2)), findsOneWidget);

      await tap(tester, l10n.notionImportSelectAll);
      await tap(tester, l10n.notionImportPreviewSelected);
      final pages = repo.bundles.single.json['pages'] as List;
      expect(pages.map((page) => page['id']).toList(), [
        '01234567-89ab-cdef-0123-456789abcdef',
        'markdown-file:Notes.md',
      ]);
      expect(repo.calls, [false]);
    },
  );

  testWidgets('pasted Markdown is one page, selected and ready to preview', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), '# Aircraft\n\nIt flies.');
    await tap(tester, l10n.notionImportReadBundle);
    expect(find.text('Aircraft'), findsOneWidget);
    expect(find.text(l10n.notionImportSelectionCount(1, 1)), findsOneWidget);
    expect(find.text(l10n.notionImportWarnPastedIdentity), findsOneWidget);
    await tap(tester, l10n.notionImportPreviewSelected);
    final page = (repo.bundles.single.json['pages'] as List).single as Map;
    expect(page['id'], 'markdown-file:Aircraft.md');
    expect(repo.calls, [false]);
  });

  testWidgets('files that cannot be read say which and why', (tester) async {
    var answer = <NotionImportFile>[
      NotionImportFile(name: 'notes.txt', bytes: utf8.encode('x')),
    ];
    NotionImportSourceException? refusal;
    var crash = false;
    await pumpSheet(
      tester,
      pickFiles: () async {
        if (refusal != null) throw refusal;
        if (crash) throw StateError('picker');
        return answer;
      },
    );
    Future<void> choose() async {
      await tester.tap(find.byKey(const ValueKey('notion-import-choose')));
      await tester.pumpAndSettle();
    }

    await choose();
    expect(
      find.text(l10n.notionImportSourceUnsupported('notes.txt')),
      findsOneWidget,
    );

    answer = [
      NotionImportFile(name: 'export.zip', bytes: utf8.encode('not a zip')),
    ];
    await choose();
    expect(
      find.text(l10n.notionImportSourceInvalidZip('export.zip')),
      findsOneWidget,
    );

    refusal = const NotionImportSourceException(
      NotionImportSourceError.tooLarge,
    );
    await choose();
    expect(find.text(l10n.notionImportSourceTooLarge), findsOneWidget);

    refusal = null;
    crash = true;
    await choose();
    expect(find.text(l10n.notionImportSourceUnreadable), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('cancelling the picker keeps what was there', (tester) async {
    await pumpSheet(tester, pickFiles: () async => null);
    await tester.enterText(find.byType(TextField), _input);
    await tap(tester, l10n.notionImportReadBundle);
    await tester.tap(find.byKey(const ValueKey('notion-import-choose')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.notionImportSelectionCount(1, 1)), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      _input,
    );
  });

  testWidgets('report issues are put in words, grouped, without signed URLs', (
    tester,
  ) async {
    repo.issues = const [
      NotionImportIssue(code: 'slug-derived', detail: ''),
      NotionImportIssue(code: 'unsupported-block', detail: 'synced_block'),
      NotionImportIssue(code: 'unsupported-block', detail: 'column_list'),
      NotionImportIssue(
        code: 'expiring-image-url',
        detail:
            'https://prod-files-secure.s3.amazonaws.com/x?X-Amz-Signature=s',
      ),
      NotionImportIssue(code: 'brand-new-code', detail: ''),
    ];
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), _input);
    await tap(tester, l10n.notionImportReadBundle);
    await tap(tester, l10n.notionImportPreviewSelected);
    expect(find.text(l10n.notionImportIssueSlugDerived), findsOneWidget);
    expect(
      find.text(
        '${l10n.notionImportIssueUnsupportedBlock} '
        '(${l10n.notionImportWarningCount(2)})',
      ),
      findsOneWidget,
    );
    expect(find.text('synced_block, column_list'), findsOneWidget);
    expect(find.text(l10n.notionImportIssueExpiringImage), findsOneWidget);
    expect(find.textContaining('X-Amz'), findsNothing);
    expect(
      find.text(l10n.notionImportIssueOther('brand-new-code')),
      findsOneWidget,
    );
    expect(find.textContaining('slug-derived'), findsNothing);
  });

  test('every documented issue code has its own words', () {
    const codes = [
      'slug-derived',
      'empty-block-dropped',
      'expiring-image-url',
      'featured-image-not-carried',
      'hierarchy-not-carried',
      'work-type-fallback',
      'link-block-flattened',
      'equation-flattened',
      'callout-flattened',
      'toggle-flattened',
      'checkbox-state-dropped',
      'table-block-dropped',
      'unsupported-block',
      'invalid-block-dropped',
      'empty-title',
      'empty-body',
      'image-copy-failed',
      'translation-locale-not-carried',
      'work-type-not-carried',
    ];
    for (final labels in [l10n, lookupAppLocalizations(const Locale('zh'))]) {
      final messages = {
        for (final code in codes) notionIssueMessage(labels, code),
      };
      expect(messages, hasLength(codes.length));
      for (final code in codes) {
        expect(
          notionIssueMessage(labels, code),
          isNot(labels.notionImportIssueOther(code)),
        );
      }
    }
  });

  testWidgets('the rate limit is explained, with the wait when it is known', (
    tester,
  ) async {
    repo.failure = const Failure(
      'limited',
      kind: FailureKind.server,
      code: 'server.RATE_LIMITED',
      cause: NowaveApiException(
        statusCode: 429,
        code: 'RATE_LIMITED',
        message: 'slow down',
        retryAfterSeconds: 150,
      ),
    );
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), _input);
    await tap(tester, l10n.notionImportReadBundle);
    await tap(tester, l10n.notionImportPreviewSelected);
    expect(find.text(l10n.notionImportRateLimitedRetry(3)), findsOneWidget);

    repo.failure = const Failure(
      'limited',
      kind: FailureKind.server,
      code: 'server.RATE_LIMITED',
    );
    await tap(tester, l10n.notionImportPreviewSelected);
    expect(find.text(l10n.notionImportRateLimited), findsOneWidget);
    expect(repo.calls, [false, false]);
  });
}

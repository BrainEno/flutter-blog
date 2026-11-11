import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/notion_export/notion_export.dart';
import 'package:belog/features/blog/presentation/editor/notion_export_sheet.dart';
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
}

class _Repo implements NotionExportRepository {
  int calls = 0;
  Completer<Either<Failure, NotionExportResult>>? pending;
  NotionExportResult result = const NotionExportResult(
    missing: false,
    bundleJson: 'private bundle',
    issues: ['work-type-not-carried'],
    editions: [
      NotionExportEdition(
        locale: 'en',
        fromNotion: true,
        issues: ['unsupported'],
      ),
    ],
  );
  @override
  Future<Either<Failure, NotionExportResult>> export({
    required String slug,
    required NowaveSessionFence sessionFence,
  }) async {
    calls++;
    if (pending != null) return pending!.future;
    return right(result);
  }
}

const _fence = NowaveSessionFence(userId: 'user', generation: 1);
void main() {
  late _Identity identity;
  late AppUserCubit userCubit;
  late _Repo repo;
  late List<String> copies;
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
    copies = [];
  });
  tearDown(() async {
    await userCubit.close();
    await identity.changes.close();
  });
  Future<void> pumpSheet(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
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
          body: NotionExportSheet(
            repository: repo,
            identity: identity,
            userCubit: userCubit,
            fence: _fence,
            slug: 'hello',
            copyText: (text) async {
              copies.add(text);
            },
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

  testWidgets(
    'reads on demand, displays report, copies only on explicit action',
    (tester) async {
      await pumpSheet(tester);
      expect(repo.calls, 0);
      expect(copies, isEmpty);
      await tap(tester, l10n.notionExportLoad);
      expect(find.text('work-type-not-carried'), findsOneWidget);
      expect(find.text('unsupported'), findsOneWidget);
      expect(
        find.text(
          l10n.notionExportEdition('en', l10n.notionExportNotionOrigin),
        ),
        findsOneWidget,
      );
      expect(copies, isEmpty);
      await tap(tester, l10n.notionExportCopy);
      expect(copies, ['private bundle']);
      expect(find.text(l10n.notionExportCopied), findsOneWidget);
    },
  );
  testWidgets(
    'explains known losses and handles unknown codes safely in both languages',
    (tester) async {
      repo.result = const NotionExportResult(
        missing: false,
        bundleJson: 'private bundle',
        issues: [
          'translation-locale-not-carried',
          'work-type-not-carried',
          'future-issue',
          'https://example.invalid/private?token=secret',
        ],
        editions: [
          NotionExportEdition(
            locale: 'en',
            fromNotion: false,
            issues: ['unsupported-block'],
          ),
        ],
      );
      for (final locale in [const Locale('en'), const Locale('zh')]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpSheet(tester, locale: locale);
        final labels = lookupAppLocalizations(locale);
        await tap(tester, labels.notionExportLoad);
        expect(find.text(labels.notionExportIssueTranslation), findsOneWidget);
        expect(find.text(labels.notionExportIssueWorkType), findsOneWidget);
        expect(find.text(labels.notionExportIssueBlock), findsOneWidget);
        expect(find.text(labels.notionExportIssueUnknown), findsNWidgets(2));
        expect(find.text('future-issue'), findsOneWidget);
        expect(
          find.text(labels.notionExportIssueUnrecognizedCode),
          findsOneWidget,
        );
        expect(
          find.text('https://example.invalid/private?token=secret'),
          findsNothing,
        );
        expect(copies, isEmpty);
      }
    },
  );

  testWidgets('no reported issues is not presented as a lossless guarantee', (
    tester,
  ) async {
    repo.result = const NotionExportResult(
      missing: false,
      bundleJson: 'private bundle',
      issues: [],
      editions: [
        NotionExportEdition(locale: 'en', fromNotion: true, issues: []),
      ],
    );
    await pumpSheet(tester);
    await tap(tester, l10n.notionExportLoad);
    expect(find.text(l10n.notionExportNoIssues), findsOneWidget);
    expect(copies, isEmpty);
  });

  testWidgets('missing work offers no copy', (tester) async {
    repo.result = const NotionExportResult(
      missing: true,
      bundleJson: '',
      issues: [],
      editions: [],
    );
    await pumpSheet(tester);
    await tap(tester, l10n.notionExportLoad);
    expect(find.text(l10n.notionExportMissing), findsOneWidget);
    expect(find.text(l10n.notionExportCopy), findsNothing);
    expect(copies, isEmpty);
  });
  testWidgets('session switch removes report and prevents copying', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tap(tester, l10n.notionExportLoad);
    identity.generation++;
    identity.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text(l10n.notionExportCopy), findsNothing);
    expect(find.text('work-type-not-carried'), findsNothing);
    expect(copies, isEmpty);
  });
  testWidgets('late response after session switch is discarded', (
    tester,
  ) async {
    repo.pending = Completer<Either<Failure, NotionExportResult>>();
    await pumpSheet(tester);
    await tap(tester, l10n.notionExportLoad);
    identity.user = 'other';
    identity.changes.add(null);
    repo.pending!.complete(right(repo.result));
    await tester.pumpAndSettle();
    expect(find.text(l10n.notionExportCopy), findsNothing);
    expect(find.text('unsupported'), findsNothing);
    expect(copies, isEmpty);
  });
}

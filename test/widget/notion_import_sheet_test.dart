import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
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
}

class _Repo implements NotionImportRepository {
  final calls = <bool>[];
  final bundles = <NotionBundle>[];
  Completer<Either<Failure, NotionImportReport>>? pending;
  bool failApply = false;
  @override
  Future<Either<Failure, NotionImportReport>> submit({
    required NotionBundle bundle,
    required bool apply,
    required NowaveSessionFence sessionFence,
  }) async {
    calls.add(apply);
    bundles.add(bundle);
    if (pending != null) return pending!.future;
    if (failApply && apply) return left(Failure.timeout());
    return right(
      NotionImportReport(
        applied: apply,
        pages: const [
          NotionImportPage(
            title: 'My page',
            locale: 'en',
            action: NotionImportAction.create,
            detail: 'detail',
            issues: [],
          ),
        ],
      ),
    );
  }
}

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
    await identity.changes.close();
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NotionImportSheet(
            repository: repo,
            identity: identity,
            userCubit: userCubit,
            fence: _fence,
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
    'previews first, requires explicit confirmation, and applies the same snapshot',
    (tester) async {
      await pumpSheet(tester);
      await tester.enterText(find.byType(TextField), _input);
      await tap(tester, l10n.notionImportPreview);
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

  testWidgets('editing the bundle invalidates its preview and confirmation', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), _input);
    await tap(tester, l10n.notionImportPreview);
    await tap(tester, l10n.notionImportReviewConfirm);
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.pumpAndSettle();
    expect(find.text(l10n.notionImportConfirm), findsNothing);
    await tap(tester, l10n.notionImportPreview);
    expect(find.text(l10n.notionImportInvalid), findsOneWidget);
    expect(repo.calls, [false]);
  });

  testWidgets('an uncertain apply cannot be repeated without a new preview', (
    tester,
  ) async {
    repo.failApply = true;
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), _input);
    await tap(tester, l10n.notionImportPreview);
    await tap(tester, l10n.notionImportReviewConfirm);
    await tap(tester, l10n.notionImportConfirm);
    expect(find.text(l10n.notionImportOutcomeUnknown), findsOneWidget);
    expect(find.text(l10n.notionImportConfirm), findsNothing);
    expect(repo.calls, [false, true]);
  });

  testWidgets('session replacement hides input and drops a late preview', (
    tester,
  ) async {
    repo.pending = Completer<Either<Failure, NotionImportReport>>();
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), _input);
    await tester.tap(find.text(l10n.notionImportPreview));
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
}

import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/notion_export/notion_export.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/presentation/editor/editor_notion_coordinator.dart';
import 'package:belog/features/blog/presentation/editor/notion_export_sheet.dart';
import 'package:belog/features/blog/presentation/editor/notion_import_sheet.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _ImportRepository extends Mock implements NotionImportRepository {}

class _ExportRepository extends Mock implements NotionExportRepository {}

class _Identity implements NowaveSessionIdentity {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  String? activeUserId = 'author';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 3;
  @override
  Stream<void> get identityChanges => changes.stream;

  Future<void> close() => changes.close();
}

void main() {
  late _Identity identity;
  late AppUserCubit cubit;
  late EditorNotionCoordinator coordinator;
  late _ImportRepository importer;
  late _ExportRepository exporter;
  late bool current;
  late BuildContext context;

  setUp(() {
    identity = _Identity();
    cubit = AppUserCubit()
      ..updateUser(
        User(
          id: 'author',
          email: 'a@example.invalid',
          name: 'A',
          updatedAt: DateTime.utc(2026),
        ),
      );
    importer = _ImportRepository();
    exporter = _ExportRepository();
    current = true;
    coordinator = EditorNotionCoordinator(
      identity: identity,
      userCubit: cubit,
      userId: 'author',
      generation: 3,
      isCurrent: () => current,
      importRepository: () => importer,
      exportRepository: () => exporter,
    );
  });

  tearDown(() async {
    coordinator.dismiss();
    await cubit.close();
    await identity.close();
  });

  Future<void> openHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const Text('Editor host');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('single fenced import route is dismissed without removing host', (
    tester,
  ) async {
    await openHost(tester);
    unawaited(coordinator.openImport(context));
    await tester.pumpAndSettle();
    final sheet = tester.widget<NotionImportSheet>(
      find.byType(NotionImportSheet),
    );
    expect(sheet.fence.userId, 'author');
    expect(sheet.fence.generation, 3);
    expect(sheet.identity, same(identity));
    expect(coordinator.applyStarted, isFalse);
    await coordinator.openImport(context);
    await tester.pumpAndSettle();
    expect(find.byType(NotionImportSheet), findsOneWidget);
    current = false;
    coordinator.dismiss();
    await tester.pumpAndSettle();
    expect(find.byType(NotionImportSheet), findsNothing);
    expect(find.text('Editor host'), findsOneWidget);
    await coordinator.openImport(context);
    await tester.pumpAndSettle();
    expect(find.byType(NotionImportSheet), findsNothing);
  });

  testWidgets('export opens only with a target and retains captured fence', (
    tester,
  ) async {
    await openHost(tester);
    await coordinator.openExport(context, null);
    await coordinator.openExport(context, '');
    expect(find.byType(NotionExportSheet), findsNothing);
    unawaited(coordinator.openExport(context, 'article'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<NotionExportSheet>(
      find.byType(NotionExportSheet),
    );
    expect(sheet.slug, 'article');
    expect(sheet.fence.userId, 'author');
    expect(sheet.fence.generation, 3);
    coordinator.dismiss();
    await tester.pumpAndSettle();
    expect(find.byType(NotionExportSheet), findsNothing);
    expect(find.text('Editor host'), findsOneWidget);
  });
}

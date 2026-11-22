import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/article_editions.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/notion_export/notion_export.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/presentation/editor/editor_notion_coordinator.dart';
import 'package:belog/features/blog/presentation/editor/notion_export_sheet.dart';
import 'package:belog/features/blog/presentation/editor/notion_import_sheet.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

class _ImportRepository extends Mock implements NotionImportRepository {}

class _ExportRepository extends Mock implements NotionExportRepository {}

class _BlogRepository extends Mock implements BlogRepository {}

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

  testWidgets('opening an imported article closes the sheet first', (
    tester,
  ) async {
    final opened = <String>[];
    Future<Map<String, bool>?> works() async => {'w': true};
    coordinator = EditorNotionCoordinator(
      identity: identity,
      userCubit: cubit,
      userId: 'author',
      generation: 3,
      isCurrent: () => current,
      importRepository: () => importer,
      exportRepository: () => exporter,
      publishedWorks: works,
      openArticle: (_, slug) => opened.add(slug),
    );
    await openHost(tester);
    final done = coordinator.openImport(context);
    await tester.pumpAndSettle();
    final sheet = tester.widget<NotionImportSheet>(
      find.byType(NotionImportSheet),
    );
    expect(sheet.publishedWorks, isNotNull);
    sheet.onOpenArticle!('qiangbi');
    await tester.pumpAndSettle();
    await done;
    expect(find.byType(NotionImportSheet), findsNothing);
    expect(find.text('Editor host'), findsOneWidget);
    expect(opened, ['qiangbi']);

    // Not under a replaced session.
    unawaited(coordinator.openImport(context));
    await tester.pumpAndSettle();
    current = false;
    tester
        .widget<NotionImportSheet>(find.byType(NotionImportSheet))
        .onOpenArticle!('other');
    await tester.pumpAndSettle();
    expect(opened, ['qiangbi']);
  });

  testWidgets('published works come from the author\'s own list', (
    tester,
  ) async {
    final blogs = _BlogRepository();
    BlogModel blog(String work, {required bool draft}) => BlogModel(
      id: 'slug-$work',
      title: work,
      content: '',
      posterId: 'author',
      imageUrl: '',
      tags: const [],
      updatedAt: DateTime.utc(2026),
      isDraft: draft,
      articleId: work,
    );
    when(() => blogs.getMyArticleEditions(userId: 'author')).thenAnswer(
      (_) async => right(
        ArticleEditions(
          blogs: [
            blog('w1', draft: false),
            blog('w2', draft: true),
            blog('', draft: false),
          ],
          locales: const ['zh-CN', 'en'],
        ),
      ),
    );
    GetIt.instance.registerSingleton<BlogRepository>(blogs);
    addTearDown(() => GetIt.instance.unregister<BlogRepository>());
    await openHost(tester);
    unawaited(coordinator.openImport(context));
    await tester.pumpAndSettle();
    final sheet = tester.widget<NotionImportSheet>(
      find.byType(NotionImportSheet),
    );
    expect(await sheet.publishedWorks!(), {'w1': true, 'w2': false});

    when(
      () => blogs.getMyArticleEditions(userId: 'author'),
    ).thenAnswer((_) async => left(Failure.networkOffline()));
    expect(await sheet.publishedWorks!(), isNull);
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

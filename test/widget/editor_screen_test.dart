import 'dart:async';

import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/editor/auto_save_banner.dart';
import 'package:belog/features/blog/presentation/editor/editor_app_bar.dart';
import 'package:belog/features/blog/presentation/editor/editor_form.dart';
import 'package:belog/features/blog/presentation/editor/editor_screen.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _UploadBloc extends Mock implements BlogUploadBloc {}

class _UploadEvent extends Fake implements BlogUploadEvent {}

void main() {
  setUpAll(() => registerFallbackValue(_UploadEvent()));
  late _UploadBloc bloc;
  late StreamController<BlogUploadState> changes;
  late TextEditingController title;
  late TextEditingController body;
  late GlobalKey<FormState> formKey;
  late List<BlogUploadState> received;
  late int publishes;
  late int saves;
  late int imports;
  late int exports;
  late int cancels;

  setUp(() {
    bloc = _UploadBloc();
    changes = StreamController<BlogUploadState>.broadcast(sync: true);
    title = TextEditingController(text: 'private title');
    body = TextEditingController(text: 'private body');
    formKey = GlobalKey<FormState>();
    received = [];
    publishes = 0;
    saves = 0;
    imports = 0;
    exports = 0;
    cancels = 0;
    when(() => bloc.state).thenReturn(BlogUploadInitial());
    when(() => bloc.stream).thenAnswer((_) => changes.stream);
  });

  tearDown(() async {
    await changes.close();
    title.dispose();
    body.dispose();
  });

  EditorForm form() => EditorForm(
    formKey: formKey,
    titleController: title,
    contentController: body,
    selectedTags: const [],
    onTagsChanged: (_) {},
    image: null,
    isNewImageSelected: false,
    blog: null,
    hasUnclaimedDrafts: false,
    autoSaveStatus: AutoSaveStatus.idle,
    onPickCover: () {},
    onChooseCoverFromLibrary: () {},
    categories: const [],
    selectedCategoryIds: const [],
    categoriesLoading: false,
    categoriesFailed: false,
    onCategoriesChanged: (_) {},
    onRetryCategories: () {},
  );

  Future<void> render(
    WidgetTester tester, {
    bool current = true,
    bool notionApplied = false,
    bool editing = false,
    bool canExport = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<BlogUploadBloc>.value(
          value: bloc,
          child: EditorScreen(
            isCurrentEditor: current,
            notionApplyStarted: notionApplied,
            isEditing: editing,
            form: current ? form() : null,
            onPublish: () => publishes++,
            onSaveDraft: () => saves++,
            onCancel: () => cancels++,
            onImportNotion: () => imports++,
            onExportNotion: canExport ? () => exports++ : null,
            onUploadState: (_, state) => received.add(state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('screen delegates actions and does not submit anything itself', (
    tester,
  ) async {
    await render(tester, editing: true, canExport: true);
    expect(find.byType(EditorForm), findsOneWidget);
    expect(find.text('private title'), findsOneWidget);
    final appBar = tester.widget<EditorAppBar>(find.byType(EditorAppBar));
    appBar.onPublish();
    appBar.onSaveDraft();
    appBar.onCancel();
    appBar.onImportNotion();
    appBar.onExportNotion!();
    expect([publishes, saves, cancels, imports, exports], [1, 1, 1, 1, 1]);
    verifyNever(() => bloc.add(any()));
  });

  testWidgets('invalidated view does not build form or upload listener', (
    tester,
  ) async {
    await render(tester, current: false);
    expect(find.textContaining('session changed'), findsOneWidget);
    expect(find.byType(EditorForm), findsNothing);
    expect(find.byType(EditorAppBar), findsNothing);
    changes.add(BlogUploadSuccess());
    await tester.pump();
    expect(received, isEmpty);
    expect(find.text('private title'), findsNothing);
  });

  testWidgets('invalidated import reports the more specific warning', (
    tester,
  ) async {
    await render(tester, current: false, notionApplied: true);
    expect(
      find.textContaining('import may already have written'),
      findsOneWidget,
    );
    expect(find.byType(EditorForm), findsNothing);
  });

  testWidgets('loading replaces only the form and reports state to owner', (
    tester,
  ) async {
    await render(tester);
    changes.add(BlogUploadLoading());
    await tester.pump();
    expect(received.single, isA<BlogUploadLoading>());
    expect(find.byType(NoWaveLoadingLabel), findsOneWidget);
    expect(find.byType(EditorForm), findsNothing);
    expect(find.byType(EditorAppBar), findsOneWidget);
    changes.add(BlogUploadInitial());
    await tester.pump();
    expect(find.byType(EditorForm), findsOneWidget);
  });

  testWidgets('new article has no export action', (tester) async {
    await render(tester);
    final appBar = tester.widget<EditorAppBar>(find.byType(EditorAppBar));
    expect(appBar.isEditing, isFalse);
    expect(appBar.onExportNotion, isNull);
  });
}

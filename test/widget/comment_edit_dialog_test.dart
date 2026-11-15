import 'dart:async';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_edit_result.dart';
import 'package:belog/features/blog/presentation/comments/comment_edit_dialog.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Bloc extends Mock implements CommentBloc {}

class _Identity implements NowaveSessionIdentity {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  String? activeUserId = 'author';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 1;
  @override
  Stream<void> get identityChanges => changes.stream;
  void signOut() {
    activeUserId = null;
    accessToken = null;
    sessionGeneration++;
    changes.add(null);
  }
}

const _fence = NowaveSessionFence(userId: 'author', generation: 1);
Comment _comment() => Comment(
  id: 'c1',
  articleId: 'work',
  authorId: 'author',
  content: 'old words',
  isPlainText: true,
  createdAt: DateTime.utc(2025),
);

void main() {
  late _Bloc bloc;
  late _Identity identity;
  setUpAll(() {
    registerFallbackValue(_comment());
    registerFallbackValue(_fence);
  });
  setUp(() {
    bloc = _Bloc();
    identity = _Identity();
    when(() => bloc.sessionIdentity).thenReturn(identity);
  });
  tearDown(() async => identity.changes.close());

  Future<void> open(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => CommentEditDialog(
                  comment: _comment(),
                  bloc: bloc,
                  fence: _fence,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('cancel preserves original and sends no request', (tester) async {
    await open(tester);
    expect(find.text('old words'), findsOneWidget);
    expect(
      find.textContaining('Changes made on another device'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'draft correction');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this correction?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(CommentEditDialog), findsNothing);
    verifyNever(
      () => bloc.editPlainComment(
        original: any(named: 'original'),
        text: any(named: 'text'),
        fence: any(named: 'fence'),
      ),
    );
  });
  testWidgets('rejection preserves input and allows manual retry', (
    tester,
  ) async {
    when(
      () => bloc.editPlainComment(
        original: any(named: 'original'),
        text: any(named: 'text'),
        fence: any(named: 'fence'),
      ),
    ).thenAnswer(
      (_) async => const CommentEditResult(
        CommentEditStatus.rejected,
        failure: Failure('offline', code: 'network.offline'),
      ),
    );
    await open(tester);
    await tester.enterText(find.byType(TextField), 'draft correction');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('draft correction'), findsOneWidget);
    expect(find.byType(CommentEditDialog), findsOneWidget);
    verify(
      () => bloc.editPlainComment(
        original: any(named: 'original'),
        text: 'draft correction',
        fence: any(named: 'fence'),
      ),
    ).called(1);
  });
  testWidgets('unknown result blocks another save until refresh', (
    tester,
  ) async {
    when(
      () => bloc.editPlainComment(
        original: any(named: 'original'),
        text: any(named: 'text'),
        fence: any(named: 'fence'),
      ),
    ).thenAnswer(
      (_) async => const CommentEditResult(CommentEditStatus.outcomeUnknown),
    );
    await open(tester);
    await tester.enterText(find.byType(TextField), 'draft correction');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('result is unknown'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
  });
  testWidgets('session replacement immediately hides draft and blocks save', (
    tester,
  ) async {
    await open(tester, locale: const Locale('zh'));
    await tester.enterText(find.byType(TextField), 'private correction');
    identity.signOut();
    await tester.pump();
    expect(find.text('private correction'), findsNothing);
    expect(find.text('登录会话已改变，请关闭编辑器后重新开始。'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
          .onPressed,
      isNull,
    );
  });
}

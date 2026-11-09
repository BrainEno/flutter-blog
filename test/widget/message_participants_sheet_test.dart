import 'package:belog/core/error/failures.dart';
import 'package:belog/features/messages/domain/entities/message_participant.dart';
import 'package:belog/features/messages/presentation/pages/message_participants_sheet.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import '../support/message_fakes.dart';

class _Harness {
  _Harness({this.locale = const Locale('en')});

  final Locale locale;
  List<AuthorSearchResult> searchResults = const [];
  Failure? updateFailure;
  final List<String> queries = [];
  final List<({List<String> add, List<String> remove})> updates = [];

  Future<Either<Failure, List<AuthorSearchResult>>> search(String query) async {
    queries.add(query);
    return right(searchResults);
  }

  Future<Failure?> update({
    required List<String> addUserIds,
    required List<String> removeUserIds,
  }) async {
    updates.add((
      add: List.unmodifiable(addUserIds),
      remove: List.unmodifiable(removeUserIds),
    ));
    return updateFailure;
  }

  Widget app() => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => MessageParticipantsSheet(
                conversation: testConversation(),
                viewerId: 'user-a',
                participants: const {
                  'user-a': MessageParticipant(
                    userId: 'user-a',
                    displayName: 'Creator',
                  ),
                  'user-b': MessageParticipant(
                    userId: 'user-b',
                    displayName: 'Reader B',
                  ),
                },
                searchAuthors: search,
                updateParticipants: update,
              ),
            ),
            child: const Text('Open manager'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the complete-history disclosure before member changes', (
    tester,
  ) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.tap(find.text('Open manager'));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.text(l10n.messagesParticipantsHistoryWarning), findsOneWidget);
    expect(find.text(l10n.messagesParticipantsCurrent), findsOneWidget);
    expect(find.text('Reader B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding a searched author requires explicit history consent', (
    tester,
  ) async {
    final harness = _Harness()
      ..searchResults = const [
        AuthorSearchResult(userId: 'user-c', displayName: 'New author'),
      ];
    await tester.pumpWidget(harness.app());
    await tester.tap(find.text('Open manager'));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.text(l10n.messagesParticipantsAddAction));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(harness.queries, ['New']);
    expect(find.text('New author'), findsOneWidget);
    await tester.tap(find.text('New author'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.messagesParticipantsAddSelected(1)));
    await tester.pumpAndSettle();

    expect(find.text(l10n.messagesParticipantsHistoryWarning), findsNWidgets(2));
    expect(find.text(l10n.messagesParticipantsAddConfirmTitle(1)), findsOneWidget);
    await tester.tap(find.text(l10n.messagesParticipantsConfirmAdd));
    await tester.pumpAndSettle();

    expect(harness.updates.single.add, ['user-c']);
    expect(harness.updates.single.remove, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an update with unknown outcome cannot be retried in the same sheet', (
    tester,
  ) async {
    final harness = _Harness()
      ..searchResults = const [
        AuthorSearchResult(userId: 'user-c', displayName: 'New author'),
      ]
      ..updateFailure = const Failure(
        'timeout',
        kind: FailureKind.network,
        code: 'network.timeout',
      );
    await tester.pumpWidget(harness.app());
    await tester.tap(find.text('Open manager'));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.text(l10n.messagesParticipantsAddAction));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New author'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.messagesParticipantsAddSelected(1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.messagesParticipantsConfirmAdd));
    await tester.pumpAndSettle();

    expect(harness.updates, hasLength(1));
    expect(find.text(l10n.messagesParticipantsOutcomeUnknown), findsOneWidget);
    final retry = tester.widget<FilledButton>(
      find.widgetWithText(
        FilledButton,
        l10n.messagesParticipantsAddSelected(1),
      ),
    );
    expect(retry.onPressed, isNull);

    await tester.tap(find.byTooltip(l10n.actionClose));
    await tester.pumpAndSettle();
    expect(find.text(l10n.messagesParticipantsSearchScope), findsNothing);
    expect(harness.updates, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picker excludes existing members from author search', (
    tester,
  ) async {
    final harness = _Harness()
      ..searchResults = const [
        AuthorSearchResult(userId: 'user-b', displayName: 'Reader B'),
        AuthorSearchResult(userId: 'user-c', displayName: 'New author'),
      ];
    await tester.pumpWidget(harness.app());
    await tester.tap(find.text('Open manager'));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.text(l10n.messagesParticipantsAddAction));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Reader');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Reader B'), findsNothing);
    expect(find.text('New author'), findsOneWidget);
    expect(harness.updates, isEmpty);
  });

  testWidgets('removing a member does not claim their messages are deleted', (
    tester,
  ) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.tap(find.text('Open manager'));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.byTooltip(l10n.messagesParticipantsRemoveAction));
    await tester.pumpAndSettle();

    expect(find.text(l10n.messagesParticipantsRemoveBody), findsOneWidget);
    await tester.tap(find.text(l10n.messagesParticipantsRemoveAction));
    await tester.pumpAndSettle();

    expect(harness.updates.single.add, isEmpty);
    expect(harness.updates.single.remove, ['user-b']);
    expect(tester.takeException(), isNull);
  });
}

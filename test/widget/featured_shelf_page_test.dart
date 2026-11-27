import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/auth/domain/account_editorial_capacity.dart';
import 'package:belog/features/auth/domain/repository/account_editorial_repository.dart';
import 'package:belog/features/blog/domain/entities/featured_shelf_entry.dart';
import 'package:belog/features/blog/domain/repositories/featured_shelf_repository.dart';
import 'package:belog/features/blog/presentation/pages/featured_shelf_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

/// A session the screen can fence against, with the account switch the page is
/// built to survive.
class _Identity implements NowaveSessionIdentity {
  String? userId = 'user-a';
  String? token = 'fake-token-a';
  int generation = 1;
  final controller = StreamController<void>.broadcast(sync: true);

  @override
  String? get activeUserId => userId;

  @override
  String? get accessToken => token;

  @override
  int get sessionGeneration => generation;

  @override
  Stream<void> get identityChanges => controller.stream;

  void signOut() {
    generation++;
    userId = null;
    token = null;
    controller.add(null);
  }
}

/// Records every call and answers by hand, so a test can assert the exact body
/// of the write rather than only that a button looked enabled.
class _Shelf implements FeaturedShelfRepository {
  final loadLocales = <String>[];
  final loadPending = <Completer<Either<Failure, List<FeaturedShelfEntry>>>>[];
  final browseQueries = <String>[];
  final browsePending =
      <Completer<Either<Failure, List<FeaturedShelfEntry>>>>[];
  final saves = <_Save>[];
  final savePending = <Completer<Either<Failure, FeaturedShelfSaveResult>>>[];

  @override
  Future<Either<Failure, List<FeaturedShelfEntry>>> load({
    required String locale,
  }) {
    loadLocales.add(locale);
    final result = Completer<Either<Failure, List<FeaturedShelfEntry>>>();
    loadPending.add(result);
    return result.future;
  }

  @override
  Future<Either<Failure, List<FeaturedShelfEntry>>> browse({
    required String locale,
    String query = '',
  }) {
    browseQueries.add(query);
    final result = Completer<Either<Failure, List<FeaturedShelfEntry>>>();
    browsePending.add(result);
    return result.future;
  }

  @override
  Future<Either<Failure, FeaturedShelfSaveResult>> save({
    required NowaveSessionFence fence,
    required String locale,
    required List<String> articleIds,
  }) {
    saves.add(_Save(fence: fence, locale: locale, ids: articleIds));
    final result = Completer<Either<Failure, FeaturedShelfSaveResult>>();
    savePending.add(result);
    return result.future;
  }
}

class _Save {
  _Save({required this.fence, required this.locale, required this.ids});

  final NowaveSessionFence fence;
  final String locale;
  final List<String> ids;
}

/// `null` capacity stands for "the read did not answer", which the page must
/// keep distinct from a `denied`.
class _Editorial implements AccountEditorialRepository {
  _Editorial(this.capacity);

  AccountEditorialCapacity? capacity;
  int calls = 0;

  @override
  Future<Either<Failure, AccountEditorialCapacity>> readCapacity(
    NowaveSessionFence fence,
  ) async {
    calls++;
    final answer = capacity;
    if (answer == null) return left(Failure('the read did not answer'));
    return right(answer);
  }
}

FeaturedShelfEntry _entry(String id, String title) =>
    FeaturedShelfEntry(articleId: id, slug: 'slug-$id', title: title);

final _shelf2 = [
  _entry('id-a', 'Long first piece'),
  _entry('id-b', 'Second piece'),
];

class _Harness {
  _Harness({this.capacity = AccountEditorialCapacity.granted});

  final AccountEditorialCapacity? capacity;
  final identity = _Identity();
  final shelf = _Shelf();
  late final editorial = _Editorial(capacity);
  final userCubit = AppUserCubit()
    ..updateUser(
      User(
        id: 'user-a',
        email: 'user-a@example.invalid',
        name: 'user-a',
        updatedAt: DateTime.utc(2025),
      ),
    );

  /// The page under test, at any surface size, text scale, and interface
  /// language. The defaults are what every case here already used.
  Future<void> pump(
    WidgetTester tester, {
    Size? surface,
    double? textScale,
    Locale locale = const Locale('en'),
  }) async {
    if (surface != null) {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final scaler = TextScaler.linear(textScale ?? 1);
    final page = FeaturedShelfPage(
      shelf: shelf,
      editorial: editorial,
      identity: identity,
    );
    await tester.pumpWidget(
      BlocProvider<AppUserCubit>.value(
        value: userCubit,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    await tester.pump();
  }

  /// Answers the opening read. `pumpAndSettle` is safe here: the screen's
  /// placeholder is a labelled rule, not a spinner that animates forever.
  Future<void> answer(
    WidgetTester tester,
    List<FeaturedShelfEntry> entries,
  ) async {
    shelf.loadPending.last.complete(right(entries));
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    await userCubit.close();
    await identity.controller.close();
  }
}

const _saveKey = ValueKey('featured-shelf-save');

NoWaveButton _saveButton(WidgetTester tester) =>
    tester.widget<NoWaveButton>(find.byKey(_saveKey));

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('reads the shelf for the content locale, in stored order', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _shelf2);
    // The fallback caveat is never conditional: a curated shelf and a default
    // ranking look the same in the response, so the screen always says so.
    expect(find.text(l10n.featuredShelfFallbackNote), findsOneWidget);

    // The shelf is per content locale, and `ContentLocale` is what the app
    // reads that from - not the interface locale of this MaterialApp.
    expect(harness.shelf.loadLocales, [ContentLocale.instance.tag]);
    expect(find.text('1. Long first piece'), findsOneWidget);
    expect(find.text('2. Second piece'), findsOneWidget);
    expect(
      find.text(l10n.featuredShelfCounter(2, kFeaturedShelfCapacity)),
      findsOneWidget,
    );
    // Nothing is dirty at rest, so the one control that can rewrite the home
    // tab starts out inert.
    expect(_saveButton(tester).onPressed, isNull);
    expect(harness.shelf.saves, isEmpty);
  });

  testWidgets('a move needs a confirmed whole-list write to leave the screen', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _shelf2);

    await tester.tap(find.byIcon(Icons.arrow_upward).at(1));
    await tester.pumpAndSettle();
    expect(find.text('1. Second piece'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNotNull);
    expect(harness.shelf.saves, isEmpty);

    await tester.tap(find.byKey(_saveKey));
    await tester.pumpAndSettle();
    expect(find.text(l10n.featuredShelfConfirmTitle), findsOneWidget);
    // The dialog is the last chance: no request may exist while it is open.
    expect(harness.shelf.saves, isEmpty);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.featuredShelfSave),
      ),
    );
    await tester.pumpAndSettle();
    final save = harness.shelf.saves.single;
    expect(save.ids, ['id-b', 'id-a']);
    expect(save.locale, ContentLocale.instance.tag);
    expect(save.fence.userId, 'user-a');
    expect(save.fence.generation, 1);

    const stored = FeaturedShelfSaveResult(
      FeaturedShelfSave.stored,
      storedIds: ['id-b', 'id-a'],
    );
    harness.shelf.savePending.single.complete(right(stored));
    await tester.pump();
    // The save is followed by a re-read, because the shelf is shared.
    expect(harness.shelf.loadPending, hasLength(2));
    harness.shelf.loadPending.last.complete(right(_shelf2));
    await tester.pumpAndSettle();
    expect(find.text(l10n.featuredShelfSaved), findsOneWidget);
  });

  testWidgets('cancelling the confirmation sends nothing', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _shelf2);
    await tester.tap(find.byIcon(Icons.arrow_downward).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_saveKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.actionCancel),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.shelf.saves, isEmpty);
    expect(_saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('a refusal is reported, and re-read instead of resent', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _shelf2);
    await tester.tap(find.byIcon(Icons.close).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_saveKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.featuredShelfSave),
      ),
    );
    await tester.pumpAndSettle();
    harness.shelf.savePending.single.complete(
      right(const FeaturedShelfSaveResult.refused()),
    );
    await tester.pump();
    expect(harness.shelf.loadPending, hasLength(2));
    harness.shelf.loadPending.last.complete(right([_shelf2[1]]));
    await tester.pumpAndSettle();
    expect(find.text(l10n.featuredShelfRefused), findsOneWidget);
    // One write only. A second send could overwrite what another editor saved.
    expect(harness.shelf.saves, hasLength(1));
  });

  testWidgets('an unreadable answer says so and never resends', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _shelf2);
    await tester.tap(find.byIcon(Icons.arrow_upward).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_saveKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.featuredShelfSave),
      ),
    );
    await tester.pumpAndSettle();
    harness.shelf.savePending.single.complete(
      right(const FeaturedShelfSaveResult.unknown()),
    );
    await tester.pump();
    harness.shelf.loadPending.last.complete(right(_shelf2));
    await tester.pumpAndSettle();
    expect(find.text(l10n.featuredShelfUnknownResult), findsOneWidget);
    expect(harness.shelf.saves, hasLength(1));
  });

  testWidgets('a shelf over capacity explains itself and refuses to send', (
    tester,
  ) async {
    final many = [
      for (var index = 0; index < 21; index++)
        _entry('id-$index', 'Piece $index'),
    ];
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, many);

    expect(
      find.text(l10n.featuredShelfTooMany(kFeaturedShelfCapacity)),
      findsOneWidget,
    );
    expect(_saveButton(tester).onPressed, isNull);
    expect(harness.shelf.saves, isEmpty);
  });

  testWidgets('browse marks what is already on the shelf', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _shelf2);
    // The search control sits after the shelf rows: built, but below the fold
    // of the test window, so it has to be scrolled into reach before a tap.
    await tester.ensureVisible(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    final found = [
      _entry('id-a', 'Long first piece'),
      _entry('id-c', 'A new piece'),
    ];
    harness.shelf.browsePending.single.complete(right(found));
    await tester.pumpAndSettle();
    expect(harness.shelf.browseQueries, ['']);
    expect(find.text(l10n.featuredShelfAlreadyOn), findsOneWidget);
    await tester.ensureVisible(find.text(l10n.featuredShelfBrowseAdd));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.featuredShelfBrowseAdd));
    await tester.pumpAndSettle();
    // Adding is local until the save: it goes to the end of the list.
    expect(find.text('3. A new piece'), findsOneWidget);
    expect(harness.shelf.saves, isEmpty);
    expect(_saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('a role nobody confirmed says the server decides', (
    tester,
  ) async {
    final harness = _Harness(capacity: AccountEditorialCapacity.unknown);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _shelf2);
    expect(find.text(l10n.featuredShelfUnknownRoleNote), findsOneWidget);
    // Asked once for the opening: no polling, no re-read per rebuild.
    expect(harness.editorial.calls, 1);
  });

  testWidgets('a named editor gets no caveat line', (tester) async {
    final harness = _Harness(capacity: AccountEditorialCapacity.granted);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _shelf2);
    expect(find.text(l10n.featuredShelfUnknownRoleNote), findsNothing);
    expect(harness.editorial.calls, 1);
  });

  testWidgets('a signed-out account is shown no editor controls', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.identity.signOut();
    await harness.pump(tester);
    await tester.pumpAndSettle();
    expect(find.text(l10n.errorNotSignedIn), findsOneWidget);
    expect(find.byKey(_saveKey), findsNothing);
    // The read is not spent on a session that cannot be authorised.
    expect(harness.shelf.loadLocales, isEmpty);
  });

  testWidgets('a shelf that reads back different says so', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _shelf2);
    await tester.tap(find.byIcon(Icons.arrow_upward).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_saveKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.featuredShelfSave),
      ),
    );
    await tester.pumpAndSettle();
    const readBack = ['id-a', 'id-b'];
    const stored = FeaturedShelfSaveResult(
      FeaturedShelfSave.stored,
      storedIds: readBack,
    );
    harness.shelf.savePending.single.complete(right(stored));
    await tester.pump();
    // What the server has now is the stored order, not the one on screen.
    await harness.answer(tester, _shelf2);
    expect(find.text(l10n.featuredShelfChangedElsewhere), findsOneWidget);
  });

  // #377 asks for the shelf to hold up on the narrowest phone and the largest
  // text the platforms offer, in both interface languages: an overflow banner
  // across the save bar would lock an editor out of the one screen that
  // rewrites what every reader sees.
  for (final locale in const [Locale('en'), Locale('zh')]) {
    final tag = locale.languageCode;
    testWidgets('$tag keeps the shelf at 320 dp and 2x text', (tester) async {
      final copy = lookupAppLocalizations(locale);
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.pump(
        tester,
        surface: const Size(320, 640),
        textScale: 2,
        locale: locale,
      );
      await harness.answer(tester, _shelf2);

      expect(find.text(copy.featuredShelfTitle), findsOneWidget);
      // The row moves are the whole purpose of the screen, so a clipped one
      // is a bug rather than a layout trade-off.
      expect(find.byTooltip(copy.featuredShelfMoveUp), findsNWidgets(2));
      expect(find.byTooltip(copy.featuredShelfMoveDown), findsNWidgets(2));
      expect(find.byTooltip(copy.featuredShelfRemove), findsNWidgets(2));
      expect(find.byKey(_saveKey), findsOneWidget);
      // An overflow is reported as a test exception, and the counter row is
      // what usually breaks first at this scale.
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('every move is addressable by name', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final three = [
      _entry('id-a', 'First piece'),
      _entry('id-b', 'Second piece'),
      _entry('id-c', 'Third piece'),
    ];
    await harness.answer(tester, three);

    // A reader hears these three names; nothing on this screen needs a drag
    // or the visual position of a row to be described.
    expect(find.byTooltip(l10n.featuredShelfMoveUp), findsNWidgets(3));
    expect(find.byTooltip(l10n.featuredShelfMoveDown), findsNWidgets(3));
    expect(find.byTooltip(l10n.featuredShelfRemove), findsNWidgets(3));

    // Rows sit inside the ListView, so a named control can be built and still
    // be out of reach: scroll to it first, the way a reader has to.
    await tester.ensureVisible(find.byTooltip(l10n.featuredShelfRemove).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.featuredShelfRemove).at(2));
    await tester.pumpAndSettle();
    expect(find.text('3. Third piece'), findsNothing);
    await tester.ensureVisible(find.byTooltip(l10n.featuredShelfMoveUp).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.featuredShelfMoveUp).at(1));
    await tester.pumpAndSettle();
    expect(find.text('1. Second piece'), findsOneWidget);

    await tester.tap(find.byKey(_saveKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.featuredShelfSave),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.shelf.saves.single.ids, ['id-b', 'id-a']);
    const stored = FeaturedShelfSaveResult(
      FeaturedShelfSave.stored,
      storedIds: ['id-b', 'id-a'],
    );
    harness.shelf.savePending.single.complete(right(stored));
    await tester.pump();
    final back = [
      _entry('id-b', 'Second piece'),
      _entry('id-a', 'First piece'),
    ];
    await harness.answer(tester, back);
    expect(find.text(l10n.featuredShelfSaved), findsOneWidget);
  });
}

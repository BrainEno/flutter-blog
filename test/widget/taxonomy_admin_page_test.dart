import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/auth/domain/account_editorial_capacity.dart';
import 'package:belog/features/auth/domain/repository/account_editorial_repository.dart';
import 'package:belog/features/blog/domain/category_paging.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/entities/taxonomy_draft.dart';
import 'package:belog/features/blog/domain/repositories/taxonomy_admin_repository.dart';
import 'package:belog/features/blog/presentation/pages/taxonomy_admin_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

/// A session the screen can fence against, with the account switch it is built
/// to survive.
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

class _Create {
  _Create({required this.fence, required this.draft});

  final NowaveSessionFence fence;
  final TaxonomyDraft draft;
}

/// Records every call and answers by hand, so a test can assert what the screen
/// sent rather than that a button merely looked enabled.
class _Taxonomy implements TaxonomyAdminRepository {
  final cataloguePending = <Completer<Either<Failure, List<CategoryRef>>>>[];
  final creates = <_Create>[];
  final createPending = <Completer<Either<Failure, TaxonomyWrite>>>[];
  final removeIds = <String>[];
  final removePending = <Completer<Either<Failure, TaxonomyWrite>>>[];

  @override
  Future<Either<Failure, List<CategoryRef>>> catalogue() {
    final result = Completer<Either<Failure, List<CategoryRef>>>();
    cataloguePending.add(result);
    return result.future;
  }

  @override
  Future<Either<Failure, TaxonomyWrite>> create({
    required NowaveSessionFence fence,
    required TaxonomyDraft draft,
  }) {
    creates.add(_Create(fence: fence, draft: draft));
    final result = Completer<Either<Failure, TaxonomyWrite>>();
    createPending.add(result);
    return result.future;
  }

  @override
  Future<Either<Failure, TaxonomyWrite>> remove({
    required NowaveSessionFence fence,
    required String id,
  }) {
    removeIds.add(id);
    final result = Completer<Either<Failure, TaxonomyWrite>>();
    removePending.add(result);
    return result.future;
  }
}

const _addKey = ValueKey('taxonomy-admin-add');
const _nameKey = ValueKey('taxonomy-admin-name');
const _slugKey = ValueKey('taxonomy-admin-slug');
const _descriptionKey = ValueKey('taxonomy-admin-description');

const _idA = '11111111-1111-4111-8111-111111111111';
const _idB = '22222222-2222-4222-8222-222222222222';

const _two = [
  CategoryRef(id: _idA, slug: 'noise-2a3b', name: '声音与噪音'),
  CategoryRef(id: _idB, slug: 'long-reads', name: '长读'),
];

NoWaveButton _addButton(WidgetTester tester) {
  return tester.widget<NoWaveButton>(find.byKey(_addKey));
}

String _draftName(WidgetTester tester) {
  return tester.widget<TextField>(find.byKey(_nameKey)).controller!.text;
}

class _Harness {
  _Harness({this.capacity = AccountEditorialCapacity.granted});

  final AccountEditorialCapacity? capacity;
  final identity = _Identity();
  final taxonomy = _Taxonomy();
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

  /// The page under test, at any surface size, text scale and interface
  /// language. The defaults are what every case here uses.
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
    final page = TaxonomyAdminPage(
      taxonomy: taxonomy,
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

  /// Answers the catalogue read the opening makes.
  Future<void> answer(WidgetTester tester, List<CategoryRef> rows) async {
    taxonomy.cataloguePending.last.complete(right(rows));
    await tester.pumpAndSettle();
  }

  /// Types a draft the catalogue would take, in the order the form asks.
  Future<void> typeDraft(WidgetTester tester) async {
    await tester.enterText(find.byKey(_nameKey), '现场录音');
    await tester.enterText(find.byKey(_slugKey), 'field-9c1d');
    await tester.pump();
  }

  Future<void> scrollToAdd(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_addKey));
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    await userCubit.close();
    await identity.controller.close();
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('the opening reads the catalogue and the role once', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    expect(harness.taxonomy.cataloguePending, hasLength(1));
    await harness.answer(tester, _two);

    expect(find.text('声音与噪音'), findsOneWidget);
    expect(find.text('noise-2a3b'), findsOneWidget);
    expect(find.text('长读'), findsOneWidget);
    // One read per opening, and the role asked once: no polling.
    expect(harness.taxonomy.cataloguePending, hasLength(1));
    expect(harness.editorial.calls, 1);
  });

  testWidgets('a full page is called a page, not the catalogue', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final rows = [
      for (var index = 0; index < kCategoryListLimit; index++)
        CategoryRef(id: _idA, slug: 'row-$index', name: 'Row $index'),
    ];
    await harness.answer(tester, rows);

    expect(find.text(l10n.taxonomyAdminPageFull), findsOneWidget);
  });

  testWidgets('a short page does not claim to be truncated', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _two);

    expect(find.text(l10n.taxonomyAdminPageNote), findsOneWidget);
    expect(find.text(l10n.taxonomyAdminPageFull), findsNothing);
    // The Chinese-only store is stated on every opening: it is the one fact an
    // editor cannot infer from the names on screen.
    expect(find.text(l10n.taxonomyAdminLocaleNote), findsOneWidget);
  });

  testWidgets('an unanswered role says the server decides', (tester) async {
    final harness = _Harness(capacity: AccountEditorialCapacity.unknown);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _two);
    expect(find.text(l10n.taxonomyAdminUnknownRoleNote), findsOneWidget);
    expect(harness.editorial.calls, 1);
  });

  testWidgets('a named editor is not given the caveat line', (tester) async {
    final harness = _Harness(capacity: AccountEditorialCapacity.granted);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _two);
    expect(find.text(l10n.taxonomyAdminUnknownRoleNote), findsNothing);
  });

  testWidgets('the add button waits for a draft, not a hope', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _two);
    await harness.scrollToAdd(tester);

    expect(_addButton(tester).onPressed, isNull);
    // An untouched form is not a draft to be scolded about.
    expect(find.text(l10n.taxonomyAdminNameBlank), findsNothing);

    await tester.enterText(find.byKey(_nameKey), '现场录音');
    await tester.pump();
    expect(_addButton(tester).onPressed, isNull);
    expect(find.text(l10n.taxonomyAdminSlugUnreadable), findsOneWidget);

    await tester.enterText(find.byKey(_slugKey), 'field-9c1d');
    await tester.pump();
    expect(_addButton(tester).onPressed, isNotNull);
  });

  testWidgets('the blurb cap is the server cap, exactly', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _two);
    await harness.typeDraft(tester);
    final atTheCap = '字' * kTaxonomyDescriptionLimit;
    await tester.enterText(find.byKey(_descriptionKey), atTheCap);
    await tester.pump();
    await harness.scrollToAdd(tester);

    expect(find.textContaining('$kTaxonomyDescriptionLimit /'), findsOneWidget);
    expect(_addButton(tester).onPressed, isNotNull);

    await tester.enterText(find.byKey(_descriptionKey), '$atTheCap多');
    await tester.pump();
    expect(_addButton(tester).onPressed, isNull);
    expect(find.text(l10n.taxonomyAdminDescriptionTooLong), findsOneWidget);
    expect(harness.taxonomy.creates, isEmpty);
  });

  testWidgets('a create is sent once, fenced, then re-read', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _two);
    await harness.typeDraft(tester);
    await harness.scrollToAdd(tester);
    await tester.tap(find.byKey(_addKey));
    await tester.pumpAndSettle();

    final create = harness.taxonomy.creates.single;
    expect(create.draft.name, '现场录音');
    expect(create.draft.slug, 'field-9c1d');
    expect(create.draft.description, '');
    expect(create.fence.userId, 'user-a');
    expect(create.fence.generation, 1);
    // A create replaces nothing, so it needs no confirmation.
    expect(find.byType(AlertDialog), findsNothing);

    harness.taxonomy.createPending.single.complete(right(TaxonomyWrite.done));
    await tester.pumpAndSettle();
    expect(find.text(l10n.taxonomyAdminAdded), findsOneWidget);
    // The catalogue is shared, so the screen reads it back rather than splicing
    // its own new row into the list.
    expect(harness.taxonomy.cataloguePending, hasLength(2));
    expect(_draftName(tester), isEmpty);
  });

  testWidgets('a refused create says who decides, and still re-reads', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _two);
    await harness.typeDraft(tester);
    await harness.scrollToAdd(tester);
    await tester.tap(find.byKey(_addKey));
    await tester.pumpAndSettle();
    const refused = TaxonomyWrite.refused;
    harness.taxonomy.createPending.single.complete(right(refused));
    await tester.pumpAndSettle();

    expect(find.text(l10n.taxonomyAdminRefused), findsOneWidget);
    expect(harness.taxonomy.cataloguePending, hasLength(2));
    // The draft stays on screen: it was not written, and clearing it would
    // spend the editor's typing on a refusal.
    expect(_draftName(tester), '现场录音');
  });

  testWidgets('a delete is refused until somebody confirms it', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _two);
    await tester.tap(find.byTooltip(l10n.taxonomyAdminRemove).first);
    await tester.pumpAndSettle();

    expect(find.text(l10n.taxonomyAdminConfirmTitle), findsOneWidget);
    expect(harness.taxonomy.removeIds, isEmpty);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.actionCancel),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.taxonomy.removeIds, isEmpty);
    // A cancelled dialog did not even re-read: nothing happened to re-read.
    expect(harness.taxonomy.cataloguePending, hasLength(1));
  });

  testWidgets('a confirmed delete names the row the catalogue carried', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _two);
    await tester.tap(find.byTooltip(l10n.taxonomyAdminRemove).at(1));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.taxonomyAdminRemove),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.taxonomy.removeIds, [_idB]);

    harness.taxonomy.removePending.single.complete(right(TaxonomyWrite.done));
    await tester.pumpAndSettle();
    expect(find.text(l10n.taxonomyAdminRemoved), findsOneWidget);
    expect(harness.taxonomy.cataloguePending, hasLength(2));
  });

  testWidgets('a receipt of false is reported as not removed', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _two);
    await tester.tap(find.byTooltip(l10n.taxonomyAdminRemove).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.taxonomyAdminRemove),
      ),
    );
    await tester.pumpAndSettle();
    harness.taxonomy.removePending.single.complete(
      right(TaxonomyWrite.notRemoved),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.taxonomyAdminNotRemoved), findsOneWidget);
    expect(find.text(l10n.taxonomyAdminRemoved), findsNothing);
  });

  testWidgets('a row without an id is shown but not removable', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final legacy = [const CategoryRef(slug: 'legacy-slug', name: '旧行列')];
    await harness.answer(tester, legacy);

    expect(find.text('旧行列'), findsOneWidget);
    expect(find.text(l10n.taxonomyAdminNoId), findsOneWidget);
    final button = tester.widget<IconButton>(
      find.byTooltip(l10n.taxonomyAdminRemove),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a signed-out account is offered no form', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.identity.signOut();
    await harness.pump(tester);
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorNotSignedIn), findsOneWidget);
    expect(find.byKey(_addKey), findsNothing);
    expect(harness.taxonomy.cataloguePending, isEmpty);
  });

  testWidgets('a failed read is retried by asking again', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final failure = Failure('读不出来', code: 'categories.unavailable');
    harness.taxonomy.cataloguePending.last.complete(left(failure));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.taxonomyAdminRefresh));
    await tester.pumpAndSettle();
    expect(harness.taxonomy.cataloguePending, hasLength(2));
  });

  for (final locale in const [Locale('en'), Locale('zh')]) {
    final tag = locale.languageCode;
    testWidgets('$tag keeps the form at 320 dp and 2x text', (tester) async {
      final copy = lookupAppLocalizations(locale);
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.pump(
        tester,
        surface: const Size(320, 640),
        textScale: 2,
        locale: locale,
      );
      await harness.answer(tester, _two);

      expect(find.text(copy.taxonomyAdminTitle), findsOneWidget);
      for (final key in [_nameKey, _slugKey, _descriptionKey, _addKey]) {
        expect(find.byKey(key), findsOneWidget);
      }
      expect(find.byTooltip(copy.taxonomyAdminRemove), findsNWidgets(2));
      // An overflow shows up as a test exception, and the row name under a
      // badge is what usually breaks first at this scale.
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a delete is reachable by its announced name', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.answer(tester, _two);
    // Rows live inside the ListView, so a named control can be built and still
    // be out of reach: scroll to it first, the way a reader has to.
    await tester.ensureVisible(find.byTooltip(l10n.taxonomyAdminRemove).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.taxonomyAdminRemove).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.taxonomyAdminConfirmTitle), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.taxonomyAdminRemove),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.taxonomy.removeIds, [_idB]);
  });
}

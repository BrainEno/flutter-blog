import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';
import 'package:belog/features/user/domain/usecases/edit_user_usecase.dart';
import 'package:belog/features/user/domain/entities/user_media_asset.dart';
import 'package:belog/features/user/domain/entities/user_media_page.dart';
import 'package:belog/features/user/domain/repositories/user_repository.dart';
import 'package:belog/features/user/domain/usecases/get_user_media_library_page.dart';
import 'package:belog/features/user/presentation/pages/edit_user_info_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockEditUserUseCase extends Mock implements EditUserUseCase {}

class _MockUserRepository extends Mock implements UserRepository {}

/// A signed-in session for the form: the bloc fences the save with it.
class _FakeSession implements NowaveSessionIdentity {
  String? userId = 'u1';
  int generation = 1;
  final controller = StreamController<void>.broadcast(sync: true);

  @override
  String? get activeUserId => userId;

  @override
  String? get accessToken => userId == null ? null : 'token';

  @override
  int get sessionGeneration => generation;

  @override
  Stream<void> get identityChanges => controller.stream;
}

User _user({
  String name = '旧名字',
  String bio = '写诗的人',
  String website = 'https://example.invalid',
}) => User(
  id: 'u1',
  email: 'a@example.invalid',
  name: name,
  bio: bio,
  website: website,
  updatedAt: DateTime.utc(2024),
);

void main() {
  late _MockEditUserUseCase useCase;
  late AppUserCubit appUser;
  late UserEditBloc bloc;
  late _FakeSession session;

  setUpAll(() {
    registerFallbackValue(
      const NowaveSessionFence(userId: 'u1', generation: 1),
    );
    registerFallbackValue(
      EditUserParams(
        userId: '',
        name: '',
        bio: '',
        website: '',
        sessionFence: const NowaveSessionFence(userId: '', generation: 0),
      ),
    );
  });

  setUp(() {
    useCase = _MockEditUserUseCase();
    session = _FakeSession();
    appUser = AppUserCubit()..updateUser(_user());
    bloc = UserEditBloc(
      editUserUseCase: useCase,
      appUserCubit: appUser,
      sessionIdentity: session,
    );
  });

  tearDown(() async {
    await bloc.close();
    await appUser.close();
    await session.controller.close();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    GetUserMediaLibraryPage? getPage,
  }) async {
    // The form is taller than the default 800x600 surface; a save button below
    // the fold makes tap() miss without failing loudly.
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AppUserCubit>.value(value: appUser),
          BlocProvider<UserEditBloc>.value(value: bloc),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EditUserInfoPage(
            sessionIdentity: session,
            getUserMediaLibraryPage: getPage,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a media-library avatar is previewed and sent without bytes', (
    tester,
  ) async {
    const url =
        'https://api.example.invalid/api/v1/media/64f7a2c6-42b6-4b7b-9f89-2d68b8c45a01';
    final repository = _MockUserRepository();
    final asset = UserMediaAsset(
      id: '64f7a2c6-42b6-4b7b-9f89-2d68b8c45a01',
      imageUrl: url,
      width: 1200,
      height: 800,
      byteSize: 4096,
      createdAt: DateTime.utc(2026),
    );
    when(
      () => repository.getMediaLibraryPage(
        sessionFence: any(named: 'sessionFence'),
        cursor: null,
      ),
    ).thenAnswer(
      (_) async => right(UserMediaPage(items: [asset], nextCursor: null)),
    );
    when(
      () => useCase(any()),
    ).thenAnswer((_) async => left(Failure.networkOffline()));
    await pumpPage(tester, getPage: GetUserMediaLibraryPage(repository));
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.tap(find.text(l10n.editProfileChooseAvatarFromLibrary));
    await tester.pumpAndSettle();
    expect(find.text(l10n.userMediaPickerAvatarTitle), findsOneWidget);
    await tester.tap(find.text('1200 × 800'));
    await tester.pumpAndSettle();
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNotNull);
    await tester.tap(find.byType(NoWaveButton));
    await tester.pumpAndSettle();
    final params =
        verify(() => useCase(captureAny())).captured.single as EditUserParams;
    expect(params.uploadedAvatarUrl, url);
    expect(params.avatar, isNull);
    expect(params.sessionFence.userId, 'u1');
    expect(params.sessionFence.generation, 1);
  });

  testWidgets('session change closes the picker and hides the old form', (
    tester,
  ) async {
    final repository = _MockUserRepository();
    when(
      () => repository.getMediaLibraryPage(
        sessionFence: any(named: 'sessionFence'),
        cursor: null,
      ),
    ).thenAnswer(
      (_) async => right(UserMediaPage(items: [], nextCursor: null)),
    );
    await pumpPage(tester, getPage: GetUserMediaLibraryPage(repository));
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.tap(find.text(l10n.editProfileChooseAvatarFromLibrary));
    await tester.pumpAndSettle();
    expect(find.text(l10n.userMediaPickerAvatarTitle), findsOneWidget);
    session.userId = 'u2';
    session.generation++;
    session.controller.add(null);
    await tester.pumpAndSettle();
    expect(find.text(l10n.userMediaPickerAvatarTitle), findsNothing);
    expect(find.text(l10n.editProfileSessionChanged), findsOneWidget);
    expect(find.text('旧名字'), findsNothing);
    verifyNever(() => useCase(any()));
  });

  testWidgets('cancelling the media picker preserves the current avatar', (
    tester,
  ) async {
    final repository = _MockUserRepository();
    when(
      () => repository.getMediaLibraryPage(
        sessionFence: any(named: 'sessionFence'),
        cursor: null,
      ),
    ).thenAnswer(
      (_) async => right(UserMediaPage(items: [], nextCursor: null)),
    );
    when(
      () => useCase(any()),
    ).thenAnswer((_) async => left(Failure.networkOffline()));
    await pumpPage(tester, getPage: GetUserMediaLibraryPage(repository));
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.tap(find.text(l10n.editProfileChooseAvatarFromLibrary));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NoWaveButton));
    await tester.pumpAndSettle();
    final params =
        verify(() => useCase(captureAny())).captured.single as EditUserParams;
    expect(params.uploadedAvatarUrl, isNull);
    expect(params.avatar, isNull);
  });

  testWidgets('same-account re-login invalidates the original form', (
    tester,
  ) async {
    await pumpPage(tester);
    session.generation++;
    session.controller.add(null);
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.editProfileSessionChanged), findsOneWidget);
    expect(find.byType(NoWaveButton), findsNothing);
    verifyNever(() => useCase(any()));
  });

  testWidgets('a late media response cannot revive an invalidated form', (
    tester,
  ) async {
    final repository = _MockUserRepository();
    final pending = Completer<Either<Failure, UserMediaPage>>();
    when(
      () => repository.getMediaLibraryPage(
        sessionFence: any(named: 'sessionFence'),
        cursor: null,
      ),
    ).thenAnswer((_) => pending.future);
    await pumpPage(tester, getPage: GetUserMediaLibraryPage(repository));
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.tap(find.text(l10n.editProfileChooseAvatarFromLibrary));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    session.userId = 'u2';
    session.generation++;
    session.controller.add(null);
    await tester.pump();
    session.userId = 'u1';
    session.generation++;
    session.controller.add(null);
    pending.complete(right(UserMediaPage(items: [], nextCursor: null)));
    await tester.pumpAndSettle();
    expect(find.text(l10n.editProfileSessionChanged), findsOneWidget);
    expect(find.byType(NoWaveButton), findsNothing);
    verifyNever(() => useCase(any()));
  });

  testWidgets('the form is pre-filled with the stored bio and website', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.text('旧名字'), findsOneWidget);
    expect(find.text('写诗的人'), findsOneWidget);
    expect(find.text('https://example.invalid'), findsOneWidget);
  });

  testWidgets('saving only a new name keeps the bio and the website', (
    tester,
  ) async {
    // Fail the write so the page stays mounted (a success pops the route).
    when(() => useCase(any())).thenAnswer((_) async {
      final failure = Failure('保存失败', kind: FailureKind.server);
      return Left<Failure, User>(failure);
    });

    await pumpPage(tester);
    await tester.enterText(find.byType(TextFormField).at(0), '新名字');
    await tester.tap(find.byType(NoWaveButton));
    await tester.pumpAndSettle();

    final params =
        verify(() => useCase(captureAny())).captured.single as EditUserParams;
    expect(params.name, '新名字');
    // The backend stores a missing bio as '', which erased every author's
    // introduction whenever they edited an unrelated field.
    expect(params.bio, '写诗的人');
    expect(params.website, 'https://example.invalid');
  });

  testWidgets('a non-http website is rejected before any request', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextFormField).at(2), 'example.invalid');
    await tester.tap(find.byType(NoWaveButton));
    await tester.pumpAndSettle();

    verifyNever(() => useCase(any()));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text('Use an http:// or https:// address, or leave this empty'),
      findsOneWidget,
    );
  });
}

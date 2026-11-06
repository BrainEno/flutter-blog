import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';
import 'package:belog/features/user/domain/usecases/edit_user_usecase.dart';
import 'package:belog/features/user/presentation/pages/edit_user_info_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockEditUserUseCase extends Mock implements EditUserUseCase {}

/// A signed-in session for the form: the bloc fences the save with it.
class _FakeSession implements NowaveSessionIdentity {
  @override
  String? get activeUserId => 'u1';

  @override
  String? get accessToken => 'token';

  @override
  int get sessionGeneration => 1;

  @override
  Stream<void> get identityChanges => const Stream<void>.empty();
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

  setUpAll(() {
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
    appUser = AppUserCubit()..updateUser(_user());
    bloc = UserEditBloc(
      editUserUseCase: useCase,
      appUserCubit: appUser,
      sessionIdentity: _FakeSession(),
    );
  });

  Future<void> pumpPage(WidgetTester tester) async {
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
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EditUserInfoPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

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

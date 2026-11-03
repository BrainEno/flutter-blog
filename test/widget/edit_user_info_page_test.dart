import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';
import 'package:belog/features/user/domain/usecases/edit_user_usecase.dart';
import 'package:belog/features/user/presentation/pages/edit_user_info_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockEditUserUseCase extends Mock implements EditUserUseCase {}

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
      EditUserParams(userId: '', name: '', bio: '', website: ''),
    );
  });

  setUp(() {
    useCase = _MockEditUserUseCase();
    appUser = AppUserCubit()..updateUser(_user());
    bloc = UserEditBloc(editUserUseCase: useCase, appUserCubit: appUser);
  });

  Future<void> pumpPage(WidgetTester tester) async {
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
    await tester.tap(find.byType(ElevatedButton));
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
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    verifyNever(() => useCase(any()));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text('Use an http:// or https:// address, or leave this empty'),
      findsOneWidget,
    );
  });
}

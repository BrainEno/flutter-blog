import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';
import 'package:belog/features/user/domain/repositories/user_repository.dart';
import 'package:belog/features/user/domain/usecases/edit_user_usecase.dart';
import 'package:belog/features/user/presentation/pages/edit_user_info_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockUserRepository extends Mock implements UserRepository {}

Future<AppLocalizations> _pumpPage(
  WidgetTester tester,
  Locale locale,
) async {
  const website = 'https://example.invalid/profile';
  final appUser = AppUserCubit()
    ..updateUser(
      User(
        id: 'u1',
        email: 'user@example.invalid',
        name: '测试用户',
        bio: '既有简介',
        website: website,
        updatedAt: DateTime.utc(2025),
      ),
    );
  final editBloc = UserEditBloc(
    editUserUseCase: EditUserUseCase(MockUserRepository()),
    appUserCubit: appUser,
  );
  addTearDown(() async {
    await editBloc.close();
    await appUser.close();
  });

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<AppUserCubit>.value(value: appUser),
        BlocProvider<UserEditBloc>.value(value: editBloc),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EditUserInfoPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(EditUserInfoPage)));
}

void main() {
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets('the URL input is labelled as website: $locale', (
      tester,
    ) async {
      final l10n = await _pumpPage(tester, locale);

      final websiteField = find.widgetWithText(
        TextFormField,
        l10n.labelWebsite,
      );
      expect(websiteField, findsOneWidget);
      expect(find.widgetWithText(TextFormField, l10n.labelBio), findsNothing);

      final field = tester.widget<TextFormField>(websiteField);
      expect(field.controller?.text, 'https://example.invalid/profile');
      expect(field.keyboardType, TextInputType.url);
      expect(field.maxLines, 1);
    });
  }
}

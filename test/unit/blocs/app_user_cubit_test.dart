import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:flutter_test/flutter_test.dart';

User _user(String id) => User(
  id: id,
  email: '$id@example.invalid',
  name: id,
  updatedAt: DateTime.utc(2026),
);

void main() {
  test(
    'identity revision notifies synchronously after state changes',
    () async {
      final cubit = AppUserCubit();
      addTearDown(cubit.close);
      final observed = <String?>[];
      cubit.identityRevision.addListener(() {
        final state = cubit.state;
        observed.add(state is AppUserLoggedIn ? state.user.id : null);
      });

      cubit.updateUser(_user('a'));
      cubit.updateUser(_user('b'));
      cubit.updateUser(_user('a'));
      cubit.updateUser(null);
      expect(observed, ['a', 'b', 'a', null]);
      expect(cubit.identityRevision.value, 4);
    },
  );
}

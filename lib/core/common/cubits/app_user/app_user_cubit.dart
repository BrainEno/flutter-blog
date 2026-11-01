import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../entities/user.dart';

part 'app_user_state.dart';

class AppUserCubit extends Cubit<AppUserState> {
  AppUserCubit() : super(AppUserInitial());

  final ValueNotifier<int> _identityRevision = ValueNotifier<int>(0);

  /// Synchronous invalidation signal for account-sensitive screens. The
  /// ordinary Cubit stream remains unchanged; listeners should inspect
  /// [state], not treat this revision as an authorization claim.
  ValueListenable<int> get identityRevision => _identityRevision;

  void updateUser(User? user) {
    if (user == null) {
      emit(AppUserInitial());
    } else {
      emit(AppUserLoggedIn(user));
    }
    _identityRevision.value++;
  }

  @override
  Future<void> close() {
    if (!isClosed) _identityRevision.dispose();
    return super.close();
  }
}

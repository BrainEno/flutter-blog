import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/usecases/edit_user_usecase.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'user_edit_event.dart';
part 'user_edit_state.dart';

class UserEditBloc extends Bloc<UserEditEvent, UserEditState> {
  final EditUserUseCase _editUserUseCase;
  final AppUserCubit appUserCubit;

  UserEditBloc({
    required EditUserUseCase editUserUseCase,
    required this.appUserCubit,
  }) : _editUserUseCase = editUserUseCase,
       super(UserEditInitial()) {
    on<UserEditSubmitted>(_onEditUserSubmitted);
  }

  Future<void> _onEditUserSubmitted(
    UserEditSubmitted event,
    Emitter<UserEditState> emit,
  ) async {
    emit(UserEditLoading());
    if (appUserCubit.state is! AppUserLoggedIn) {
      emit(
        UserEditFailure(
          failure: Failure(
            '用户未登录',
            kind: FailureKind.auth,
            code: 'auth.notSignedIn',
          ),
        ),
      );
      return;
    }

    final params = EditUserParams(
      userId: (appUserCubit.state as AppUserLoggedIn).user.id,
      name: event.name,
      avatar: event.avatar,
      avatarMimeType: event.avatarMimeType,
      website: event.website ?? '',
    );

    final result = await _editUserUseCase(params);
    result.fold(
      (failure) {
        emit(UserEditFailure(failure: failure.forPresentation()));
      },
      (user) {
        appUserCubit.updateUser(user);
        emit(UserEditSuccess());
      },
    );
  }
}

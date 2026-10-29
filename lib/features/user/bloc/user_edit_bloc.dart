import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
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
      emit(UserEditFailure(message: "用户未登录"));
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
        emit(UserEditFailure(message: "编辑用户资料失败,${failure.message}"));
      },
      (user) {
        appUserCubit.updateUser(user);
        emit(UserEditSuccess());
      },
    );
  }
}

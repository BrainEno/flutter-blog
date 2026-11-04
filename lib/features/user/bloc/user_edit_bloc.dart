import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/domain/usecases/edit_user_usecase.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'user_edit_event.dart';
part 'user_edit_state.dart';

class UserEditBloc extends Bloc<UserEditEvent, UserEditState> {
  final EditUserUseCase _editUserUseCase;
  final AppUserCubit appUserCubit;

  /// The live session, used to fence the save against an account switch.
  final NowaveSessionIdentity? _session;

  UserEditBloc({
    required EditUserUseCase editUserUseCase,
    required this.appUserCubit,
    NowaveSessionIdentity? sessionIdentity,
  }) : _editUserUseCase = editUserUseCase,
       _session = sessionIdentity,
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

    // Capture the account that is opening this save, once, before any await.
    // The use case carries the fence across the profile read, the avatar
    // upload and the profile write, so a switch cannot redirect the save into
    // another account - and a same-account re-login gets a new generation,
    // which the fence treats as a different operation too (#104).
    final fence = _currentFence();
    if (fence == null) {
      emit(UserEditFailure(failure: _notSignedIn()));
      return;
    }

    final params = EditUserParams(
      userId: (appUserCubit.state as AppUserLoggedIn).user.id,
      name: event.name,
      avatar: event.avatar,
      avatarMimeType: event.avatarMimeType,
      bio: event.bio ?? '',
      website: event.website ?? '',
      sessionFence: fence,
    );

    final result = await _editUserUseCase(params);
    result.fold(
      (failure) {
        emit(UserEditFailure(failure: failure.forPresentation()));
      },
      (user) {
        // The write may have landed just as the account changed: publishing it
        // would paint account A's profile into account B's UI.
        if (!_isCurrent(fence)) {
          emit(UserEditFailure(failure: _sessionChanged()));
          return;
        }
        appUserCubit.updateUser(user);
        emit(UserEditSuccess());
      },
    );
  }

  NowaveSessionFence? _currentFence() {
    final session = _session;
    final userId = session?.activeUserId ?? '';
    if (session == null || userId.isEmpty) return null;
    return NowaveSessionFence(
      userId: userId,
      generation: session.sessionGeneration,
    );
  }

  bool _isCurrent(NowaveSessionFence fence) {
    final session = _session;
    if (session == null) return false;
    return session.activeUserId == fence.userId &&
        session.sessionGeneration == fence.generation;
  }

  Failure _notSignedIn() =>
      Failure('用户未登录', kind: FailureKind.auth, code: 'auth.notSignedIn');

  Failure _sessionChanged() => Failure(
    '登录账户已变更，资料未保存',
    kind: FailureKind.auth,
    code: 'auth.sessionChanged',
  );
}

import 'package:belog/features/user/domain/usecases/change_email_usecase.dart';
import 'package:belog/features/user/domain/usecases/reset_password_usecase.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'edit_account_event.dart';
part 'edit_account_state.dart';

class EditAccountBloc extends Bloc<EditAccountEvent, EditAccountState> {
  final ChangeEmailUseCase changeEmailUseCase;
  final ResetPasswordUseCase resetPasswordUseCase;

  EditAccountBloc({
    required this.changeEmailUseCase,
    required this.resetPasswordUseCase,
  }) : super(EditAccountInitial()) {
    on<ChangeEmailEvent>(_onChangeEmail);
    on<ResetPasswordEvent>(_onResetPassword);
  }

  Future<void> _onChangeEmail(
    ChangeEmailEvent event,
    Emitter<EditAccountState> emit,
  ) async {
    emit(EditAccountLoading());
    final result = await changeEmailUseCase(event.newEmail);
    result.fold(
      (failure) => emit(EditAccountFailure(message: failure.message)),
      // Supabase sends a confirmation e-mail to the new address: the
      // change only takes effect once the user confirms it there.
      (_) => emit(
        EditAccountSuccess(message: '确认邮件已发送至新邮箱，请查收并完成验证'),
      ),
    );
  }

  Future<void> _onResetPassword(
    ResetPasswordEvent event,
    Emitter<EditAccountState> emit,
  ) async {
    emit(EditAccountLoading());
    final result = await resetPasswordUseCase(event.newPassword);
    result.fold(
      (failure) => emit(EditAccountFailure(message: failure.message)),
      // Sessions on other devices are revoked by the data source after a
      // successful change; this device stays signed in.
      (_) => emit(EditAccountSuccess(message: '密码已修改，其他设备已退出登录')),
    );
  }
}

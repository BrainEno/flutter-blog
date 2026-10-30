part of 'user_edit_bloc.dart';

abstract class UserEditState extends Equatable {
  const UserEditState();

  @override
  List<Object> get props => [];
}

class UserEditInitial extends UserEditState {}

class UserEditLoading extends UserEditState {}

class UserEditSuccess extends UserEditState {}

class UserEditFailure extends UserEditState {
  final Failure failure;

  const UserEditFailure({required this.failure});

  /// Display-safe Chinese fallback, composed as before (issue #24): the
  /// UI localizes via `errorProfileSavePrefix` + `localizedFailure`.
  String get message => '编辑用户资料失败,${failure.message}';

  @override
  List<Object> get props => [message];
}

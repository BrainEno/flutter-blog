part of 'user_edit_bloc.dart';

abstract class UserEditEvent extends Equatable {
  const UserEditEvent();

  @override
  List<Object> get props => [];
}

/// Profile display data submission. The e-mail address is not part of it:
/// it only changes through the account-security flow (Supabase Auth
/// update + confirmation e-mail).
class UserEditSubmitted extends UserEditEvent {
  final String name;
  final String? website;
  final File? avatar;

  const UserEditSubmitted({
    required this.name,
    this.website,
    this.avatar,
  });

  @override
  List<Object> get props => [name, avatar ?? '', website ?? ''];
}

part of 'user_edit_bloc.dart';

abstract class UserEditEvent extends Equatable {
  const UserEditEvent();

  @override
  List<Object> get props => [];
}

/// Profile display data submission. The e-mail address is not part of it:
/// the backend offers no e-mail change endpoint yet (gap G2, see
/// docs/supabase-to-nowave-migration.md).
class UserEditSubmitted extends UserEditEvent {
  final String name;
  final String? bio;
  final String? website;
  final ImageUpload? avatar;

  const UserEditSubmitted({
    required this.name,
    this.bio,
    this.website,
    this.avatar,
  });

  @override
  List<Object> get props => [name, avatar ?? '', bio ?? '', website ?? ''];
}

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
  final String? website;
  final File? avatar;

  /// MIME type reported by the picker; uploaded as the object's
  /// contentType.
  final String? avatarMimeType;

  const UserEditSubmitted({
    required this.name,
    this.website,
    this.avatar,
    this.avatarMimeType,
  });

  @override
  List<Object> get props => [name, avatar ?? '', website ?? ''];
}

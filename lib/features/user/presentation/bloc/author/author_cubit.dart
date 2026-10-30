import 'package:belog/features/user/domain/entities/author_profile.dart';
import 'package:belog/features/user/domain/usecases/author.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class AuthorState {
  const AuthorState();
}

final class AuthorLoading extends AuthorState {
  const AuthorLoading();
}

final class AuthorFailure extends AuthorState {
  final String error;
  const AuthorFailure(this.error);
}

final class AuthorLoaded extends AuthorState {
  final AuthorProfile profile;

  /// Guards the follow button against rapid taps: exactly one follow or
  /// unfollow request is in flight.
  final bool followInFlight;

  /// Display-safe error of the last failed follow/unfollow; empty when the
  /// last action succeeded. The profile is untouched on failure, so the
  /// button keeps showing the server-resolved state.
  final String followError;

  const AuthorLoaded({
    required this.profile,
    this.followInFlight = false,
    this.followError = '',
  });

  AuthorLoaded copyWith({
    AuthorProfile? profile,
    bool? followInFlight,
    String? followError,
  }) {
    return AuthorLoaded(
      profile: profile ?? this.profile,
      followInFlight: followInFlight ?? this.followInFlight,
      followError: followError ?? this.followError,
    );
  }
}

/// Page-scoped Cubit backing the author profile page (issue #20).
///
/// The follow state always comes from the server: loads resolve
/// `isFollowing` against the viewer, and every follow/unfollow returns
/// the fresh profile, which replaces the local one. A failed toggle
/// leaves the previous server state in place.
class AuthorCubit extends Cubit<AuthorState> {
  final GetAuthorProfile _getAuthorProfile;
  final FollowAuthor _followAuthor;
  final UnfollowAuthor _unfollowAuthor;
  final String userId;

  AuthorCubit({
    required GetAuthorProfile getAuthorProfile,
    required FollowAuthor followAuthor,
    required UnfollowAuthor unfollowAuthor,
    required this.userId,
  }) : _getAuthorProfile = getAuthorProfile,
       _followAuthor = followAuthor,
       _unfollowAuthor = unfollowAuthor,
       super(const AuthorLoading()) {
    load();
  }

  Future<void> load() async {
    emit(const AuthorLoading());
    final res = await _getAuthorProfile(userId);
    res.fold(
      (failure) => emit(AuthorFailure(failure.message)),
      (profile) => emit(AuthorLoaded(profile: profile)),
    );
  }

  Future<void> toggleFollow() async {
    final state = this.state;
    if (state is! AuthorLoaded || state.followInFlight) {
      return;
    }

    final wasFollowing = state.profile.isFollowing;
    emit(state.copyWith(followInFlight: true, followError: ''));
    final res = await (wasFollowing
        ? _unfollowAuthor(userId)
        : _followAuthor(userId));
    res.fold(
      (failure) => emit(
        state.copyWith(
          followInFlight: false,
          followError: failure.message.isNotEmpty
              ? failure.message
              : '关注操作失败，请稍后重试',
        ),
      ),
      // The server sends the fresh profile back: the new follow state and
      // counts are its answer, not a local simulation.
      (profile) => emit(AuthorLoaded(profile: profile, followInFlight: false)),
    );
  }
}

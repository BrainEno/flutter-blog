import 'package:belog/core/error/failures.dart';
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
  final Failure failure;
  const AuthorFailure(this.failure);

  /// Display-safe Chinese fallback; the UI localizes via
  /// `localizedFailure` (issue #24).
  String get error => failure.message;
}

final class AuthorLoaded extends AuthorState {
  final AuthorProfile profile;

  /// Guards the follow button against rapid taps: exactly one follow or
  /// unfollow request is in flight.
  final bool followInFlight;

  /// Failure of the last failed follow/unfollow; null when the last
  /// action succeeded. The profile is untouched on failure, so the button
  /// keeps showing the server-resolved state. The UI localizes it via
  /// `localizedFailure` (issue #24).
  final Failure? followFailure;

  const AuthorLoaded({
    required this.profile,
    this.followInFlight = false,
    this.followFailure,
  });

  /// Display-safe Chinese fallback of [followFailure]; empty when null.
  String get followError => followFailure?.message ?? '';

  AuthorLoaded copyWith({
    AuthorProfile? profile,
    bool? followInFlight,
    Failure? followFailure,
    bool clearFollowFailure = false,
  }) {
    return AuthorLoaded(
      profile: profile ?? this.profile,
      followInFlight: followInFlight ?? this.followInFlight,
      followFailure: clearFollowFailure
          ? null
          : followFailure ?? this.followFailure,
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
      (failure) => emit(AuthorFailure(failure.forPresentation())),
      (profile) => emit(AuthorLoaded(profile: profile)),
    );
  }

  Future<void> toggleFollow() async {
    final state = this.state;
    if (state is! AuthorLoaded || state.followInFlight) {
      return;
    }

    final wasFollowing = state.profile.isFollowing;
    emit(state.copyWith(followInFlight: true, clearFollowFailure: true));
    final res = await (wasFollowing
        ? _unfollowAuthor(userId)
        : _followAuthor(userId));
    res.fold(
      (failure) => emit(
        state.copyWith(
          followInFlight: false,
          followFailure: failure.message.isNotEmpty
              ? failure.forPresentation()
              : Failure('关注操作失败，请稍后重试', code: 'follow.toggle'),
        ),
      ),
      // The server sends the fresh profile back: the new follow state and
      // counts are its answer, not a local simulation.
      (profile) => emit(AuthorLoaded(profile: profile, followInFlight: false)),
    );
  }
}

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/common/widgets/no_wave_section_heading.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/l10n/display_name_l10n.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/tag_navigation.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:belog/features/user/domain/entities/author_profile.dart';
import 'package:belog/features/user/domain/entities/author_relationship.dart';
import 'package:belog/features/user/presentation/bloc/author/author_cubit.dart';
import 'package:belog/router/shell_branch_location.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public author profile page (issue #20): who they are, the follow
/// relationship, and their published articles.
///
/// The follow state is server-resolved end to end — loads resolve
/// `isFollowing` against the viewer, and every toggle replaces the
/// profile with the fresh one the server returns. Signed-out visitors
/// are routed to login instead of a fake state; the author's own page
/// shows no follow button at all.
class AuthorPage extends StatefulWidget {
  final String userId;

  const AuthorPage({super.key, required this.userId});

  @override
  State<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends State<AuthorPage> {
  @override
  void initState() {
    super.initState();
    context.read<BlogByBloc>().add(GetBlogByPosterEvent(userId: widget.userId));
  }

  void _requestLogin() {
    final currentLocation = GoRouterState.of(context).uri.toString();
    context.push('/login?redirect=${Uri.encodeComponent(currentLocation)}');
  }

  Future<void> _openWebsite(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      if (mounted) showSnackBar(context, context.l10n.invalidLink);
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      showSnackBar(context, context.l10n.cannotOpenLink);
    }
  }

  void _openRelationships(AuthorRelationshipKind kind) {
    context.push(
      shellBranchLocation(
        GoRouterState.of(context).uri,
        '/author/${Uri.encodeComponent(widget.userId)}/${kind.name}',
      ),
    );
  }

  /// Opens the private-message flow with this author.
  ///
  /// The inbox behind `/profile/messages` decides whether a conversation
  /// already exists: creating one here would open a second thread with the
  /// same person, because the server treats every create as a new conversation.
  void _messageAuthor() {
    final appUserState = context.read<AppUserCubit>().state;
    if (appUserState is! AppUserLoggedIn) {
      showSnackBar(context, context.l10n.signInRequired);
      _requestLogin();
      return;
    }
    context.push('/profile/messages?to=${Uri.encodeComponent(widget.userId)}');
  }

  void _onFollowTap() {
    final appUserState = context.read<AppUserCubit>().state;
    if (appUserState is! AppUserLoggedIn) {
      showSnackBar(context, context.l10n.signInRequired);
      _requestLogin();
      return;
    }
    context.read<AuthorCubit>().toggleFollow();
  }

  @override
  Widget build(BuildContext context) {
    final appUserState = context.watch<AppUserCubit>().state;
    final viewerId = appUserState is AppUserLoggedIn
        ? appUserState.user.id
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.authorTitle)),
      body: BlocConsumer<AuthorCubit, AuthorState>(
        listenWhen: (previous, current) =>
            current is AuthorLoaded &&
            previous is AuthorLoaded &&
            current.followError != previous.followError &&
            current.followError.isNotEmpty,
        listener: (context, state) {
          showSnackBar(
            context,
            localizedFailure(
              context.l10n,
              (state as AuthorLoaded).followFailure!,
            ),
          );
        },
        builder: (context, state) {
          if (state is AuthorLoading) {
            return Center(
              child: CircularProgressIndicator(
                semanticsLabel: context.l10n.loading,
              ),
            );
          }
          if (state is AuthorFailure) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(NoWaveSpacing.medium),
                child: NoWaveStatus(
                  message: state.error.isNotEmpty
                      ? localizedFailure(context.l10n, state.failure)
                      : context.l10n.authorMissing,
                  actionLabel: context.l10n.actionRetry,
                  onAction: () => context.read<AuthorCubit>().load(),
                ),
              ),
            );
          }
          final loaded = state as AuthorLoaded;
          final profile = loaded.profile;
          final isSelf = viewerId != null && viewerId == profile.userId;

          return ListView(
            padding: const EdgeInsets.all(NoWaveSpacing.medium),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProfileHeader(
                        profile: profile,
                        onOpenWebsite: _openWebsite,
                        onOpenFollowers: () => _openRelationships(
                          AuthorRelationshipKind.followers,
                        ),
                        onOpenFollowing: () => _openRelationships(
                          AuthorRelationshipKind.following,
                        ),
                      ),
                      const SizedBox(height: NoWaveSpacing.medium),
                      // Side by side rather than stacked: the follow button
                      // already sets this row's height, and growing the header
                      // pushes the article list out of reach on small screens.
                      Wrap(
                        spacing: NoWaveSpacing.small,
                        runSpacing: NoWaveSpacing.small,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _FollowButton(
                            loaded: loaded,
                            isSelf: isSelf,
                            onTap: _onFollowTap,
                          ),
                          if (!isSelf)
                            TextButton.icon(
                              onPressed: _messageAuthor,
                              icon: const Icon(Icons.mail_outline, size: 16),
                              label: Text(context.l10n.messagesStart),
                            ),
                        ],
                      ),
                      const SizedBox(height: NoWaveSpacing.section),
                      const Divider(height: 1),
                      const SizedBox(height: NoWaveSpacing.medium),
                      NoWaveSectionHeading(
                        title: context.l10n.authorArticlesTitle,
                      ),
                      const SizedBox(height: NoWaveSpacing.medium),
                      BlocBuilder<BlogByBloc, BlogByState>(
                        builder: (context, articleState) {
                          if (articleState is GetBlogsByUserLoading ||
                              articleState is BlogByInitial) {
                            return Center(
                              child: CircularProgressIndicator(
                                semanticsLabel: context.l10n.loadingArticles,
                              ),
                            );
                          }
                          if (articleState is GetBlogsByUserFailure) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: NoWaveSpacing.large,
                              ),
                              child: NoWaveStatus(
                                message: articleState.error.isNotEmpty
                                    ? localizedFailure(
                                        context.l10n,
                                        articleState.failure,
                                      )
                                    : context.l10n.authorArticlesLoadFailed,
                                actionLabel: context.l10n.actionRetry,
                                onAction: () => context.read<BlogByBloc>().add(
                                  GetBlogByPosterEvent(userId: widget.userId),
                                ),
                              ),
                            );
                          }
                          final blogs = articleState is GetBlogsByUserSuccess
                              ? articleState.blogs
                              : const [];
                          if (blogs.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: NoWaveSpacing.large,
                              ),
                              child: Center(
                                child: NoWaveStatus(
                                  message: context.l10n.authorNoArticles,
                                ),
                              ),
                            );
                          }
                          return Column(
                            children: [
                              for (var index = 0; index < blogs.length; index++)
                                BlogCard(
                                  blog: blogs[index],
                                  index: index + 1,
                                  onTagTap: (tag) =>
                                      openTagArticles(context, tag),
                                  onTap: () => context.push(
                                    shellBranchLocation(
                                      GoRouterState.of(context).uri,
                                      '/view/${Uri.encodeComponent(blogs[index].id)}',
                                    ),
                                    extra: blogs[index],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final AuthorProfile profile;
  final void Function(String url) onOpenWebsite;
  final VoidCallback onOpenFollowers;
  final VoidCallback onOpenFollowing;

  const _ProfileHeader({
    required this.profile,
    required this.onOpenWebsite,
    required this.onOpenFollowers,
    required this.onOpenFollowing,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = authorDisplayName(l10n, profile.displayName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NoWaveAvatar(name: name, imageUrl: profile.avatarUrl),
            const SizedBox(width: NoWaveSpacing.medium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      name,
                      style: NoWaveTypography.title(context, size: 32),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.followerStats(
                      profile.followerCount,
                      formatNumber(
                        Localizations.localeOf(context),
                        profile.followerCount,
                      ),
                      formatNumber(
                        Localizations.localeOf(context),
                        profile.followingCount,
                      ),
                    ),
                    style: NoWaveTypography.meta(context),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: NoWaveSpacing.xs),
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: onOpenFollowers,
              child: Text(l10n.viewFollowers),
            ),
            TextButton(
              onPressed: onOpenFollowing,
              child: Text(l10n.viewFollowing),
            ),
          ],
        ),
        if (profile.bio.trim().isNotEmpty) ...[
          const SizedBox(height: NoWaveSpacing.medium),
          Text(profile.bio, style: const TextStyle(height: 1.5)),
        ],
        if (profile.websiteUrl.trim().isNotEmpty) ...[
          const SizedBox(height: NoWaveSpacing.small),
          TextButton(
            onPressed: () => onOpenWebsite(profile.websiteUrl),
            child: Text(profile.websiteUrl),
          ),
        ],
      ],
    );
  }
}

class _FollowButton extends StatelessWidget {
  final AuthorLoaded loaded;
  final bool isSelf;
  final VoidCallback onTap;

  const _FollowButton({
    required this.loaded,
    required this.isSelf,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isSelf) {
      // No Align: a wrapping parent lays this out by its own width, and an
      // Align would claim the whole line.
      return Chip(label: Text(context.l10n.thisIsYou));
    }

    final following = loaded.profile.isFollowing;
    final inFlight = loaded.followInFlight;

    return Semantics(
      toggled: following,
      child: NoWaveButton(
        label: following
            ? context.l10n.followingButton
            : context.l10n.followButton,
        icon: following ? Icons.check : Icons.person_add_alt_1,
        // Following is the resting state, so unfollow reads as secondary;
        // the action the page is asking for - follow - is the primary one.
        variant: following
            ? NoWaveButtonVariant.secondary
            : NoWaveButtonVariant.primary,
        isLoading: inFlight,
        onPressed: inFlight ? null : onTap,
      ),
    );
  }
}

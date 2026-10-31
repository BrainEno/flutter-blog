import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/common/widgets/no_wave_section_heading.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:belog/features/user/domain/entities/author_profile.dart';
import 'package:belog/features/user/presentation/bloc/author/author_cubit.dart';
import 'package:belog/router/shell_branch_location.dart';
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
                padding: const EdgeInsets.all(16),
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
            padding: const EdgeInsets.all(16),
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
                      ),
                      const SizedBox(height: 16),
                      _FollowButton(
                        loaded: loaded,
                        isSelf: isSelf,
                        onTap: _onFollowTap,
                      ),
                      const SizedBox(height: 32),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      NoWaveSectionHeading(
                        title: context.l10n.authorArticlesTitle,
                      ),
                      const SizedBox(height: 16),
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
                              padding: const EdgeInsets.symmetric(vertical: 24),
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
                              padding: const EdgeInsets.symmetric(vertical: 24),
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

  const _ProfileHeader({required this.profile, required this.onOpenWebsite});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = profile.displayName.trim().isNotEmpty
        ? profile.displayName
        : l10n.anonymousAuthor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NoWaveAvatar(name: name, imageUrl: profile.avatarUrl),
            const SizedBox(width: 16),
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
        if (profile.bio.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(profile.bio, style: const TextStyle(height: 1.5)),
        ],
        if (profile.websiteUrl.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
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
      return Align(
        alignment: Alignment.centerLeft,
        child: Chip(label: Text(context.l10n.thisIsYou)),
      );
    }

    final following = loaded.profile.isFollowing;
    final inFlight = loaded.followInFlight;
    const shape = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
    final progress = SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        semanticsLabel: context.l10n.loading,
      ),
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        toggled: following,
        child: following
            ? OutlinedButton.icon(
                style: OutlinedButton.styleFrom(shape: shape),
                onPressed: inFlight ? null : onTap,
                icon: inFlight ? progress : const Icon(Icons.check, size: 16),
                label: Text(context.l10n.followingButton),
              )
            : FilledButton.icon(
                style: FilledButton.styleFrom(shape: shape),
                onPressed: inFlight ? null : onTap,
                icon: inFlight
                    ? progress
                    : const Icon(Icons.person_add_alt_1, size: 16),
                label: Text(context.l10n.followButton),
              ),
      ),
    );
  }
}

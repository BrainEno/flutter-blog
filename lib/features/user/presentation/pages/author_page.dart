import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_event.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_state.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:belog/features/user/domain/entities/author_profile.dart';
import 'package:belog/features/user/presentation/bloc/author/author_cubit.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
    context.read<BlogByBloc>().add(
      GetBlogByPosterEvent(userId: widget.userId),
    );
  }

  void _requestLogin() {
    final currentLocation = GoRouterState.of(context).uri.toString();
    context.push('/login?redirect=${Uri.encodeComponent(currentLocation)}');
  }

  Future<void> _openWebsite(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      if (mounted) showSnackBar(context, '链接无效');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      showSnackBar(context, '无法打开链接');
    }
  }

  void _onFollowTap(AuthorLoaded state) {
    final appUserState = context.read<AppUserCubit>().state;
    if (appUserState is! AppUserLoggedIn) {
      showSnackBar(context, '请先登录账户');
      _requestLogin();
      return;
    }
    context.read<AuthorCubit>().toggleFollow();
  }

  @override
  Widget build(BuildContext context) {
    final appUserState = context.watch<AppUserCubit>().state;
    final viewerId =
        appUserState is AppUserLoggedIn ? appUserState.user.id : null;

    return Scaffold(
      appBar: AppBar(title: const Text('作者')),
      body: BlocConsumer<AuthorCubit, AuthorState>(
        listenWhen: (previous, current) =>
            current is AuthorLoaded &&
            previous is AuthorLoaded &&
            current.followError != previous.followError &&
            current.followError.isNotEmpty,
        listener: (context, state) {
          showSnackBar(context, state.followError);
        },
        builder: (context, state) {
          if (state is AuthorLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is AuthorFailure) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.error.isNotEmpty ? state.error : '作者不存在或已注销',
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.read<AuthorCubit>().load(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          final loaded = state as AuthorLoaded;
          final profile = loaded.profile;
          final isSelf = viewerId != null && viewerId == profile.userId;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              _ProfileHeader(profile: profile, onOpenWebsite: _openWebsite),
              const SizedBox(height: 16),
              _FollowButton(
                loaded: loaded,
                isSelf: isSelf,
                onTap: () => _onFollowTap(loaded),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'TA 的文章',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              BlocBuilder<BlogByBloc, BlogByState>(
                builder: (context, articleState) {
                  if (articleState is GetBlogsByUserLoading ||
                      articleState is BlogByInitial) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (articleState is GetBlogsByUserFailure) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        articleState.error.isNotEmpty
                            ? articleState.error
                            : '文章加载失败',
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final blogs = articleState is GetBlogsByUserSuccess
                      ? articleState.blogs
                      : const [];
                  if (blogs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '还没有发布文章',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: blogs
                        .map((blog) => BlogCard(blog: blog))
                        .toList(),
                  );
                },
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundImage: profile.avatarUrl.isNotEmpty
                    ? CachedNetworkImageProvider(profile.avatarUrl)
                    : null,
                child: profile.avatarUrl.isEmpty
                    ? const Icon(Icons.person, size: 32)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName.isNotEmpty
                          ? profile.displayName
                          : '匿名作者',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '粉丝 ${profile.followerCount}'
                      ' · 关注 ${profile.followingCount}',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(profile.bio, style: const TextStyle(height: 1.4)),
          ],
          if (profile.websiteUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpenWebsite(profile.websiteUrl),
              child: Text(
                profile.websiteUrl,
                style: const TextStyle(
                  color: AppPalette.gradient1,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
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
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Chip(label: Text('这是你'), visualDensity: VisualDensity.compact),
        ),
      );
    }

    final following = loaded.profile.isFollowing;
    final inFlight = loaded.followInFlight;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Align(
        alignment: Alignment.centerLeft,
        child: following
            ? OutlinedButton.icon(
                onPressed: inFlight ? null : onTap,
                icon: inFlight
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 16),
                label: const Text('已关注'),
              )
            : FilledButton.icon(
                onPressed: inFlight ? null : onTap,
                icon: inFlight
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1, size: 16),
                label: const Text('关注'),
              ),
      ),
    );
  }
}

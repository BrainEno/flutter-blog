import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_refresh.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_masthead.dart';
import 'package:belog/core/common/widgets/no_wave_section_heading.dart';
import 'package:belog/core/design/components/no_wave_column.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_item.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_skeleton.dart';
import 'package:belog/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:belog/router/route_paths.dart';

class SavedBlogsPage extends StatefulWidget {
  const SavedBlogsPage({super.key});

  @override
  State<SavedBlogsPage> createState() => _SavedBlogsPageState();
}

class _SavedBlogsPageState extends State<SavedBlogsPage>
    with WidgetsBindingObserver, RouteAware {
  List<Blog> _lastBlogs = []; // Store the last successful blog list

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchSavedBlogs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      savedRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    savedRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchSavedBlogs();
    }
  }

  @override
  void didPopNext() {
    // The viewer above this page owns its own like state; refresh so likes
    // toggled there are reflected in the saved list.
    _fetchSavedBlogs();
  }

  void _fetchSavedBlogs() {
    final appUserState = context.read<AppUserCubit>().state;
    if (appUserState is AppUserLoggedIn) {
      context.read<BlogLikedBloc>().add(
        UserLikedBlogs(userId: appUserState.user.id),
      );
    }
  }

  Future<void> _refresh() async {
    final likes = context.read<BlogLikedBloc>();
    _fetchSavedBlogs();
    await likes.stream.firstWhere(
      (state) =>
          state is UserLikedBlogsSuccess || state is UserLikedBlogsFailure,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // One gutter for the masthead, the heading and the grid, so all three
    // start on the same edge as every other tab.
    final gutter = NoWaveColumn.inset(MediaQuery.sizeOf(context).width);
    return Scaffold(
      appBar: AppBar(titleSpacing: gutter, title: const NoWaveMasthead()),
      body: BlocConsumer<BlogLikedBloc, BlogLikedState>(
        listener: (context, state) {
          if (state is UserLikedBlogsFailure) {
            showSnackBar(context, localizedFailure(l10n, state.failure));
          }
        },
        builder: (context, state) {
          if (state is UserLikedBlogsSuccess) {
            _lastBlogs = state.blogs;
          }
          final blogs = state is UserLikedBlogsSuccess
              ? state.blogs
              : _lastBlogs;
          // A refresh in the background keeps the list it has; only a first
          // read shows the skeleton.
          final Widget body;
          if (state is UserLikedBlogsFailure && blogs.isEmpty) {
            body = SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.all(gutter),
                child: NoWaveStatus(
                  message: l10n.loadErrorPrefix(
                    localizedFailure(l10n, state.failure),
                  ),
                  actionLabel: l10n.actionRetry,
                  onAction: _fetchSavedBlogs,
                ),
              ),
            );
          } else if (blogs.isEmpty && state is! UserLikedBlogsSuccess) {
            body = SliverFillRemaining(
              child: BlogGridSkeleton(
                padding: EdgeInsets.symmetric(horizontal: gutter),
              ),
            );
          } else if (blogs.isEmpty) {
            body = SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  NoWaveSizes.emptyStateOffset,
                  gutter,
                  NoWaveSpacing.section,
                ),
                child: Text(
                  l10n.savedEmpty,
                  textAlign: TextAlign.center,
                  style:
                      NoWaveTypography.title(
                        context,
                        size: NoWaveTypeScale.sectionTitle,
                      ).copyWith(
                        fontWeight: FontWeight.w400,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            );
          } else {
            body = SliverPadding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                0,
                gutter,
                NoWaveSpacing.section,
              ),
              sliver: SliverGrid.builder(
                gridDelegate: blogGridDelegate(context, gutter: gutter),
                itemCount: blogs.length,
                itemBuilder: (context, index) {
                  final blog = blogs[index];
                  return BlogGridItem(
                    blog: blog,
                    onTap: () {
                      context.push(RoutePaths.savedView(blog.id), extra: blog);
                    },
                  );
                },
              ),
            );
          }
          return NoWaveRefresh(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      NoWaveSpacing.large,
                      gutter,
                      NoWaveSpacing.large,
                    ),
                    child: NoWaveSectionHeading(
                      title: l10n.tabSaved,
                      companion: l10n.savedHeadingCompanion,
                      eyebrow: l10n.savedEyebrow,
                    ),
                  ),
                ),
                body,
              ],
            ),
          );
        },
      ),
    );
  }
}

import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/presentation/blocs/related_articles/related_articles_cubit.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Related-articles rider under a viewed article (issue #19).
///
/// A best-effort reading suggestion: the section stays hidden while
/// loading or empty and after a failure — the reader came for the
/// article. The Cubit is created and disposed with this section.
class RelatedArticlesSection extends StatelessWidget {
  final GetRelatedArticles getRelatedArticles;
  final String slug;

  const RelatedArticlesSection({
    super.key,
    required this.getRelatedArticles,
    required this.slug,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (_) => RelatedArticlesCubit(
            getRelatedArticles: getRelatedArticles,
            slug: slug,
          ),
      child: BlocBuilder<RelatedArticlesCubit, RelatedArticlesState>(
        builder: (context, state) {
          if (state is! RelatedArticlesLoaded || state.blogs.isEmpty) {
            return const SizedBox.shrink();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 32),
              const Text(
                '相关阅读',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...state.blogs.map((blog) => BlogCard(blog: blog)),
            ],
          );
        },
      ),
    );
  }
}

import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
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
  final ValueChanged<Blog> onOpenArticle;

  const RelatedArticlesSection({
    super.key,
    required this.getRelatedArticles,
    required this.slug,
    required this.onOpenArticle,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => RelatedArticlesCubit(
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
              Text(
                context.l10n.relatedReading,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              for (var index = 0; index < state.blogs.length; index++)
                BlogCard(
                  blog: state.blogs[index],
                  index: index + 1,
                  onTap: () => onOpenArticle(state.blogs[index]),
                ),
            ],
          );
        },
      ),
    );
  }
}

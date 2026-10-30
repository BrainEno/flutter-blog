import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class RelatedArticlesState {
  const RelatedArticlesState();
}

final class RelatedArticlesInitial extends RelatedArticlesState {
  const RelatedArticlesInitial();
}

final class RelatedArticlesLoading extends RelatedArticlesState {
  const RelatedArticlesLoading();
}

final class RelatedArticlesLoaded extends RelatedArticlesState {
  final List<Blog> blogs;
  const RelatedArticlesLoaded(this.blogs);
}

final class RelatedArticlesFailure extends RelatedArticlesState {
  const RelatedArticlesFailure();
}

/// Page-scoped Cubit backing the viewer's related-articles rider
/// (issue #19).
///
/// Related articles are a best-effort reading suggestion: the section is
/// simply hidden on failure — the reader came for the article, not for the
/// rider — so the failure state carries no message.
class RelatedArticlesCubit extends Cubit<RelatedArticlesState> {
  final GetRelatedArticles _getRelatedArticles;
  final String slug;

  RelatedArticlesCubit({
    required GetRelatedArticles getRelatedArticles,
    required this.slug,
  }) : _getRelatedArticles = getRelatedArticles,
       super(const RelatedArticlesInitial()) {
    load();
  }

  Future<void> load() async {
    emit(const RelatedArticlesLoading());
    final res = await _getRelatedArticles(slug);
    res.fold(
      (_) => emit(const RelatedArticlesFailure()),
      (blogs) => emit(RelatedArticlesLoaded(blogs)),
    );
  }
}

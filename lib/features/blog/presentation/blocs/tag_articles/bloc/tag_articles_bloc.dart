import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/tag_ref.dart';
import 'package:belog/features/blog/domain/tag_paging.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_tag.dart';
import 'package:belog/features/blog/domain/usecase/resolve_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'tag_articles_event.dart';
part 'tag_articles_state.dart';

/// Browses one tag: resolve it once, then walk its article list by offset.
///
/// The tag is addressed by the **name** an article stores (that is what the UI
/// has), and resolved to its server slug here. Both "the tag does not exist"
/// and "the tag exists but has no articles" are first-class states, because
/// collapsing them into an empty list is how a browsing page ends up showing
/// unrelated content (#106).
class TagArticlesBloc extends Bloc<TagArticlesEvent, TagArticlesState> {
  final ResolveTag _resolveTag;
  final GetArticlesByTag _getArticlesByTag;

  /// The tag the page is about, in the wording the article stored.
  String? _tagName;

  /// The resolved taxonomy, reused by refresh and load-more.
  TagRef? _tag;

  TagArticlesBloc({
    required ResolveTag resolveTag,
    required GetArticlesByTag getArticlesByTag,
  }) : _resolveTag = resolveTag,
       _getArticlesByTag = getArticlesByTag,
       super(TagArticlesInitial()) {
    on<TagArticlesRequested>(_onRequested);
    on<TagArticlesRefreshed>(_onRefreshed);
    on<TagArticlesMoreRequested>(_onMoreRequested);
  }

  Future<void> _onRequested(
    TagArticlesRequested event,
    Emitter<TagArticlesState> emit,
  ) async {
    final name = event.tag.trim();
    if (name.isEmpty) {
      emit(TagArticlesUnknown(tag: event.tag));
      return;
    }
    _tagName = name;
    _tag = null;
    await _loadFirstPage(emit);
  }

  Future<void> _onRefreshed(
    TagArticlesRefreshed event,
    Emitter<TagArticlesState> emit,
  ) async {
    if (_tagName == null) return;
    await _loadFirstPage(emit);
  }

  Future<void> _loadFirstPage(Emitter<TagArticlesState> emit) async {
    final name = _tagName;
    if (name == null) return;
    emit(TagArticlesLoading());

    // Reuse the resolved taxonomy on refresh; a tag's slug never changes for
    // a given name, and re-resolving would cost a round trip per pull.
    var tag = _tag;
    if (tag == null) {
      final resolved = await _resolveTag(ResolveTagParams(name: name));
      TagRef? found;
      Failure? resolveFailure;
      resolved.fold((failure) => resolveFailure = failure, (value) {
        found = value;
      });
      final failure = resolveFailure;
      if (failure != null) {
        emit(TagArticlesFailure(failure: failure.forPresentation()));
        return;
      }
      final resolvedTag = found;
      if (resolvedTag == null) {
        emit(TagArticlesUnknown(tag: name));
        return;
      }
      tag = resolvedTag;
      _tag = resolvedTag;
    }

    final res = await _getArticlesByTag(
      TagArticlesParams(slug: tag.slug, offset: 0),
    );
    res.fold(
      (failure) => emit(_unknownOrFailure(failure)),
      (articles) => emit(
        TagArticlesSuccess(
          tag: tag!,
          articles: articles,
          hasMore: articles.length >= kTagPageSize,
        ),
      ),
    );
  }

  Future<void> _onMoreRequested(
    TagArticlesMoreRequested event,
    Emitter<TagArticlesState> emit,
  ) async {
    final current = state;
    if (current is! TagArticlesSuccess) return;
    if (!current.hasMore || current.loadingMore) return;

    emit(current.copyWith(loadingMore: true, loadMoreFailure: null));
    final res = await _getArticlesByTag(
      TagArticlesParams(
        slug: current.tag.slug,
        offset: current.articles.length,
      ),
    );
    res.fold(
      (failure) => emit(
        current.copyWith(
          loadingMore: false,
          loadMoreFailure: failure.forPresentation(),
        ),
      ),
      (more) {
        // Offset paging can repeat a row when something is published while
        // the reader scrolls; ids are stable, so drop what is already shown.
        final seen = current.articles.map((blog) => blog.id).toSet();
        final added = more.where((blog) => seen.add(blog.id)).toList();
        emit(
          TagArticlesSuccess(
            tag: current.tag,
            articles: [...current.articles, ...added],
            hasMore: more.length >= kTagPageSize,
          ),
        );
      },
    );
  }

  /// A tag that vanished between resolving and reading is the same state as
  /// one that never existed: say so rather than showing an empty list.
  TagArticlesState _unknownOrFailure(Failure failure) {
    final name = _tagName ?? '';
    if (failure.code == 'tag.notFound') return TagArticlesUnknown(tag: name);
    return TagArticlesFailure(failure: failure.forPresentation());
  }
}

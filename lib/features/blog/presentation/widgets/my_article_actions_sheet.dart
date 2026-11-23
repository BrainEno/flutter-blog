import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:flutter/material.dart';

/// What the author picked for one of their own articles.
enum MyArticleAction { edit, publish, unpublish, delete }

/// Why the app cannot change whether an article is public, or null when it
/// can.
enum MyArticleVisibilityBlock {
  /// The body holds something the app's editor cannot carry (a quote with an
  /// attribution, say): resending it could lose it, so only the web may.
  webOnly,

  /// The list row came without the revision a conditional write needs.
  refreshFirst,
}

/// The actions for one article in "my articles": edit, publish or take back
/// to a draft, delete.
///
/// It only reports the choice. The page asks for confirmation where readers
/// would lose something and performs the write.
class MyArticleActionsSheet extends StatelessWidget {
  const MyArticleActionsSheet({
    super.key,
    required this.blog,
    this.visibilityBlock,
  });

  final Blog blog;

  /// Non-null greys out the publish / draft entry and says why.
  final MyArticleVisibilityBlock? visibilityBlock;

  static Future<MyArticleAction?> show(
    BuildContext context, {
    required Blog blog,
    MyArticleVisibilityBlock? visibilityBlock,
  }) {
    return showModalBottomSheet<MyArticleAction>(
      context: context,
      useSafeArea: true,
      builder: (_) =>
          MyArticleActionsSheet(blog: blog, visibilityBlock: visibilityBlock),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = Theme.of(context).colorScheme.error;
    final visibilityNote = switch (visibilityBlock) {
      MyArticleVisibilityBlock.webOnly => l10n.myArticleVisibilityWebOnly,
      MyArticleVisibilityBlock.refreshFirst =>
        l10n.myArticleVisibilityRefreshFirst,
      null => null,
    };
    void choose(MyArticleAction action) => Navigator.of(context).pop(action);
    // Scrolls rather than overflows at large text sizes on a small phone.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: NoWaveSpacing.small),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NoWaveSpacing.large,
              NoWaveSpacing.large,
              NoWaveSpacing.large,
              NoWaveSpacing.small,
            ),
            child: Text(
              blog.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            key: const Key('my-article-action-edit'),
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.myArticleActionEdit),
            onTap: () => choose(MyArticleAction.edit),
          ),
          ListTile(
            key: const Key('my-article-action-visibility'),
            enabled: visibilityNote == null,
            leading: Icon(
              blog.isDraft ? Icons.public : Icons.visibility_off_outlined,
            ),
            title: Text(
              blog.isDraft
                  ? l10n.myArticleActionPublish
                  : l10n.editorUnpublishToDraft,
            ),
            subtitle: visibilityNote == null ? null : Text(visibilityNote),
            onTap: () => choose(
              blog.isDraft
                  ? MyArticleAction.publish
                  : MyArticleAction.unpublish,
            ),
          ),
          ListTile(
            key: const Key('my-article-action-delete'),
            leading: Icon(Icons.delete_outline, color: error),
            title: Text(l10n.deleteArticleTitle),
            subtitle: Text(l10n.myArticleActionDeleteNote),
            textColor: error,
            onTap: () => choose(MyArticleAction.delete),
          ),
        ],
      ),
    );
  }
}

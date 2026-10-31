import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/presentation/widgets/article_cover.dart';
import 'package:belog/features/blog/presentation/widgets/article_reader_header.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_item.dart';
import 'package:belog/features/blog/presentation/widgets/related_articles_section.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class MockGetRelatedArticles extends Mock implements GetRelatedArticles {}

// Inspect the actual widget builders without mounting the network image or
// issuing a request in a widget test.
class InspectableArticleCover extends ArticleCover {
  const InspectableArticleCover({
    required super.title,
    required super.imageUrl,
  });

  Widget inspect(BuildContext context) => super.build(context);
}

Blog article({String imageUrl = ''}) => Blog(
  id: 'an-article',
  title: 'A long article title about a city and its changing seasons',
  content: 'An article excerpt that can wrap over several lines.',
  posterId: 'author',
  posterName: 'A writer with a long name',
  imageUrl: imageUrl,
  tags: const ['诗歌', '自定义'],
  updatedAt: DateTime.utc(2026, 10, 31),
);

Widget testApp(
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  theme: AppTheme.lightThemeMode,
  darkTheme: AppTheme.darkThemeMode,
  themeMode: themeMode,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: child,
);

void setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  test('themes expose the no-wave paper, ink and accessible accent pairs', () {
    expect(AppTheme.lightThemeMode.scaffoldBackgroundColor, AppPalette.paper);
    expect(AppTheme.darkThemeMode.scaffoldBackgroundColor, AppPalette.ink);
    expect(AppTheme.lightThemeMode.colorScheme.primary, AppPalette.oxblood);
    expect(AppTheme.darkThemeMode.colorScheme.primary, AppPalette.orange);
    expect(AppTheme.darkThemeMode.colorScheme.onPrimary, AppPalette.ink);
  });

  testWidgets(
    'article row delegates pointer and keyboard activation without a router',
    (tester) async {
      setViewport(tester, const Size(320, 900));
      final semantics = tester.ensureSemantics();
      try {
        var clicks = 0;
        final blog = article();
        await tester.pumpWidget(
          testApp(
            Scaffold(
              body: SingleChildScrollView(
                child: BlogCard(
                  blog: blog,
                  featured: true,
                  index: 1,
                  onTap: () => clicks++,
                ),
              ),
            ),
            textScale: 2,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Poetry'), findsOneWidget);
        expect(find.text('自定义'), findsOneWidget);
        await tester.ensureVisible(find.byType(ArticleCover));
        expect(
          find.bySemanticsLabel(
            RegExp(RegExp.escape('Cover of ${blog.title}')),
          ),
          findsWidgets,
        );
        await tester.ensureVisible(find.text(blog.title));
        await tester.tap(find.text(blog.title));
        expect(clicks, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(clicks, 2);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'cover uses the unmodified HTTP URL and an accessible local fallback',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        const title = 'My article';
        await tester.pumpWidget(
          testApp(
            const Scaffold(
              body: ArticleCover(
                title: title,
                imageUrl: 'file:///not-a-network-cover.jpg',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.bySemanticsLabel('Cover of $title'), findsOneWidget);
        final fallback = tester.widget<Image>(find.byType(Image));
        expect(
          (fallback.image as AssetImage).assetName,
          'assets/images/no_wave_cover_fallback.jpg',
        );

        // Inspect the network builder without mounting it: no external request is
        // needed to exercise the exact error/placeholder fallback builders.
        const url = 'https://example.org/media/cover.webp?original=1';
        late CachedNetworkImage networkImage;
        late BuildContext coverContext;
        await tester.pumpWidget(
          testApp(
            Scaffold(
              body: Builder(
                builder: (context) {
                  coverContext = context;
                  final cover =
                      const InspectableArticleCover(
                            title: title,
                            imageUrl: url,
                          ).inspect(context)
                          as Semantics;
                  final excluded = cover.child! as ExcludeSemantics;
                  final ratio = excluded.child! as AspectRatio;
                  final background = ratio.child! as ColoredBox;
                  networkImage = background.child! as CachedNetworkImage;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        expect(networkImage.imageUrl, url);
        final error =
            networkImage.errorWidget!(coverContext, url, StateError('offline'))
                as Image;
        final loading = networkImage.placeholder!(coverContext, url) as Image;
        expect(
          (error.image as AssetImage).assetName,
          'assets/images/no_wave_cover_fallback.jpg',
        );
        expect(
          (loading.image as AssetImage).assetName,
          'assets/images/no_wave_cover_fallback.jpg',
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'grid and reader header fit large text in both themes and preserve actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        for (final size in [const Size(320, 900), const Size(800, 1000)]) {
          setViewport(tester, size);
          for (final mode in [ThemeMode.light, ThemeMode.dark]) {
            var opens = 0;
            var deletes = 0;
            final blog = article();
            await tester.pumpWidget(
              testApp(
                Scaffold(
                  body: Builder(
                    builder: (context) => GridView(
                      gridDelegate: blogGridDelegate(context),
                      children: [
                        BlogGridItem(
                          blog: blog,
                          onTap: () => opens++,
                          onLongPress: () => deletes++,
                        ),
                      ],
                    ),
                  ),
                ),
                locale: const Locale('zh'),
                themeMode: mode,
                textScale: 2,
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text(blog.title));
            await tester.tap(find.byTooltip('删除文章'));
            expect(opens, 1);
            expect(deletes, 1);
            expect(tester.takeException(), isNull);

            var authors = 0;
            await tester.pumpWidget(
              testApp(
                Scaffold(
                  body: SingleChildScrollView(
                    child: ArticleReaderHeader(
                      blog: blog,
                      onAuthorTap: () => authors++,
                    ),
                  ),
                ),
                themeMode: mode,
                textScale: 2,
              ),
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text(blog.posterName!));
            await tester.tap(find.text(blog.posterName!));
            expect(authors, 1);
            expect(tester.takeException(), isNull);
          }
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('related article selection is delegated to the parent', (
    tester,
  ) async {
    final blog = article();
    Blog? selected;
    final fetch = MockGetRelatedArticles();
    when(() => fetch('current')).thenAnswer((_) async => Right([blog]));
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: SingleChildScrollView(
            child: RelatedArticlesSection(
              getRelatedArticles: fetch,
              slug: 'current',
              onOpenArticle: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(blog.title));
    expect(selected, same(blog));
  });
}

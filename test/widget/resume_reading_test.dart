import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/presentation/pages/blog_viewer_page.dart';
import 'package:belog/features/blog/presentation/viewer/resume_reading_slip.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'router_test.dart' show Harness, sampleUser;

/// A history that keeps what it is told, so a test can see what the reader
/// wrote and seed where it last left off.
class _History implements ReadingHistoryStore {
  final recorded = <String>[];
  final progress = <String, double>{};
  final saved = <double>[];

  @override
  Future<void> record({required String userId, required Blog blog}) async {
    recorded.add(blog.id);
  }

  @override
  Future<List<ReadingHistoryEntry>> list({
    required String userId,
    int limit = 200,
  }) async => const [];

  @override
  Future<void> saveProgress({
    required String userId,
    required String blogId,
    required double progress,
  }) async {
    saved.add(progress);
    this.progress[blogId] = progress;
  }

  @override
  Future<double?> progressOf({
    required String userId,
    required String blogId,
  }) async => progress[blogId];

  @override
  Future<void> remove({required String userId, required String blogId}) async {}

  @override
  Future<void> clear({required String userId}) async {}
}

const _paragraph =
    '夜里的城市像一张没有写完的稿纸。路灯一盏一盏亮起来，把街道切成整齐的段落，'
    '而我们只是其中被反复修改的句子。';

BlogModel _longArticle(String id) => BlogModel(
  id: id,
  title: '没有写完的稿纸',
  content: [for (var i = 0; i < 40; i++) _paragraph].join('\n\n'),
  posterId: 'author',
  imageUrl: '',
  tags: const ['散文'],
  updatedAt: DateTime.utc(2025),
);

ScrollPosition _articleScroll(WidgetTester tester) {
  final scrollable = find
      .descendant(
        of: find.descendant(
          of: find.byType(BlogViewerPage),
          matching: find.byType(CustomScrollView),
        ),
        matching: find.byType(Scrollable),
      )
      .first;
  return tester.state<ScrollableState>(scrollable).position;
}

void main() {
  setUp(() => GetIt.instance.reset());

  Future<(Harness, _History)> open(
    WidgetTester tester, {
    String location = '/',
    double? leftAt,
  }) async {
    final harness = Harness()..buildRouter(initialLocation: location);
    addTearDown(harness.dispose);
    final history = _History();
    if (leftAt != null) history.progress['long'] = leftAt;
    GetIt.instance.registerSingleton<ReadingHistoryStore>(history);
    final article = _longArticle('long');
    when(
      () => harness.remote.getAllBlogs(page: 1),
    ).thenAnswer((_) async => [article]);
    when(
      () => harness.remote.getBlogById(any()),
    ).thenAnswer((_) async => article);
    when(
      () => harness.remote.isBlogLikedByUser(any(), any()),
    ).thenAnswer((_) async => false);
    harness.appUserCubit.updateUser(sampleUser());
    await harness.pump(tester);
    await tester.pumpAndSettle();
    return (harness, history);
  }

  testWidgets('an article opened from a card is written to the history', (
    tester,
  ) async {
    final (_, history) = await open(tester);

    await tester.ensureVisible(find.byType(BlogCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BlogCard));
    await tester.pumpAndSettle();

    expect(find.byType(BlogViewerPage), findsOneWidget);
    expect(history.recorded, ['long']);
  });

  testWidgets('a scroll that comes to rest remembers how far the reader got', (
    tester,
  ) async {
    final (_, history) = await open(tester, location: '/view/long');

    await tester.drag(find.byType(BlogViewerPage), const Offset(0, -1500));
    await tester.pumpAndSettle();

    expect(history.saved, isNotEmpty);
    expect(history.saved.last, greaterThan(0));
    expect(history.saved.last, lessThan(1));
    // Nothing to pick up on a first read.
    expect(find.byType(ResumeReadingSlip), findsNothing);
  });

  testWidgets('reopening offers to pick up where the reader left off', (
    tester,
  ) async {
    final (_, history) = await open(
      tester,
      location: '/view/long',
      leftAt: 0.5,
    );

    expect(find.byType(ResumeReadingSlip), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);
    expect(_articleScroll(tester).pixels, 0);

    await tester.tap(find.byType(ResumeReadingSlip));
    await tester.pumpAndSettle();

    expect(_articleScroll(tester).pixels, greaterThan(0));
    expect(find.byType(ResumeReadingSlip), findsNothing);
    // Arriving where it already was is not a new position to write.
    expect(history.saved.where((at) => (at - 0.5).abs() > 0.02), isEmpty);
  });

  testWidgets('the offer leaves once the reader scrolls past the place', (
    tester,
  ) async {
    await open(tester, location: '/view/long', leftAt: 0.1);
    expect(find.byType(ResumeReadingSlip), findsOneWidget);

    await tester.drag(find.byType(BlogViewerPage), const Offset(0, -3000));
    await tester.pumpAndSettle();

    expect(find.byType(ResumeReadingSlip), findsNothing);
  });

  testWidgets('an article read to the end makes no offer', (tester) async {
    await open(tester, location: '/view/long', leftAt: 0.99);

    expect(find.byType(ResumeReadingSlip), findsNothing);
  });
}

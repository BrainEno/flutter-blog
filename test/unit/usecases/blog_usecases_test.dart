import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/domain/usecase/toggle_like_blog.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';

class MockBlogRepository extends Mock implements BlogRepository {}

void main() {
  group('GetAllBlogs UseCase', () {
    late MockBlogRepository mockRepository;
    late GetAllBlogs useCase;

    setUp(() {
      mockRepository = MockBlogRepository();
      useCase = GetAllBlogs(mockRepository);
    });

    test('should return list of blogs on success', () async {
      final blogs = [
        Blog(
          iid: 1,
          id: 'blog_1',
          title: 'Blog 1',
          content: 'Content 1',
          posterId: 'user_1',
          imageUrl: 'https://example.com/1.jpg',
          tags: ['tag1'],
          updatedAt: DateTime(2024, 1, 1),
        ),
        Blog(
          iid: 2,
          id: 'blog_2',
          title: 'Blog 2',
          content: 'Content 2',
          posterId: 'user_2',
          imageUrl: 'https://example.com/2.jpg',
          tags: ['tag2'],
          updatedAt: DateTime(2024, 1, 2),
        ),
      ];

      when(() => mockRepository.getAllBlogs(page: 1))
          .thenAnswer((_) async => Right(blogs));

      final result = await useCase(GetAllBlogsParams(page: 1));

      expect(result, Right(blogs));
      verify(() => mockRepository.getAllBlogs(page: 1)).called(1);
    });

    test('should return Failure on repository error', () async {
      when(() => mockRepository.getAllBlogs(page: 1))
          .thenAnswer((_) async => Left(Failure('Network error')));

      final result = await useCase(GetAllBlogsParams(page: 1));

      result.fold(
        (failure) => expect(failure.message, 'Network error'),
        (_) => fail('Expected failure'),
      );
      verify(() => mockRepository.getAllBlogs(page: 1)).called(1);
    });
  });

  group('ToggleLikeBlog UseCase', () {
    late MockBlogRepository mockRepository;
    late ToggleLikeBlog useCase;

    setUp(() {
      mockRepository = MockBlogRepository();
      useCase = ToggleLikeBlog(mockRepository);
    });

    test('should return true when toggle succeeds', () async {
      when(() => mockRepository.toggleLikeBlog('user_1', 'blog_1'))
          .thenAnswer((_) async => const Right(true));

      final result = await useCase(
        ToggleLikeParams(userId: 'user_1', blogId: 'blog_1'),
      );

      result.fold(
        (_) => fail('Expected success'),
        (value) => expect(value, true),
      );
      verify(() => mockRepository.toggleLikeBlog('user_1', 'blog_1')).called(1);
    });

    test('should return Failure on repository error', () async {
      when(() => mockRepository.toggleLikeBlog('user_1', 'blog_1'))
          .thenAnswer((_) async => Left(Failure('Toggle failed')));

      final result = await useCase(
        ToggleLikeParams(userId: 'user_1', blogId: 'blog_1'),
      );

      result.fold(
        (failure) => expect(failure.message, 'Toggle failed'),
        (_) => fail('Expected failure'),
      );
      verify(() => mockRepository.toggleLikeBlog('user_1', 'blog_1')).called(1);
    });
  });
}

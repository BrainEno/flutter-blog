import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserModel.fromNowaveProfile', () {
    test('maps the no-wave profile fields onto the app user', () {
      final model = UserModel.fromNowaveProfile(<String, dynamic>{
        'userId': 'u1',
        'displayName': '名字',
        'bio': '',
        'avatarUrl': 'https://api.example.invalid/api/v1/media/a',
        'websiteUrl': 'https://example.invalid',
        'locale': 'zh-CN',
        'updatedAt': '2024-01-01T00:00:00.000Z',
      }, email: 'user@example.invalid');

      expect(model.id, 'u1');
      expect(model.name, '名字');
      expect(model.avatarUrl, 'https://api.example.invalid/api/v1/media/a');
      expect(model.website, 'https://example.invalid');
      expect(model.email, 'user@example.invalid');
      expect(model.updatedAt, DateTime.utc(2024, 1, 1));
    });

    test('the profile carries no e-mail: the shown address comes from the '
        'locally cached sign-in e-mail', () {
      final model = UserModel.fromNowaveProfile(<String, dynamic>{
        'userId': 'u1',
        'displayName': '名字',
        'updatedAt': '2024-01-01T00:00:00.000Z',
      }, email: 'cached@example.invalid');

      expect(model.email, 'cached@example.invalid');
    });

    test('missing optional fields default instead of throwing', () {
      final model = UserModel.fromNowaveProfile(<String, dynamic>{
        'userId': 'u1',
        'displayName': '名字',
      }, email: '');

      expect(model.avatarUrl, '');
      expect(model.website, '');
      expect(model.updatedAt, isNotNull);
    });
  });
}

import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toProfileUpdateJson', () {
    final model = UserModel(
      id: 'u1',
      email: 'original@example.invalid',
      name: '名字',
      avatarUrl: 'https://example.invalid/a.png',
      website: 'https://example.invalid',
      updatedAt: DateTime.utc(2024, 1, 1),
    );

    test('contains the editable display columns', () {
      final json = model.toProfileUpdateJson();
      expect(json['name'], '名字');
      expect(json['avatar_url'], 'https://example.invalid/a.png');
      expect(json['website'], 'https://example.invalid');
      expect(json['updated_at'], '2024-01-01T00:00:00.000Z');
    });

    test('never contains the e-mail column: the auth address only changes '
        'through Supabase Auth (changeEmail + confirmation), never a direct '
        'profiles write', () {
      final json = model.toProfileUpdateJson();
      expect(json.containsKey('email'), isFalse);
      expect(json.containsKey('id'), isFalse);
    });
  });
}

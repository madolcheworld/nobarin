import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/data/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthRepository Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saveProfile saves profile locally and getCachedProfile retrieves it', () async {
      final repository = AuthRepository();
      final profile = await repository.saveProfile(
        username: 'TestUser',
        avatarUrl: '🦊',
      );

      expect(profile.username, 'TestUser');
      expect(profile.avatarUrl, '🦊');
      expect(profile.id, isNotEmpty);

      final cached = await repository.getCachedProfile();
      expect(cached, isNotNull);
      expect(cached?.username, 'TestUser');
      expect(cached?.avatarUrl, '🦊');
      expect(cached?.id, profile.id);
    });

    test('clearSession removes cached profile', () async {
      final repository = AuthRepository();
      await repository.saveProfile(
        username: 'UserToRemove',
        avatarUrl: '🐼',
      );

      var cached = await repository.getCachedProfile();
      expect(cached, isNotNull);

      await repository.clearSession();
      cached = await repository.getCachedProfile();
      expect(cached, isNull);
    });

    test('deleteAccount removes cached profile and data', () async {
      final repository = AuthRepository();
      await repository.saveProfile(
        username: 'UserToDelete',
        avatarUrl: '⚡',
      );

      var cached = await repository.getCachedProfile();
      expect(cached, isNotNull);

      await repository.deleteAccount();
      cached = await repository.getCachedProfile();
      expect(cached, isNull);
    });
  });
}

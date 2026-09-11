import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_party/features/lobby/data/google_drive_auth_service.dart';
import 'package:watch_party/features/lobby/data/models/google_drive_account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoogleDriveAccount Model Tests', () {
    test('serializes and deserializes correctly', () {
      final account = GoogleDriveAccount(
        id: 'acc_12345',
        email: 'tester@example.com',
        displayName: 'Test User',
        photoUrl: 'https://example.com/avatar.png',
        accessToken: 'token_abc_123',
        isMock: false,
      );

      final jsonStr = account.toJson();
      final restored = GoogleDriveAccount.fromJson(jsonStr);

      expect(restored.id, 'acc_12345');
      expect(restored.email, 'tester@example.com');
      expect(restored.displayName, 'Test User');
      expect(restored.photoUrl, 'https://example.com/avatar.png');
      expect(restored.accessToken, 'token_abc_123');
      expect(restored.isMock, isFalse);
    });

    test('mockDemo creates valid demo account', () {
      final demo = GoogleDriveAccount.mockDemo(
        name: 'Demo Drive User',
        email: 'demo@watchparty.app',
      );

      expect(demo.id, 'mock_gdrive_user_99');
      expect(demo.displayName, 'Demo Drive User');
      expect(demo.email, 'demo@watchparty.app');
      expect(demo.isMock, isTrue);
      expect(demo.accessToken, isNotEmpty);
    });

    test('copyWith updates specific fields properly', () {
      final original = GoogleDriveAccount.mockDemo();
      final updated = original.copyWith(
        displayName: 'Updated Name',
        accessToken: 'new_token',
      );

      expect(updated.displayName, 'Updated Name');
      expect(updated.accessToken, 'new_token');
      expect(updated.email, original.email);
    });
  });

  group('GoogleDriveAuthService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('demo sign-in flow updates state and persists account', () async {
      final authService = GoogleDriveAuthService();
      await authService.init();

      expect(authService.isSignedIn, isFalse);
      expect(authService.currentAccount, isNull);

      final account = await authService.signIn(forceMock: true);

      expect(account, isNotNull);
      expect(authService.isSignedIn, isTrue);
      expect(authService.currentAccount?.isMock, isTrue);

      final token = await authService.getValidAccessToken();
      expect(token, isNotNull);

      // Sign out
      await authService.signOut();
      expect(authService.isSignedIn, isFalse);
      expect(authService.currentAccount, isNull);
    });
  });
}

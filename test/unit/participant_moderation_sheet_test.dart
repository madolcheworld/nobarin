import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/room/controllers/room_controller.dart';
import 'package:nobarin/features/room/models/room_model.dart';
import 'package:nobarin/features/room/presentation/widgets/participant_moderation_sheet.dart';

void main() {
  group('ParticipantModerationSheet Widget Tests', () {
    final hostUser = const UserProfile(
      id: 'host-101',
      username: 'AliceHost',
      avatarUrl: '👑',
      isGuest: false,
    );

    final coHostUser = const UserProfile(
      id: 'cohost-202',
      username: 'BobCoHost',
      avatarUrl: '⭐',
      isGuest: false,
    );

    final viewerUser = const UserProfile(
      id: 'viewer-303',
      username: 'CharlieViewer',
      avatarUrl: '🐱',
      isGuest: true,
    );

    final testRoom = RoomModel(
      id: 'room-sheet-test',
      code: 'WP1122',
      title: 'Moderation Sheet Test Room',
      hostId: 'host-101',
      hostName: 'AliceHost',
      isPublic: true,
      controlMode: 'host_only',
      currentMediaType: 'direct_url',
      currentMediaUrl: '',
      currentState: 'paused',
      currentPosition: 0.0,
      livekitRoomName: 'room_WP1122',
      participantCount: 3,
    );

    testWidgets('renders Host badge for host participant', (tester) async {
      final controller = RoomController(
        initialRoom: testRoom,
        currentUser: hostUser,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParticipantModerationSheet(
              targetUser: hostUser,
              roomController: controller,
            ),
          ),
        ),
      );

      expect(find.text('AliceHost'), findsOneWidget);
      expect(find.text('👑 Host'), findsOneWidget);
      // Since it's self, moderation actions should not appear
      expect(find.text('Keluarkan dari Room'), findsNothing);

      controller.dispose();
    });

    testWidgets('renders Co-Host badge and demote option for Host viewing Co-Host', (tester) async {
      final controller = RoomController(
        initialRoom: testRoom,
        currentUser: hostUser,
      );

      // Make Bob a co-host
      controller.handleCoHostUpdated({
        'target_user_id': coHostUser.id,
        'is_co_host': true,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParticipantModerationSheet(
              targetUser: coHostUser,
              roomController: controller,
            ),
          ),
        ),
      );

      expect(find.text('BobCoHost'), findsOneWidget);
      expect(find.text('⭐ Co-Host'), findsOneWidget);
      expect(find.text('Cabut Peran Co-Host'), findsOneWidget);
      expect(find.text('Alihkan Peran Host'), findsOneWidget);
      expect(find.text('Matikan Mikrofon'), findsOneWidget);
      expect(find.text('Keluarkan dari Room'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('renders promote option and all actions for Host viewing regular Viewer', (tester) async {
      final controller = RoomController(
        initialRoom: testRoom,
        currentUser: hostUser,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParticipantModerationSheet(
              targetUser: viewerUser,
              roomController: controller,
            ),
          ),
        ),
      );

      expect(find.text('CharlieViewer'), findsOneWidget);
      expect(find.text('👤 Peserta'), findsOneWidget);
      expect(find.text('Jadikan Co-Host'), findsOneWidget);
      expect(find.text('Alihkan Peran Host'), findsOneWidget);
      expect(find.text('Matikan Mikrofon'), findsOneWidget);
      expect(find.text('Keluarkan dari Room'), findsOneWidget);

      // Tap Jadikan Co-Host
      await tester.tap(find.text('Jadikan Co-Host'));
      await tester.pumpAndSettle();

      expect(controller.isCoHost(viewerUser.id), isTrue);

      controller.dispose();
    });

    testWidgets('renders read-only view for Viewer viewing another Viewer', (tester) async {
      final controller = RoomController(
        initialRoom: testRoom,
        currentUser: const UserProfile(id: 'other-viewer', username: 'Other', isGuest: true),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParticipantModerationSheet(
              targetUser: viewerUser,
              roomController: controller,
            ),
          ),
        ),
      );

      expect(find.text('CharlieViewer'), findsOneWidget);
      expect(find.text('👤 Peserta'), findsOneWidget);
      // No moderation actions should appear
      expect(find.text('Jadikan Co-Host'), findsNothing);
      expect(find.text('Jadikan Host'), findsNothing);
      expect(find.text('Matikan Mikrofon'), findsNothing);
      expect(find.text('Keluarkan dari Room'), findsNothing);

      controller.dispose();
    });

    testWidgets('Co-Host can kick and mute Viewers, but cannot transfer host or manage co-hosts', (tester) async {
      final controller = RoomController(
        initialRoom: testRoom,
        currentUser: coHostUser,
      );
      controller.handleCoHostUpdated({
        'target_user_id': coHostUser.id,
        'is_co_host': true,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParticipantModerationSheet(
              targetUser: viewerUser,
              roomController: controller,
            ),
          ),
        ),
      );

      expect(find.text('Matikan Mikrofon'), findsOneWidget);
      expect(find.text('Keluarkan dari Room'), findsOneWidget);
      expect(find.text('Jadikan Co-Host'), findsNothing);
      expect(find.text('Jadikan Host'), findsNothing);

      controller.dispose();
    });

    testWidgets('shows disabled mute action when participant is already muted', (tester) async {
      final controller = RoomController(
        initialRoom: testRoom,
        currentUser: hostUser,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParticipantModerationSheet(
              targetUser: viewerUser,
              roomController: controller,
              isMuted: true,
            ),
          ),
        ),
      );

      expect(find.text('Matikan Mikrofon'), findsOneWidget);
      expect(find.text('Mikrofon sudah mati'), findsOneWidget);

      final listTile = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Matikan Mikrofon'));
      expect(listTile.enabled, isFalse);

      controller.dispose();
    });
  });
}

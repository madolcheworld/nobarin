import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/lobby/presentation/widgets/room_card.dart';
import 'package:nobarin/features/room/models/room_model.dart';

void main() {
  group('RoomCard Widget Tests', () {
    final testRoomWithThumb = RoomModel(
      id: 'room-1',
      code: 'WP1234',
      title: 'Nobar Anime Premiere',
      description: 'Nonton bareng episode perdana seru',
      currentMediaUrl: 'https://example.com/video.mp4',
      currentMediaType: 'direct_url',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      currentState: 'playing',
      currentPosition: 120,
      hostName: 'AdminNobar',
      participantCount: 15,
      controlMode: 'host_only',
      livekitRoomName: 'room-1',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final testRoomFallback = RoomModel(
      id: 'room-2',
      code: 'WP5678',
      title: 'Video Stream Room',
      description: 'Championship final watch party',
      currentMediaUrl: 'https://example.com/stream.m3u8',
      currentMediaType: 'direct_url',
      thumbnailUrl: null,
      currentState: 'paused',
      currentPosition: 0,
      hostName: 'GamerX',
      participantCount: 42,
      controlMode: 'collaborative',
      livekitRoomName: 'room-2',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    testWidgets('RoomCard renders thumbnail image, title, host pill, and badge',
        (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 140,
              child: RoomCard(
                room: testRoomWithThumb,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      // Verify title, host, participant count, source, and control mode
      expect(find.text('Nobar Anime Premiere'), findsOneWidget);
      expect(find.text('AdminNobar'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('Direct URL'), findsOneWidget);
      expect(find.text('Host'), findsOneWidget);

      // Verify tap
      await tester.tap(find.byType(RoomCard));
      expect(tapped, isTrue);
    });

    testWidgets(
        'RoomCard renders fallback thumbnail cleanly when thumbnailUrl is null',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 140,
              child: RoomCard(
                room: testRoomFallback,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      // Verify source label, title, host, and collaborative mode
      expect(find.text('Video Stream Room'), findsOneWidget);
      expect(find.text('GamerX'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Bebas'), findsOneWidget);
    });
  });
}

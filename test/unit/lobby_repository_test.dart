import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/lobby/data/lobby_repository.dart';
import 'package:nobarin/features/room/models/room_model.dart';

void main() {
  group('LobbyRepository Tests', () {
    late LobbyRepository repository;

    setUp(() {
      repository = LobbyRepository(supabase: null);
    });

    test('generateRoomCode produces 6-character uppercase code starting with WP',
        () {
      for (int i = 0; i < 50; i++) {
        final code = repository.generateRoomCode();
        expect(code.length, 6);
        expect(code.startsWith('WP'), isTrue);
        expect(code, matches(r'^WP[A-Z2-9]{4}$'));
      }
    });

    test('getPublicRooms returns fallback demo rooms when offline', () async {
      final rooms = await repository.getPublicRooms();
      expect(rooms.isNotEmpty, isTrue);
      expect(rooms.first.isPublic, isTrue);
    });

    test('createRoom adds room and getRoomByCode retrieves it correctly',
        () async {
      final room = await repository.createRoom(
        title: 'Unit Test Room',
        description: 'Testing room creation logic',
        hostId: 'host-100',
        hostName: 'TestHost',
        isPublic: true,
        controlMode: 'collaborative',
        initialMediaType: 'youtube',
        initialMediaUrl: 'https://youtube.com/watch?v=demo',
      );

      expect(room.title, 'Unit Test Room');
      expect(room.hostId, 'host-100');
      expect(room.isCollaborative, isTrue);
      expect(room.currentMediaType, 'youtube');

      // Fetch by code
      final found = await repository.getRoomByCode(room.code);
      expect(found, isNotNull);
      expect(found!.id, room.id);
      expect(found.title, room.title);

      // Fetch with lowercase code
      final foundLower =
          await repository.getRoomByCode(room.code.toLowerCase());
      expect(foundLower, isNotNull);
      expect(foundLower!.id, room.id);
    });

    test('normalizeCode removes hyphens, spaces, and converts to uppercase', () {
      expect(LobbyRepository.normalizeCode('wp-1001'), 'WP1001');
      expect(LobbyRepository.normalizeCode(' WP-1001 '), 'WP1001');
      expect(LobbyRepository.normalizeCode('  wp  2002  '), 'WP2002');
      expect(LobbyRepository.normalizeCode('wp1001'), 'WP1001');
      expect(LobbyRepository.normalizeCode('http://localhost:8080/#/room/WP1001'), 'WP1001');
      expect(LobbyRepository.normalizeCode('https://watchparty.app/room/wp-2002?ref=share'), 'WP2002');
      expect(LobbyRepository.normalizeCode('/room/WP1001'), 'WP1001');
      expect(LobbyRepository.normalizeCode('/rooms/WP1001'), 'WP1001');
      expect(LobbyRepository.normalizeCode('https://watchparty.app/join/WP1001'), 'WP1001');
      expect(LobbyRepository.normalizeCode('https://watchparty.app/?room=WP1001'), 'WP1001');
      expect(LobbyRepository.normalizeCode('#/room/1001'), '1001');
      expect(LobbyRepository.normalizeCode('#WP1001'), 'WP1001');

      // Quotes
      expect(LobbyRepository.normalizeCode('"WP1001"'), 'WP1001');
      expect(LobbyRepository.normalizeCode("'WP-1001'"), 'WP1001');
      expect(LobbyRepository.normalizeCode('“WP1001”'), 'WP1001');

      // Unicode dashes (en-dash, em-dash, minus)
      expect(LobbyRepository.normalizeCode('WP–1001'), 'WP1001');
      expect(LobbyRepository.normalizeCode('WP—1001'), 'WP1001');
      expect(LobbyRepository.normalizeCode('WP−1001'), 'WP1001');

      // Zero-width spaces & non-breaking spaces
      expect(LobbyRepository.normalizeCode('WP1001\u200B'), 'WP1001');
      expect(LobbyRepository.normalizeCode('WP\u00A01001'), 'WP1001');

      // Prefixes
      expect(LobbyRepository.normalizeCode('Kode room: WP1001'), 'WP1001');
      expect(LobbyRepository.normalizeCode('Kode: WP-1001'), 'WP1001');
      expect(LobbyRepository.normalizeCode('Code: WP1001'), 'WP1001');
      expect(LobbyRepository.normalizeCode('Room code: WP1001'), 'WP1001');

      // Trailing punctuation
      expect(LobbyRepository.normalizeCode('WP1001.'), 'WP1001');
      expect(LobbyRepository.normalizeCode('WP1001,'), 'WP1001');
    });

    test('getCodeCandidates generates expected permutations for WP and non-WP codes', () {
      final candidates = LobbyRepository.getCodeCandidates('wp-1001');
      expect(candidates.contains('WP1001'), isTrue);
      expect(candidates.contains('WP-1001'), isTrue);
      expect(candidates.contains('1001'), isTrue);

      // OCR / keystroke substitution 'O' <-> '0'
      final ocrCandidates = LobbyRepository.getCodeCandidates('WPIOOI');
      expect(ocrCandidates.contains('WP1001'), isTrue);

      // Non-WP code: letters + digits
      final nonWpCandidates = LobbyRepository.getCodeCandidates('TEST99');
      expect(nonWpCandidates.contains('TEST99'), isTrue);
      expect(nonWpCandidates.contains('TEST-99'), isTrue);
      expect(nonWpCandidates.contains('99'), isTrue);

      // En-dash input
      final dashCandidates = LobbyRepository.getCodeCandidates('WP–1001');
      expect(dashCandidates.contains('WP1001'), isTrue);
      expect(dashCandidates.contains('WP-1001'), isTrue);

      // Quoted input
      final quotedCandidates = LobbyRepository.getCodeCandidates('"WP1001"');
      expect(quotedCandidates.contains('WP1001'), isTrue);
    });

    test('getRoomByCode retrieves room with various formats: hyphens, spaces, suffix-only, URLs, OCR, quotes, dashes',
        () async {
      // Demo room WP1001
      final exact = await repository.getRoomByCode('WP1001');
      expect(exact, isNotNull);
      expect(exact!.code, 'WP1001');

      // Lowercase with hyphen
      final hyphenLower = await repository.getRoomByCode('wp-1001');
      expect(hyphenLower, isNotNull);
      expect(hyphenLower!.code, 'WP1001');

      // En-dash and em-dash
      final enDash = await repository.getRoomByCode('WP–1001');
      expect(enDash, isNotNull);
      expect(enDash!.code, 'WP1001');

      final emDash = await repository.getRoomByCode('WP—1001');
      expect(emDash, isNotNull);
      expect(emDash!.code, 'WP1001');

      // Quoted code
      final quoted = await repository.getRoomByCode('"WP1001"');
      expect(quoted, isNotNull);
      expect(quoted!.code, 'WP1001');

      // Zero-width space
      final zwsp = await repository.getRoomByCode('WP1001\u200B');
      expect(zwsp, isNotNull);
      expect(zwsp!.code, 'WP1001');

      // Prefix
      final prefix = await repository.getRoomByCode('Kode room: WP-1001');
      expect(prefix, isNotNull);
      expect(prefix!.code, 'WP1001');

      // Space padded
      final spacePadded = await repository.getRoomByCode('  WP 1001  ');
      expect(spacePadded, isNotNull);
      expect(spacePadded!.code, 'WP1001');

      // 4-character suffix without WP
      final suffixOnly = await repository.getRoomByCode('1001');
      expect(suffixOnly, isNotNull);
      expect(suffixOnly!.code, 'WP1001');

      // Full URL pasted into join dialog
      final fromUrl = await repository.getRoomByCode('http://localhost:8080/#/room/WP1001');
      expect(fromUrl, isNotNull);
      expect(fromUrl!.code, 'WP1001');

      // Rooms URL pasted
      final fromRoomsUrl = await repository.getRoomByCode('https://watchparty.app/rooms/WP1001');
      expect(fromRoomsUrl, isNotNull);
      expect(fromRoomsUrl!.code, 'WP1001');

      // Path pasted
      final fromPath = await repository.getRoomByCode('/room/wp-1001');
      expect(fromPath, isNotNull);
      expect(fromPath!.code, 'WP1001');

      // OCR confusion (user types letter O instead of number 0)
      final ocr = await repository.getRoomByCode('WPIOOI');
      expect(ocr, isNotNull);
      expect(ocr!.code, 'WP1001');

      // Empty code returns null
      final empty = await repository.getRoomByCode('   ');
      expect(empty, isNull);
    });

    test('getRoomByCode returns null for non-existent code', () async {
      final notFound = await repository.getRoomByCode('NON999');
      expect(notFound, isNull);
    });

    test('deleteRoom removes room from demoRooms and lookup fails', () async {
      final room = await repository.createRoom(
        title: 'Room to Delete',
        hostId: 'host-del',
        hostName: 'HostDel',
        isPublic: true,
      );

      // Verify created
      final found = await repository.getRoomByCode(room.code);
      expect(found, isNotNull);

      // Delete room
      await repository.deleteRoom(room.id, code: room.code);

      // Verify no longer found
      final deleted = await repository.getRoomByCode(room.code);
      expect(deleted, isNull);

      // Verify not in public rooms
      final publicRooms = await repository.getPublicRooms();
      expect(publicRooms.any((r) => r.id == room.id), isFalse);
    });

    test('extractHostKey correctly identifies host by ID, metadata, or name', () {
      final roomWithId = RoomModel(
        id: 'r1',
        code: 'WP1111',
        title: 'Room 1',
        hostId: 'user-abc',
        hostName: 'Alice',
        isPublic: true,
        livekitRoomName: 'room_1',
      );
      expect(LobbyRepository.extractHostKey(roomWithId), 'id:user-abc');

      final roomWithMeta = RoomModel(
        id: 'r2',
        code: 'WP2222',
        title: 'Room 2',
        description: '[HOST:name=kas;id=user-xyz] Fun room',
        hostName: 'Host',
        isPublic: true,
        livekitRoomName: 'room_2',
      );
      expect(LobbyRepository.extractHostKey(roomWithMeta), 'id:user-xyz');

      final roomWithNameOnly = RoomModel(
        id: 'r3',
        code: 'WP3333',
        title: 'Room 3',
        hostName: 'Budi',
        isPublic: true,
        livekitRoomName: 'room_3',
      );
      expect(LobbyRepository.extractHostKey(roomWithNameOnly), 'name:budi');
    });

    test('createRoom cleans up previous room from same host to avoid duplicate rooms', () async {
      // 1. Create first room for host
      final firstRoom = await repository.createRoom(
        title: 'Kas Room 1',
        hostId: 'host-kas-id',
        hostName: 'kas',
        isPublic: true,
      );
      expect(firstRoom, isNotNull);

      // Verify first room exists
      var publicRooms = await repository.getPublicRooms();
      expect(publicRooms.any((r) => r.id == firstRoom.id), isTrue);

      // 2. Create second room for the SAME host
      final secondRoom = await repository.createRoom(
        title: 'Kas Room 2',
        hostId: 'host-kas-id',
        hostName: 'kas',
        isPublic: true,
      );
      expect(secondRoom, isNotNull);

      // 3. Verify public rooms ONLY contains the second room, not the first!
      publicRooms = await repository.getPublicRooms();
      expect(publicRooms.any((r) => r.id == secondRoom.id), isTrue);
      expect(publicRooms.any((r) => r.id == firstRoom.id), isFalse);
    });

    test('deduplicateRooms keeps only the newest room per host', () {
      final now = DateTime.now();
      final duplicateList = [
        RoomModel(
          id: 'room-new',
          code: 'WPNEW1',
          title: 'Nonton Bareng Baru',
          hostName: 'kas',
          isPublic: true,
          livekitRoomName: 'live_new',
          createdAt: now,
        ),
        RoomModel(
          id: 'room-old',
          code: 'WPOLD1',
          title: 'Nonton Bareng Lama',
          hostName: 'kas',
          isPublic: true,
          livekitRoomName: 'live_old',
          createdAt: now.subtract(const Duration(minutes: 10)),
        ),
      ];

      final deduped = repository.deduplicateRooms(duplicateList);
      expect(deduped.length, 1);
      expect(deduped.first.id, 'room-new');
      expect(deduped.first.code, 'WPNEW1');
    });
  });
}

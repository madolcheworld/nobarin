import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/lobby/data/lobby_repository.dart';
import 'package:nobarin/features/lobby/presentation/lobby_controller.dart';

void main() {
  group('LobbyController Unit Tests', () {
    late LobbyRepository repository;
    late ProviderContainer container;

    setUp(() {
      repository = LobbyRepository(supabase: null);
      container = ProviderContainer(
        overrides: [
          lobbyRepositoryProvider.overrideWithValue(repository),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('LobbyController loads public rooms on initialization', () async {
      await container.read(lobbyControllerProvider.notifier).refreshRooms();
      final rooms = container.read(lobbyControllerProvider).asData?.value;
      expect(rooms, isNotNull);
      expect(rooms!.isNotEmpty, isTrue);
      expect(rooms.any((r) => r.code == 'WP1001'), isTrue);
    });

    test('findRoomByCode finds room from existing state cache', () async {
      final controller = container.read(lobbyControllerProvider.notifier);
      await controller.refreshRooms();

      // Lookup with lowercase and hyphen
      final foundHyphen = await controller.findRoomByCode('wp-1001');
      expect(foundHyphen, isNotNull);
      expect(foundHyphen!.code, 'WP1001');

      // Lookup with suffix only
      final foundSuffix = await controller.findRoomByCode('1001');
      expect(foundSuffix, isNotNull);
      expect(foundSuffix!.code, 'WP1001');

      // Lookup with spaces
      final foundSpace = await controller.findRoomByCode('  wp 1001  ');
      expect(foundSpace, isNotNull);
      expect(foundSpace!.code, 'WP1001');

      // Lookup non-existent
      final notFound = await controller.findRoomByCode('XYZ999');
      expect(notFound, isNull);
    });

    test('createRoom adds new room and findRoomByCode retrieves it', () async {
      final controller = container.read(lobbyControllerProvider.notifier);
      final room = await controller.createRoom(
        title: 'New Controller Room',
        hostId: 'host-xyz',
        hostName: 'HostXyz',
        isPublic: true,
      );

      expect(room, isNotNull);

      // Verify findRoomByCode finds it
      final found = await controller.findRoomByCode(room!.code.toLowerCase());
      expect(found, isNotNull);
      expect(found!.id, room.id);
      expect(found.title, 'New Controller Room');
    });

    test('filteredRoomsProvider filters by title, host, and tolerant code format',
        () async {
      await container.read(lobbyControllerProvider.notifier).refreshRooms();

      // 1. Initial unfiltered list
      final allRooms = container.read(filteredRoomsProvider);
      expect(allRooms.isNotEmpty, isTrue);

      // 2. Filter by exact code
      container.read(lobbySearchQueryProvider.notifier).state = 'WP1001';
      var filtered = container.read(filteredRoomsProvider);
      expect(filtered.length, 1);
      expect(filtered.first.code, 'WP1001');

      // 3. Filter by hyphenated lowercase code
      container.read(lobbySearchQueryProvider.notifier).state = 'wp-1001';
      filtered = container.read(filteredRoomsProvider);
      expect(filtered.length, 1);
      expect(filtered.first.code, 'WP1001');

      // 4. Filter by suffix
      container.read(lobbySearchQueryProvider.notifier).state = '1001';
      filtered = container.read(filteredRoomsProvider);
      expect(filtered.length, 1);
      expect(filtered.first.code, 'WP1001');

      // 5. Filter by host name
      container.read(lobbySearchQueryProvider.notifier).state = 'Popcorn';
      filtered = container.read(filteredRoomsProvider);
      expect(filtered.isNotEmpty, isTrue);
      expect(filtered.first.hostName, contains('Popcorn'));
    });

    test('findRoomByCode does not add private rooms into public lobby state', () async {
      final controller = container.read(lobbyControllerProvider.notifier);
      await controller.refreshRooms();
      final initialCount = container.read(lobbyControllerProvider).asData!.value.length;

      final privateRoom = await repository.createRoom(
        title: 'Secret Private Room',
        hostId: 'host-secret',
        hostName: 'HostSecret',
        isPublic: false,
      );

      final found = await controller.findRoomByCode(privateRoom.code);
      expect(found, isNotNull);
      expect(found!.id, privateRoom.id);

      // Verify private room was NOT added to public lobby state
      final currentRooms = container.read(lobbyControllerProvider).asData!.value;
      expect(currentRooms.length, initialCount);
      expect(currentRooms.any((r) => r.id == privateRoom.id), isFalse);
    });

    test('deleteRoom removes room from lobby state and prevents lookup', () async {
      final controller = container.read(lobbyControllerProvider.notifier);
      final room = await controller.createRoom(
        title: 'Public Room to Remove',
        hostId: 'host-del-ctrl',
        hostName: 'HostDelCtrl',
        isPublic: true,
      );
      expect(room, isNotNull);

      // Verify present in lobby
      var currentRooms = container.read(lobbyControllerProvider).asData!.value;
      expect(currentRooms.any((r) => r.id == room!.id), isTrue);

      // Delete room
      await controller.deleteRoom(room!.id, code: room.code);

      // Verify removed from lobby state
      currentRooms = container.read(lobbyControllerProvider).asData!.value;
      expect(currentRooms.any((r) => r.id == room.id), isFalse);

      // Verify findRoomByCode returns null
      final lookup = await controller.findRoomByCode(room.code);
      expect(lookup, isNull);
    });

    test('markRoomClosedLocally instantly removes room from lobby state and memory', () async {
      final controller = container.read(lobbyControllerProvider.notifier);
      final room = await controller.createRoom(
        title: 'Instant Close Room',
        hostId: 'host-inst',
        hostName: 'HostInst',
        isPublic: true,
      );
      expect(room, isNotNull);

      var currentRooms = container.read(lobbyControllerProvider).asData!.value;
      expect(currentRooms.any((r) => r.id == room!.id), isTrue);

      controller.markRoomClosedLocally(room!.id, code: room.code);

      currentRooms = container.read(lobbyControllerProvider).asData!.value;
      expect(currentRooms.any((r) => r.id == room.id), isFalse);
    });

    test('findRoomByCode never returns rooms in closed state', () async {
      final controller = container.read(lobbyControllerProvider.notifier);
      final room = await controller.createRoom(
        title: 'Closed Test Room',
        hostId: 'host-closed',
        hostName: 'HostClosed',
        isPublic: true,
      );
      expect(room, isNotNull);

      // Close it locally
      controller.markRoomClosedLocally(room!.id, code: room.code);

      // Lookup should return null
      final lookup = await controller.findRoomByCode(room.code);
      expect(lookup, isNull);
    });

    test('createRoom replaces old room from same host avoiding duplicate cards', () async {
      final controller = container.read(lobbyControllerProvider.notifier);
      await controller.refreshRooms();

      // Create first room for host
      final room1 = await controller.createRoom(
        title: 'Host Kas Room 1',
        hostId: 'host-kas-ctrl',
        hostName: 'kas',
        isPublic: true,
      );
      expect(room1, isNotNull);

      var rooms = container.read(lobbyControllerProvider).asData!.value;
      expect(rooms.any((r) => r.id == room1!.id), isTrue);

      // Create second room for same host
      final room2 = await controller.createRoom(
        title: 'Host Kas Room 2',
        hostId: 'host-kas-ctrl',
        hostName: 'kas',
        isPublic: true,
      );
      expect(room2, isNotNull);

      rooms = container.read(lobbyControllerProvider).asData!.value;
      expect(rooms.any((r) => r.id == room2!.id), isTrue);
      expect(rooms.any((r) => r.id == room1!.id), isFalse);

      // Total count of rooms with host 'kas' must be exactly 1
      final kasRooms = rooms.where((r) => r.hostName == 'kas').toList();
      expect(kasRooms.length, 1);
      expect(kasRooms.first.id, room2!.id);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/lobby/presentation/lobby_screen.dart';
import '../../features/room/models/room_model.dart';
import '../../features/room/presentation/room_screen.dart';

class _GoRouterRefreshNotifier extends ChangeNotifier {
  _GoRouterRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (previous, next) {
      notifyListeners();
    });
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _GoRouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);

      // Do not redirect while auth status is being loaded from local storage
      if (authState.isLoading) {
        return null;
      }

      final profile = authState.asData?.value;
      final isAtWelcome = state.matchedLocation == '/';

      // If user profile is already configured and at welcome, proceed to lobby
      if (profile != null && isAtWelcome) {
        return '/lobby';
      }

      // If user profile is not yet configured and trying to access lobby or room
      if (profile == null && !isAtWelcome) {
        final segments = state.uri.pathSegments;
        if (segments.length >= 2 &&
            (segments[0] == 'room' || segments[0] == 'rooms')) {
          return '/?room=${segments[1]}';
        }
        return '/';
      }

      return null;
    },
    errorBuilder: (context, state) {
      return Scaffold(
        backgroundColor: const Color(0xFF090B14),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.explore_off_rounded,
                  color: Color(0xFFFF5252),
                  size: 54,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Halaman Tidak Ditemukan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rute "${state.uri}" tidak tersedia atau telah dipindahkan.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF9E9E9E),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => context.go('/lobby'),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('Kembali ke Lobby'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FFC2),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/lobby',
        builder: (context, state) => const LobbyScreen(),
      ),
      GoRoute(
        path: '/room/:code',
        builder: (context, state) {
          final code = state.pathParameters['code'] ?? '';
          final room = state.extra as RoomModel?;
          return RoomScreen(roomCode: code, initialRoom: room);
        },
      ),
    ],
  );
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/lobby/presentation/lobby_screen.dart';
import '../../features/room/models/room_model.dart';
import '../../features/room/presentation/room_screen.dart';
import '../constants/app_colors.dart';

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
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.explore_off_rounded,
                  color: AppColors.accentRed,
                  size: 54,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Halaman Tidak Ditemukan',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rute "${state.uri}" tidak tersedia atau telah dipindahkan.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => context.go('/lobby'),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('Kembali ke Lobby'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNeon,
                    foregroundColor: Colors.white,
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
          final extra = state.extra;
          RoomModel? room;
          if (extra is RoomModel) {
            room = extra;
          } else if (extra is Map<String, dynamic>) {
            room = extra['room'] as RoomModel?;
          }
          return RoomScreen(
            roomCode: code,
            initialRoom: room,
          );
        },
      ),
    ],
  );
});

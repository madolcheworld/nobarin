import 'package:flutter/foundation.dart';
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

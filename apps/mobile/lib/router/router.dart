import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/hub/hub_screen.dart';
import '../screens/settings/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Watch auth state so the router rebuilds on login/logout.
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: auth.token != null ? '/hub' : '/login',
    redirect: (context, state) {
      final loggedIn = auth.token != null;
      final loc = state.matchedLocation;
      final onAuth = loc == '/login' || loc.startsWith('/signup');

      if (!loggedIn && !onAuth) return '/login';
      if (loggedIn && onAuth) return '/hub';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, __) => const SignupScreen(),
      ),
      GoRoute(
        path: '/hub',
        builder: (_, __) => const HubScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
    ],
  );
});

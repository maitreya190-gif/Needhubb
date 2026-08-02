import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/hub/hub_screen.dart';
import '../screens/needs/need_deep_link_screen.dart';
import '../screens/settings/settings_screen.dart';

/// A ChangeNotifier that mirrors the Riverpod auth state so GoRouter's
/// refreshListenable can react to login/logout WITHOUT recreating the
/// router (and therefore the entire widget tree) on every state change.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthChangeNotifier(ref);

  return GoRouter(
    initialLocation: ref.read(authProvider).token != null ? '/hub' : '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final loggedIn = ref.read(authProvider).token != null;
      final loc = state.matchedLocation;
      final onAuth = loc == '/login' || loc.startsWith('/signup');

      if (!loggedIn && !onAuth) return '/login';
      if (loggedIn && onAuth) return '/hub';
      return null;
    },
    routes: [
      // Deep linking is enabled in AndroidManifest.xml so shared Need links
      // reach the router, which means the platform can now hand us "/" on a
      // plain launch. Without a route for it that would be an unmatched-route
      // error screen instead of the app.
      GoRoute(
        path: '/',
        redirect: (_, __) => '/hub',
      ),
      // Opened from a shared Need card — see lib/share-card.ts on the API.
      // Two paths for the two link forms that reach us: the custom scheme
      // (needhub:///need/<id>) and the https App Link, whose public URL is
      // <api>/n/<id>. Both resolve to the same screen.
      GoRoute(
        path: '/need/:id',
        builder: (_, state) => NeedDeepLinkScreen(needId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/n/:id',
        builder: (_, state) => NeedDeepLinkScreen(needId: state.pathParameters['id']!),
      ),
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

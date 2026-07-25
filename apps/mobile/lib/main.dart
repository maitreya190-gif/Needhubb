import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/user_state.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'router/router.dart';
import 'services/chitchat_api.dart';
import 'services/needs_api.dart';
import 'services/notifications_api.dart';
import 'services/profiles_api.dart';
import 'services/reviews_api.dart';
import 'services/social_providers.dart';
import 'services/uploads_api.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: NeedHubApp()));
}

class NeedHubApp extends ConsumerStatefulWidget {
  const NeedHubApp({super.key});

  @override
  ConsumerState<NeedHubApp> createState() => _NeedHubAppState();
}

class _NeedHubAppState extends ConsumerState<NeedHubApp> {
  Timer? _socialPoller;
  Timer? _chitchatPoller;
  Timer? _notifPoller;
  String? _lastHydratedUserId;

  @override
  void initState() {
    super.initState();
    // Restore persisted auth session on startup.
    Future.microtask(() => ref.read(authProvider.notifier).init());
  }

  @override
  void dispose() {
    _socialPoller?.cancel();
    _chitchatPoller?.cancel();
    _notifPoller?.cancel();
    super.dispose();
  }

  void _onAuthChanged(AuthState next) {
    if (next.isAuthenticated) {
      if (_lastHydratedUserId != next.userId) {
        _lastHydratedUserId = next.userId;
        resetAllUserNotifiersOnLogout();
        _hydrateAndPoll();
      }
    } else {
      _lastHydratedUserId = null;
      _socialPoller?.cancel();
      _chitchatPoller?.cancel();
      _notifPoller?.cancel();
      _socialPoller = null;
      _chitchatPoller = null;
      _notifPoller = null;
      resetAllUserNotifiersOnLogout();
    }
  }

  Future<void> _hydrateAndPoll() async {
    final friendsApi = ref.read(friendsApiProvider);
    final chitchatApi = ref.read(chitchatApiProvider);
    final needsApi = ref.read(needsApiProvider);
    final notificationsApi = ref.read(notificationsApiProvider);
    final profilesApi = ref.read(profilesApiProvider);
    final reviewsApi = ref.read(reviewsApiProvider);

    // Initial hydration.
    unawaited(hydrateSocialState(friendsApi));
    unawaited(_hydrateChitchat(chitchatApi));
    unawaited(_hydrateFeed(needsApi));
    unawaited(_hydrateNotifications(notificationsApi));
    unawaited(_hydrateProfile(profilesApi));
    unawaited(_hydratePendingReviews(reviewsApi));
    unawaited(_hydrateUploads(ref.read(uploadsApiProvider)));

    // Social polling — friend requests inbox refreshes every 30s.
    _socialPoller?.cancel();
    _socialPoller = Timer.periodic(const Duration(seconds: 30), (_) {
      hydrateSocialState(friendsApi);
    });

    // ChitChat polling — roster + own status every 15s while foregrounded.
    // Roster is only relevant when user is on the ChitChat surface, but
    // polling globally keeps `chitchatRosterNotifier` warm without extra
    // per-screen boilerplate.
    _chitchatPoller?.cancel();
    _chitchatPoller = Timer.periodic(const Duration(seconds: 15), (_) {
      _hydrateChitchat(chitchatApi);
    });

    // Notifications: unread count refreshes every 30s while foregrounded.
    _notifPoller?.cancel();
    _notifPoller = Timer.periodic(const Duration(seconds: 30), (_) {
      _hydrateNotifications(notificationsApi);
    });
  }

  Future<void> _hydrateChitchat(ChitchatApi api) async {
    try {
      final status = await api.status();
      chitchatAvailableUntilNotifier.value = status.availableUntil;
      chitChatAvailableNotifier.value = status.available;
    } catch (_) {/* swallow */}
    try {
      final roster = await api.availablePeople();
      chitchatRosterNotifier.value = roster;
    } catch (_) {/* swallow */}
  }

  Future<void> _hydrateFeed(NeedsApi api) async {
    try {
      final res = await api.feed(sort: 'smart', take: 60);
      if (res.needs.isNotEmpty) {
        feedNeedsNotifier.value = res.needs;
        feedRankerNotifier.value = res.ranker;
      }
    } catch (_) {/* swallow — the mock fallback stays visible */}
  }

  Future<void> _hydrateNotifications(NotificationsApi api) async {
    try {
      final count = await api.unreadCount();
      unreadCountNotifier.value = count;
    } catch (_) {/* swallow */}
    try {
      final list = await api.list(take: 30);
      notificationsListNotifier.value = list;
    } catch (_) {/* swallow */}
  }

  Future<void> _hydrateProfile(ProfilesApi api) async {
    try {
      final me = await api.me();
      myProfileNotifier.value = me;
      pointsNotifier.value = me.pointsTotal;
      bioNotifier.value = me.bio ?? '';
      promptSkillNotifier.value = me.promptSkill ?? '';
      promptCollabNotifier.value = me.promptCollab ?? '';
      promptNeedNotifier.value = me.promptNeed ?? '';
      genderNotifier.value = me.gender;
      locationNotifier.value = (me.locationText != null && me.locationText!.isNotEmpty)
          ? me.locationText!
          : 'Bangalore';
      avatarUrlNotifier.value = me.avatarUrl;
      customInterestsNotifier.value = me.interestLabels;
      customSkillsNotifier.value = me.skillLabels;
    } catch (_) {/* swallow */}
  }

  Future<void> _hydratePendingReviews(ReviewsApi api) async {
    try {
      pendingReviewsNotifier.value = await api.pending();
    } catch (_) {/* swallow */}
  }

  Future<void> _hydrateUploads(UploadsApi api) async {
    try {
      myCertificatesNotifier.value = await api.myCertificates();
    } catch (_) {/* swallow */}
    try {
      myAchievementsNotifier.value = await api.myAchievements();
    } catch (_) {/* swallow */}
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final router = ref.watch(routerProvider);
    ref.listen<AuthState>(authProvider, (_, next) => _onAuthChanged(next));

    return MaterialApp.router(
      title: 'NeedHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.forTokens(tokens),
      routerConfig: router,
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/need.dart';
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
import 'services/socket_service.dart';
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

class _NeedHubAppState extends ConsumerState<NeedHubApp> with WidgetsBindingObserver {
  Timer? _socialPoller;
  Timer? _chitchatPoller;
  Timer? _notifPoller;
  Timer? _feedPoller;
  Timer? _uploadsPoller;
  String? _lastHydratedUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Restore persisted auth session on startup.
    Future.microtask(() => ref.read(authProvider.notifier).init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socialPoller?.cancel();
    _chitchatPoller?.cancel();
    _notifPoller?.cancel();
    _feedPoller?.cancel();
    _uploadsPoller?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app comes back to the foreground, refresh everything so users
    // see the latest data without needing to logout/login.
    if (state == AppLifecycleState.resumed && _lastHydratedUserId != null) {
      _hydrateEverything();
    }
  }

  Future<void> _hydrateEverything() async {
    final friendsApi = ref.read(friendsApiProvider);
    final chitchatApi = ref.read(chitchatApiProvider);
    final needsApi = ref.read(needsApiProvider);
    final notificationsApi = ref.read(notificationsApiProvider);
    final profilesApi = ref.read(profilesApiProvider);
    final reviewsApi = ref.read(reviewsApiProvider);
    final uploadsApi = ref.read(uploadsApiProvider);

    unawaited(hydrateSocialState(friendsApi));
    unawaited(_hydrateChitchat(chitchatApi));
    unawaited(_hydrateFeed(needsApi));
    unawaited(_hydrateNotifications(notificationsApi));
    unawaited(_hydrateProfile(profilesApi));
    unawaited(_hydratePendingReviews(reviewsApi));
    unawaited(_hydrateUploads(uploadsApi));
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
      _feedPoller?.cancel();
      _uploadsPoller?.cancel();
      _socialPoller = null;
      _chitchatPoller = null;
      _notifPoller = null;
      _feedPoller = null;
      _uploadsPoller = null;
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

    // Social polling — friend requests inbox refreshes every 15s.
    _socialPoller?.cancel();
    _socialPoller = Timer.periodic(const Duration(seconds: 15), (_) {
      hydrateSocialState(friendsApi);
    });

    // ChitChat polling — roster + own status every 15s while foregrounded.
    _chitchatPoller?.cancel();
    _chitchatPoller = Timer.periodic(const Duration(seconds: 15), (_) {
      _hydrateChitchat(chitchatApi);
    });

    // Socket: increment badge instantly on new notification
    SocketService().onNewNotification((data) {
      unreadCountNotifier.value = (unreadCountNotifier.value) + 1;
    });

    // Notifications: poll every 30s as fallback (socket handles real-time)
    _notifPoller?.cancel();
    _notifPoller = Timer.periodic(const Duration(seconds: 30), (_) {
      _hydrateNotifications(notificationsApi);
    });

    // Feed: refresh every 30s so newly-posted needs from others surface.
    _feedPoller?.cancel();
    _feedPoller = Timer.periodic(const Duration(seconds: 30), (_) {
      _hydrateFeed(needsApi);
      _hydrateProfile(profilesApi);
      _hydratePendingReviews(reviewsApi);
    });

    // Uploads: certificate/achievement admin decisions refresh every 60s.
    _uploadsPoller?.cancel();
    _uploadsPoller = Timer.periodic(const Duration(seconds: 60), (_) {
      _hydrateUploads(ref.read(uploadsApiProvider));
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
      final Map<String, Need> map = {};
      for (final n in feedNeedsNotifier.value.where((n) => n.authorName == 'You' || n.authorInitials == 'ME')) {
        map[n.id] = n;
      }
      for (final n in res.needs) {
        map[n.id] = n;
      }
      feedNeedsNotifier.value = map.values.toList();
      feedRankerNotifier.value = res.ranker;
    } catch (_) {/* swallow */}
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
          : 'Mumbai';
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

import '../models/need.dart';
import '../models/user_state.dart';
import '../screens/hub/conversation_screen.dart';
import '../screens/hub/tabs/feed_tab.dart';
import '../screens/needs/need_detail_screen.dart';
import '../screens/person/person_screen.dart';
import '../screens/redeem/redeem_screen.dart';
import '../theme/tokens.dart';
import 'notifications_api.dart';
import 'social_providers.dart';

class NotificationNavigator {
  static Future<void> handleTap({
    required BuildContext context,
    required NhNotification notif,
    required WidgetRef ref,
    bool isBottomSheet = false,
  }) async {
    // 1. Mark notification as read immediately (optimistic UI update)
    final api = ref.read(notificationsApiProvider);
    if (notif.isUnread) {
      final now = DateTime.now();
      notificationsListNotifier.value = notificationsListNotifier.value
          .map((n) => n.id == notif.id
              ? NhNotification(
                  id: n.id,
                  type: n.type,
                  title: n.title,
                  body: n.body,
                  refType: n.refType,
                  refId: n.refId,
                  createdAt: n.createdAt,
                  readAt: now,
                )
              : n)
          .toList();
      unreadCountNotifier.value =
          (unreadCountNotifier.value - 1).clamp(0, 9999);
      try {
        await api.markRead(notif.id);
      } catch (_) {}
    }

    if (!context.mounted) return;

    // 2. Dismiss bottom sheet if open
    if (isBottomSheet && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    final type = notif.type.toUpperCase();
    final refType = notif.refType?.toUpperCase();
    final refId = notif.refId;

    // Helper for loading feedback if network fetch is required
    void showLoading() {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening...'),
          duration: Duration(milliseconds: 600),
        ),
      );
    }

    // A. FRIEND_REQUEST_ACCEPTED or MESSAGE_RECEIVED -> ALWAYS Redirect directly to DM Conversation Screen!
    final isFriendAccepted = type == 'FRIEND_REQUEST_ACCEPTED' ||
        type.contains('FRIEND_ACCEPTED') ||
        notif.title.toLowerCase().contains('accepted') ||
        notif.body.toLowerCase().contains('accepted your friend request');

    final isDmOrChat = isFriendAccepted ||
        type == 'MESSAGE_RECEIVED' ||
        type.contains('MESSAGE') ||
        type.contains('CHAT');

    if (isDmOrChat) {
      final nameFromBody = notif.body.contains(' accepted')
          ? notif.body.split(' accepted').first
          : (notif.body.contains(' sent') ? notif.body.split(' sent').first : notif.title);

      if (refId != null && refId.isNotEmpty) {
        showLoading();
        try {
          final profilesApi = ref.read(profilesApiProvider);
          final user = await profilesApi.getById(refId);
          if (!context.mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConversationScreen(
                name: user.displayName,
                initials: _initials(user.displayName),
                avatarColor: NeedHubTokens.forest,
                avatarUrl: user.avatarUrl,
                userId: user.id,
              ),
            ),
          );
          return;
        } catch (_) {
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ConversationScreen(
                  name: nameFromBody.isNotEmpty ? nameFromBody : 'Chat',
                  initials: _initials(nameFromBody),
                  avatarColor: NeedHubTokens.forest,
                  userId: refId,
                ),
              ),
            );
            return;
          }
        }
      } else {
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConversationScreen(
                name: nameFromBody.isNotEmpty ? nameFromBody : 'Chat',
                initials: _initials(nameFromBody),
                avatarColor: NeedHubTokens.forest,
              ),
            ),
          );
          return;
        }
      }
    }

    // B. NEED_RESPONSE_RECEIVED / NEED_UPDATE / NEED_OFFER / NEED_COMPLETED / NEED_ACCEPTED -> ALWAYS Redirect directly to NeedDetailScreen for exact target need!
    final isNeedNotif = type == 'NEED_RESPONSE_RECEIVED' ||
        type == 'NEED_UPDATE' ||
        type == 'NEED_COMPLETED' ||
        type == 'NEED_ACCEPTED' ||
        type == 'NEED_OFFER' ||
        type.contains('NEED') ||
        type.contains('OFFER') ||
        refType == 'NEED' ||
        refType == 'need';

    if (isNeedNotif) {
      Need? targetNeed;

      // 1. Check local mockNeeds for matching id or title
      if (refId != null && refId.isNotEmpty) {
        for (final n in mockNeeds) {
          if (n.id == refId) {
            targetNeed = n;
            break;
          }
        }
      }

      if (targetNeed == null) {
        for (final n in mockNeeds) {
          if (notif.body.toLowerCase().contains(n.title.toLowerCase()) ||
              notif.title.toLowerCase().contains(n.title.toLowerCase())) {
            targetNeed = n;
            break;
          }
        }
      }

      if (targetNeed != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => NeedDetailScreen(need: targetNeed!)),
        );
        return;
      }

      // 2. Fetch from API if refId is provided
      if (refId != null && refId.isNotEmpty) {
        showLoading();
        try {
          final needsApi = ref.read(needsApiProvider);
          final fetched = await needsApi.getById(refId);
          if (!context.mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NeedDetailScreen(need: fetched)),
          );
          return;
        } catch (_) {}
      }

      // 3. Fallback: Open first need in mockNeeds directly
      if (context.mounted) {
        final fallback = mockNeeds.isNotEmpty ? mockNeeds.first : null;
        if (fallback != null) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NeedDetailScreen(need: fallback)),
          );
        }
        return;
      }
    }

    // C. FRIEND_REQUEST_RECEIVED -> Redirect directly to Person Profile Screen for that user (where Accept/Decline decision card is displayed)
    if (type == 'FRIEND_REQUEST_RECEIVED' || (type.contains('FRIEND') && !isFriendAccepted)) {
      final nameFromBody = notif.body.contains(' sent')
          ? notif.body.split(' sent').first
          : notif.title;

      if (refId != null && refId.isNotEmpty) {
        showLoading();
        try {
          final profilesApi = ref.read(profilesApiProvider);
          final user = await profilesApi.getById(refId);
          if (!context.mounted) return;
          Navigator.of(context).push(
            PersonScreen.route(
              name: user.displayName,
              initials: _initials(user.displayName),
              avatarColor: NeedHubTokens.forest,
              avatarUrl: user.avatarUrl,
              userId: user.id,
            ),
          );
          return;
        } catch (_) {
          if (context.mounted) {
            Navigator.of(context).push(
              PersonScreen.route(
                name: nameFromBody.isNotEmpty ? nameFromBody : 'Friend Request',
                initials: _initials(nameFromBody),
                avatarColor: NeedHubTokens.forest,
                userId: refId,
              ),
            );
            return;
          }
        }
      } else {
        if (context.mounted) {
          Navigator.of(context).push(
            PersonScreen.route(
              name: nameFromBody.isNotEmpty ? nameFromBody : 'Friend Request',
              initials: _initials(nameFromBody),
              avatarColor: NeedHubTokens.forest,
            ),
          );
          return;
        }
      }
    }

    // D. REDEMPTION_READY -> Redirect to Redeem Screen
    if (type == 'REDEMPTION_READY' || refType == 'REDEMPTION') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RedeemScreen()),
      );
      return;
    }

    // E. REVIEW_RECEIVED / POINTS_AWARDED / CERT_APPROVED -> Open Person/User Profile
    if (type == 'REVIEW_RECEIVED' ||
        type == 'POINTS_AWARDED' ||
        type == 'CERT_APPROVED' ||
        type == 'CERT_REJECTED') {
      if (refId != null && refId.isNotEmpty) {
        Navigator.of(context).push(
          PersonScreen.route(
            name: notif.title,
            initials: 'NH',
            avatarColor: NeedHubTokens.forest,
            userId: refId,
          ),
        );
        return;
      }
    }

    // Fallback: If refId exists, push PersonScreen
    if (refId != null && refId.isNotEmpty) {
      Navigator.of(context).push(
        PersonScreen.route(
          name: notif.title,
          initials: 'NH',
          avatarColor: NeedHubTokens.forest,
          userId: refId,
        ),
      );
    }
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

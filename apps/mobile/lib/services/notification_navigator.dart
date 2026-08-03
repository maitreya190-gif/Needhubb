import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/need.dart';
import '../screens/hub/conversation_screen.dart';
import '../screens/needs/need_detail_screen.dart';
import '../screens/person/person_screen.dart';
import '../screens/redeem/redeem_screen.dart';
import '../screens/settings/plus_screen.dart';
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

    // A. CHAT ROUTING: FRIEND_REQUEST_ACCEPTED, MESSAGE_RECEIVED, or NEED_ACCEPTED
    final isChatRouting = type == 'FRIEND_REQUEST_ACCEPTED' ||
        type.contains('FRIEND_ACCEPTED') ||
        type == 'MESSAGE_RECEIVED' ||
        type.contains('MESSAGE') ||
        type.contains('CHAT') ||
        type == 'NEED_ACCEPTED' ||
        notif.title.toLowerCase().contains('accepted');

    if (isChatRouting) {
      String chatName = 'Chat';
      if (notif.body.toLowerCase().contains(' accepted')) {
        chatName = notif.body.split(RegExp(r' accepted', caseSensitive: false)).first.trim();
      } else if (notif.body.toLowerCase().contains(' sent')) {
        chatName = notif.body.split(RegExp(r' sent', caseSensitive: false)).first.trim();
      } else if (notif.title.toLowerCase().contains('accepted')) {
        chatName = notif.title
            .replaceFirst(RegExp(r'Your req has been ', caseSensitive: false), '')
            .replaceFirst(RegExp(r'accepted', caseSensitive: false), '')
            .trim();
      }
      if (chatName.isEmpty) chatName = notif.title;

      if (refId != null && refId.isNotEmpty) {
        showLoading();
        // 1. Try to fetch as a User
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
        } catch (_) {}

        // 2. Try to fetch as a Need
        try {
          final needsApi = ref.read(needsApiProvider);
          final need = await needsApi.getById(refId);
          if (!context.mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConversationScreen(
                name: need.authorName,
                initials: need.authorInitials,
                avatarColor: NeedHubTokens.forest,
                avatarUrl: need.posterAvatarUrl,
                userId: need.posterId,
              ),
            ),
          );
          return;
        } catch (_) {}
      }

      // If we failed to resolve the refId via API, do NOT open a buggy fallback chat screen.
      // We just return to prevent opening a chat with the profile name "your req has been accepted".
      return;
    }

    // B. NEED ROUTING: NEED_RESPONSE_RECEIVED, NEED_UPDATE, NEED_COMPLETED, NEED_OFFER
    final isNeedNotif = type == 'NEED_RESPONSE_RECEIVED' ||
        type == 'NEED_UPDATE' ||
        type == 'NEED_COMPLETED' ||
        type == 'NEED_OFFER' ||
        type == 'SKILL_MATCH_NEED' ||
        type.contains('NEED') ||
        type.contains('SKILL') ||
        type.contains('OFFER') ||
        refType == 'NEED' ||
        refType == 'need';

    if (isNeedNotif) {
      Need? targetNeed;
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
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => NeedDetailScreen(need: targetNeed!)));
        return;
      }

      if (refId != null && refId.isNotEmpty) {
        showLoading();
        try {
          final needsApi = ref.read(needsApiProvider);
          final fetched = await needsApi.getById(refId);
          if (!context.mounted) return;
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => NeedDetailScreen(need: fetched)));
          return;
        } catch (_) {}
      }

      if (context.mounted && mockNeeds.isNotEmpty) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => NeedDetailScreen(need: mockNeeds.first)));
        return;
      }
    }

    // C. FRIEND REQUEST RECEIVED -> Person Profile
    if (type == 'FRIEND_REQUEST_RECEIVED' || type.contains('FRIEND')) {
      final nameFromBody = notif.body.contains(' sent') ? notif.body.split(' sent').first : notif.title;
      if (refId != null && refId.isNotEmpty) {
        showLoading();
        try {
          final profilesApi = ref.read(profilesApiProvider);
          final user = await profilesApi.getById(refId);
          if (!context.mounted) return;
          Navigator.of(context).push(PersonScreen.route(
            name: user.displayName, initials: _initials(user.displayName),
            avatarColor: NeedHubTokens.forest, avatarUrl: user.avatarUrl, userId: user.id,
          ));
          return;
        } catch (_) {}
      }
      if (context.mounted) {
        Navigator.of(context).push(PersonScreen.route(
          name: nameFromBody, initials: _initials(nameFromBody), avatarColor: NeedHubTokens.forest, userId: refId,
        ));
        return;
      }
    }

    // D0. NeedHub Plus reward claim — additive, checked before the generic
    // REDEMPTION_READY branch below so real catalog redemptions (refType
    // 'REDEMPTION') are completely unaffected.
    if (refType == 'REWARD_CLAIM') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlusScreen()));
      return;
    }

    // D. REDEMPTION
    if (type == 'REDEMPTION_READY' || refType == 'REDEMPTION') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RedeemScreen()));
      return;
    }


    // E. IMPACT (REVIEW, POINTS, CERT, VOUCH) -> NON-CLICKABLE
    if (type == 'REVIEW_RECEIVED' || type == 'POINTS_AWARDED' || type.contains('CERT_') ||
        type == 'VOUCH_RECEIVED') {
      // User explicitly requested to make impact notifications non-clickable.
      return;
    }

    // F. Fallback
    if (refId != null && refId.isNotEmpty && context.mounted) {
      // Don't arbitrarily push screens if we don't know the ID type.
      // We do nothing instead of opening a buggy nameless screen.
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

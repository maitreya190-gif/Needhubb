import 'package:flutter/foundation.dart';
import '../services/friends_api.dart';
import '../services/chitchat_api.dart';
import '../services/notifications_api.dart';
import '../services/profiles_api.dart';

void resetAllUserNotifiersOnLogout() {
  pointsNotifier.value = 340;
  ratingsGivenNotifier.value = {};
  chitChatAvailableNotifier.value = false;
  customInterestsNotifier.value = [];
  customSkillsNotifier.value = [];
  friendsNotifier.value = {};
  blockedNotifier.value = {};
  friendUserIdsNotifier.value = {};
  blockedUserIdsNotifier.value = {};
  friendRequestsInboxNotifier.value = const [];
  friendRequestsOutboxNotifier.value = const [];
  friendRequestNotifier.value = 0;
  outgoingRequestUserIdsNotifier.value = {};
  chitchatAvailableUntilNotifier.value = null;
  chitchatRosterNotifier.value = const [];
  bioNotifier.value = "";
  promptSkillNotifier.value = "";
  promptCollabNotifier.value = "";
  promptNeedNotifier.value = "";
  genderNotifier.value = null;
  locationNotifier.value = '';
  avatarUrlNotifier.value = null;
  myProfileNotifier.value = null;
  notificationsListNotifier.value = const [];
  unreadCountNotifier.value = 0;
  earnFilterNotifier.value = const FeedFilter();
  connectFilterNotifier.value = const FeedFilter();
}

// Points balance (redeem deducts from here)
final pointsNotifier = ValueNotifier<int>(340);

// Ratings the current user has given: personName → stars (1-5)
final ratingsGivenNotifier = ValueNotifier<Map<String, int>>({});

// ChitChat availability toggle
final chitChatAvailableNotifier = ValueNotifier<bool>(false);

// Custom interests/skills added via Edit Profile
final customInterestsNotifier = ValueNotifier<List<String>>([]);
final customSkillsNotifier = ValueNotifier<List<String>>([]);

// Friends and blocked users — mutations from chat menu / connect detail.
// Legacy `Set<String>` stores display names for backwards-compat with mock UI.
// The `*UserIdsNotifier` variants hold real userIds hydrated from the API.
final friendsNotifier = ValueNotifier<Set<String>>({});
final blockedNotifier = ValueNotifier<Set<String>>({});
final friendUserIdsNotifier = ValueNotifier<Set<String>>({});
final blockedUserIdsNotifier = ValueNotifier<Set<String>>({});

// Pending friend requests hydrated from GET /friends/requests.
final friendRequestsInboxNotifier =
    ValueNotifier<List<FriendRequestDto>>(const []);
final friendRequestsOutboxNotifier =
    ValueNotifier<List<FriendRequestDto>>(const []);
// Cheap counter for UI badges (inbox length).
final friendRequestNotifier = ValueNotifier<int>(0);
// UserIds we've optimistically sent requests to (to disable "Add friend" instantly).
final outgoingRequestUserIdsNotifier = ValueNotifier<Set<String>>({});

// ChitChat availability + roster hydrated from the API.
final chitchatAvailableUntilNotifier = ValueNotifier<DateTime?>(null);
final chitchatRosterNotifier = ValueNotifier<List<ChitchatPerson>>(const []);

// Profile prompts + bio + gender + location
final bioNotifier = ValueNotifier<String>("");
final promptSkillNotifier = ValueNotifier<String>("");
final promptCollabNotifier = ValueNotifier<String>("");
final promptNeedNotifier = ValueNotifier<String>("");
final genderNotifier = ValueNotifier<String?>(null);
final locationNotifier = ValueNotifier<String>('');
final avatarUrlNotifier = ValueNotifier<String?>(null);
// Privacy: whether other users can see this account as "online" — mirrors
// Profile.showOnlineStatus on the server, toggled from Settings.
final showOnlineStatusNotifier = ValueNotifier<bool>(true);

// ── Actions ──────────────────────────────────────────────────────────────────

void submitRating(String personName, int stars) {
  final next = Map<String, int>.from(ratingsGivenNotifier.value);
  next[personName] = stars;
  ratingsGivenNotifier.value = next;
}

void deductPoints(int amount) {
  pointsNotifier.value = (pointsNotifier.value - amount).clamp(0, 999999);
}

void addCustomInterest(String label) {
  final v = label.trim();
  if (v.isEmpty) return;
  if (customInterestsNotifier.value.contains(v)) return;
  customInterestsNotifier.value = [...customInterestsNotifier.value, v];
}

void addCustomSkill(String label) {
  final v = label.trim();
  if (v.isEmpty) return;
  if (customSkillsNotifier.value.contains(v)) return;
  customSkillsNotifier.value = [...customSkillsNotifier.value, v];
}

// Name-based mutators are kept for legacy screens that don't yet have userIds.
// Screens that DO have userIds should call the *ById helpers below — those
// fire the real API and keep the userId notifiers in sync.

void addFriend(String name, {String? userId, FriendsApi? api}) {
  friendsNotifier.value = {...friendsNotifier.value, name};
  if (userId != null) {
    outgoingRequestUserIdsNotifier.value = {
      ...outgoingRequestUserIdsNotifier.value,
      userId,
    };
    api?.sendRequest(userId).catchError((_) {
      // Revert optimistic state on failure.
      outgoingRequestUserIdsNotifier.value = {
        ...outgoingRequestUserIdsNotifier.value,
      }..remove(userId);
      friendsNotifier.value = {...friendsNotifier.value}..remove(name);
    });
  }
}

void removeFriend(String name, {String? userId, FriendsApi? api}) {
  final next = {...friendsNotifier.value}..remove(name);
  friendsNotifier.value = next;
  if (userId != null) {
    final ids = {...friendUserIdsNotifier.value}..remove(userId);
    friendUserIdsNotifier.value = ids;
    api?.unfriend(userId).catchError((_) {
      // Revert if the API failed.
      friendsNotifier.value = {...friendsNotifier.value, name};
      friendUserIdsNotifier.value = {...friendUserIdsNotifier.value, userId};
    });
  }
}

void blockUser(String name, {String? userId, FriendsApi? api}) {
  blockedNotifier.value = {...blockedNotifier.value, name};
  if (friendsNotifier.value.contains(name)) removeFriend(name);
  if (userId != null) {
    blockedUserIdsNotifier.value = {...blockedUserIdsNotifier.value, userId};
    friendUserIdsNotifier.value = {...friendUserIdsNotifier.value}..remove(userId);
    api?.block(userId).catchError((_) {
      blockedNotifier.value = {...blockedNotifier.value}..remove(name);
      blockedUserIdsNotifier.value = {...blockedUserIdsNotifier.value}
        ..remove(userId);
    });
  }
}

void unblockUser(String name, {String? userId, FriendsApi? api}) {
  final next = {...blockedNotifier.value}..remove(name);
  blockedNotifier.value = next;
  if (userId != null) {
    blockedUserIdsNotifier.value = {...blockedUserIdsNotifier.value}
      ..remove(userId);
    api?.unblock(userId).catchError((_) {
      blockedNotifier.value = {...blockedNotifier.value, name};
      blockedUserIdsNotifier.value = {...blockedUserIdsNotifier.value, userId};
    });
  }
}

// ── Friend request actions (userId flow only) ────────────────────────────────

Future<void> acceptFriendRequest(String requestId, FriendsApi api) async {
  // Optimistic: drop from inbox.
  final inbox = [...friendRequestsInboxNotifier.value];
  final idx = inbox.indexWhere((r) => r.id == requestId);
  if (idx < 0) return;
  final req = inbox.removeAt(idx);
  friendRequestsInboxNotifier.value = inbox;
  friendRequestNotifier.value = inbox.length;
  friendUserIdsNotifier.value = {
    ...friendUserIdsNotifier.value,
    req.fromUserId,
  };
  try {
    await api.accept(requestId);
  } catch (e) {
    // Revert on failure.
    friendRequestsInboxNotifier.value = [req, ...inbox];
    friendRequestNotifier.value = friendRequestsInboxNotifier.value.length;
    friendUserIdsNotifier.value = {...friendUserIdsNotifier.value}
      ..remove(req.fromUserId);
      rethrow;
  }
}

Future<void> declineFriendRequest(String requestId, FriendsApi api) async {
  final inbox = [...friendRequestsInboxNotifier.value];
  final idx = inbox.indexWhere((r) => r.id == requestId);
  if (idx < 0) return;
  final req = inbox.removeAt(idx);
  friendRequestsInboxNotifier.value = inbox;
  friendRequestNotifier.value = inbox.length;
  try {
    await api.decline(requestId);
  } catch (e) {
    friendRequestsInboxNotifier.value = [req, ...inbox];
    friendRequestNotifier.value = friendRequestsInboxNotifier.value.length;
    rethrow;
  }
}

Future<void> cancelFriendRequest(String requestId, FriendsApi api) async {
  final outbox = [...friendRequestsOutboxNotifier.value];
  final idx = outbox.indexWhere((r) => r.id == requestId);
  if (idx < 0) return;
  final req = outbox.removeAt(idx);
  friendRequestsOutboxNotifier.value = outbox;
  outgoingRequestUserIdsNotifier.value = {...outgoingRequestUserIdsNotifier.value}
    ..remove(req.toUserId);
  try {
    await api.cancel(requestId);
  } catch (e) {
    friendRequestsOutboxNotifier.value = [req, ...outbox];
    outgoingRequestUserIdsNotifier.value = {
      ...outgoingRequestUserIdsNotifier.value,
      req.toUserId,
    };
    rethrow;
  }
}

// ── Social state hydration ──────────────────────────────────────────────────

/// Called on app start (after login) and on tab focus to keep the local
/// notifiers in sync with the API. Failures are logged and swallowed so the
/// app can still function offline.
Future<void> hydrateSocialState(FriendsApi friendsApi) async {
  await Future.wait([
    friendsApi.list().then((friends) {
      friendUserIdsNotifier.value = friends.map((f) => f.id).toSet();
    }).catchError((_) {}),
    friendsApi.listBlocks().then((blocks) {
      blockedUserIdsNotifier.value = blocks.map((b) => b.id).toSet();
    }).catchError((_) {}),
    friendsApi.listRequests().then((r) {
      friendRequestsInboxNotifier.value = r.inbox;
      friendRequestsOutboxNotifier.value = r.outbox;
      friendRequestNotifier.value = r.inbox.length;
      outgoingRequestUserIdsNotifier.value =
          r.outbox.map((x) => x.toUserId).toSet();
    }).catchError((_) {}),
  ]);
}

// Feed filter badge items for active chip bar
class FilterBadgeItem {
  final String id;
  final String label;
  final String type;

  const FilterBadgeItem({
    required this.id,
    required this.label,
    required this.type,
  });
}

// Feed filters
class FeedFilter {
  final double maxDistanceKm;
  final int? minBudget;
  final int? maxBudget;
  final Set<String>? _genders;
  final Set<String>? _interests;
  final Set<String>? _skills;
  final String? _sortBy;

  const FeedFilter({
    this.maxDistanceKm = 50,
    this.minBudget,
    this.maxBudget,
    Set<String>? genders,
    Set<String>? interests,
    Set<String>? skills,
    String? sortBy,
  })  : _genders = genders,
        _interests = interests,
        _skills = skills,
        _sortBy = sortBy;

  Set<String> get genders => _genders ?? const <String>{};
  Set<String> get interests => _interests ?? const <String>{};
  Set<String> get skills => _skills ?? const <String>{};
  String get sortBy => _sortBy ?? 'smart';

  FeedFilter copyWith({
    double? maxDistanceKm,
    int? minBudget,
    int? maxBudget,
    Set<String>? genders,
    Set<String>? interests,
    Set<String>? skills,
    String? sortBy,
    bool clearBudget = false,
  }) {
    return FeedFilter(
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      minBudget: clearBudget ? null : (minBudget ?? this.minBudget),
      maxBudget: clearBudget ? null : (maxBudget ?? this.maxBudget),
      genders: genders ?? this.genders,
      interests: interests ?? this.interests,
      skills: skills ?? this.skills,
      sortBy: sortBy ?? this.sortBy,
    );
  }

  List<FilterBadgeItem> get activeBadges {
    final list = <FilterBadgeItem>[];
    if (maxDistanceKm < 50) {
      list.add(FilterBadgeItem(
        id: 'distance',
        label: 'Within ${maxDistanceKm.toInt()} km',
        type: 'distance',
      ));
    }
    if (minBudget != null || maxBudget != null) {
      final minStr = minBudget != null ? '₹$minBudget' : '₹0';
      final maxStr = maxBudget != null ? '₹$maxBudget' : '∞';
      list.add(FilterBadgeItem(
        id: 'budget',
        label: 'Budget $minStr - $maxStr',
        type: 'budget',
      ));
    }
    for (final g in genders) {
      list.add(FilterBadgeItem(
        id: 'gender:$g',
        label: 'Gender: $g',
        type: 'gender',
      ));
    }
    for (final i in interests) {
      list.add(FilterBadgeItem(
        id: 'interest:$i',
        label: 'Interest: $i',
        type: 'interest',
      ));
    }
    for (final s in skills) {
      list.add(FilterBadgeItem(
        id: 'skill:$s',
        label: 'Skill: $s',
        type: 'skill',
      ));
    }
    if (sortBy == 'nearest') {
      list.add(const FilterBadgeItem(
        id: 'sort',
        label: 'Sort: Nearest',
        type: 'sort',
      ));
    } else if (sortBy == 'highest_points') {
      list.add(const FilterBadgeItem(
        id: 'sort',
        label: 'Sort: Highest Points',
        type: 'sort',
      ));
    } else if (sortBy == 'newest') {
      list.add(const FilterBadgeItem(
        id: 'sort',
        label: 'Sort: Newest',
        type: 'sort',
      ));
    }
    // 'smart' is the default AI-ranked order — not shown as a badge because
    // it is the baseline, and users don't need a chip reminding them nothing
    // is being overridden.
    return list;
  }

  FeedFilter removeBadge(FilterBadgeItem badge) {
    if (badge.type == 'distance') {
      return copyWith(maxDistanceKm: 50);
    }
    if (badge.type == 'budget') {
      return copyWith(clearBudget: true);
    }
    if (badge.type == 'gender') {
      final g = badge.id.substring(7);
      final next = {...genders}..remove(g);
      return copyWith(genders: next);
    }
    if (badge.type == 'interest') {
      final i = badge.id.substring(9);
      final next = {...interests}..remove(i);
      return copyWith(interests: next);
    }
    if (badge.type == 'skill') {
      final s = badge.id.substring(6);
      final next = {...skills}..remove(s);
      return copyWith(skills: next);
    }
    if (badge.type == 'sort') {
      return copyWith(sortBy: 'smart');
    }
    return this;
  }

  bool get isDefault => activeBadges.isEmpty;
  int get filterCount => activeBadges.length;
}

final earnFilterNotifier = ValueNotifier<FeedFilter>(const FeedFilter());
final connectFilterNotifier = ValueNotifier<FeedFilter>(const FeedFilter());

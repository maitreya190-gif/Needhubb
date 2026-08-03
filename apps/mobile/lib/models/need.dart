import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';

// Increment whenever mockNeeds or mockOffers changes so widgets can react.
final needsNotifier = ValueNotifier<int>(0);
final offersNotifier = ValueNotifier<int>(0);

class NeedOffer {
  final String name;
  final String initials;
  final String note;
  final String amount;
  final Color color;
  final String? responseId;
  final String? workSampleUrl;
  final DateTime? createdAt;

  const NeedOffer({
    required this.name,
    required this.initials,
    required this.note,
    required this.amount,
    required this.color,
    this.responseId,
    this.workSampleUrl,
    this.createdAt,
  });
}

// needId → list of offers submitted for that need
final Map<String, List<NeedOffer>> mockOffers = {
  'earn_1': [
    const NeedOffer(
      name: 'Aarav Kumar',
      initials: 'AK',
      note: 'I can deliver this laptop charger within 20 minutes.',
      amount: '₹400',
      color: Color(0xFF2E6B4E),
    ),
    const NeedOffer(
      name: 'Rohan Verma',
      initials: 'RV',
      note: 'Available right away! I live 200m away.',
      amount: '₹350',
      color: Color(0xFFB85D19),
    ),
  ],
  'earn_2': [
    const NeedOffer(
      name: 'Priya Nair',
      initials: 'PN',
      note:
          'I am a senior frontend engineer and can teach Flutter state management.',
      amount: '₹800',
      color: Color(0xFFC88719),
    ),
    const NeedOffer(
      name: 'Meera Kulkarni',
      initials: 'MK',
      note: 'I have 4 years experience with Flutter & Riverpod.',
      amount: '₹1,000',
      color: Color(0xFF2E6B4E),
    ),
  ],
  'connect_1': [
    const NeedOffer(
      name: 'Sneha Rao',
      initials: 'SR',
      note:
          'Would love to study system design and practice mock interviews together!',
      amount: 'Free',
      color: Color(0xFF2E6B4E),
    ),
  ],
};

class Need {
  final String id;
  final String posterId;
  final String title;
  final String description;
  final String category; // 'connect' | 'earn' | 'chitchat'
  final String authorName;
  final String authorInitials;
  final String location;
  final double? distanceKm;
  final DateTime createdAt;
  final int? budgetMin;
  final int? budgetMax;
  final List<String> tags;
  final String? posterGender;
  final String? posterAvatarUrl;
  final bool posterFaceVerified;
  final int posterTrustScore;
  /// Whether the poster holds an active NeedHub Plus subscription — derived
  /// server-side, see lib/plus.ts's isPlusActive. Cosmetic only; the actual
  /// (capped, moderate) ranking effect already happened before this need
  /// reached the client.
  final bool posterPlus;
  final int offerCount;
  final String? posterBio;
  final List<String> posterInterests;
  final Map<String, dynamic>? posterPersonalityTraits;
  final String? posterPersonalityNickname;
  final String status;
  final double? lat;
  final double? lng;

  /// Whether the poster marked this need as urgent. Off by default, and the
  /// only thing about Urgency Mode ever visible to anyone — the server never
  /// returns its internal confidence score. See lib/urgency.ts on the API.
  final bool isUrgent;
  final DateTime? deadline;
  final int peopleNeeded;
  final int acceptedCount;

  const Need({
    required this.id,
    this.posterId = '',
    required this.title,
    required this.description,
    required this.category,
    required this.authorName,
    required this.authorInitials,
    required this.location,
    this.distanceKm,
    required this.createdAt,
    this.budgetMin,
    this.budgetMax,
    this.tags = const [],
    this.posterGender,
    this.posterAvatarUrl,
    this.posterFaceVerified = false,
    this.posterTrustScore = 0,
    this.posterPlus = false,
    this.offerCount = 0,
    this.posterBio,
    this.posterInterests = const [],
    this.posterPersonalityTraits,
    this.posterPersonalityNickname,
    this.status = 'OPEN',
    this.lat,
    this.lng,
    this.isUrgent = false,
    this.deadline,
    this.peopleNeeded = 1,
    this.acceptedCount = 0,
  });

  Need copyWith({
    String? title,
    String? description,
    int? budgetMin,
    int? budgetMax,
    String? location,
    String? status,
    int? peopleNeeded,
    int? acceptedCount,
  }) =>
      Need(
        id: id,
        posterId: posterId,
        title: title ?? this.title,
        description: description ?? this.description,
        category: category,
        authorName: authorName,
        authorInitials: authorInitials,
        location: location ?? this.location,
        distanceKm: distanceKm,
        createdAt: createdAt,
        budgetMin: budgetMin ?? this.budgetMin,
        budgetMax: budgetMax ?? this.budgetMax,
        tags: tags,
        posterGender: posterGender,
        posterAvatarUrl: posterAvatarUrl,
        posterFaceVerified: posterFaceVerified,
        posterTrustScore: posterTrustScore,
        offerCount: offerCount,
        posterBio: posterBio,
        posterInterests: posterInterests,
        posterPersonalityTraits: posterPersonalityTraits,
        posterPersonalityNickname: posterPersonalityNickname,
        status: status ?? this.status,
        lat: lat,
        lng: lng,
        isUrgent: isUrgent,
        deadline: deadline,
        peopleNeeded: peopleNeeded ?? this.peopleNeeded,
        acceptedCount: acceptedCount ?? this.acceptedCount,
      );

  bool get isFullyFrozen => acceptedCount >= peopleNeeded || status.toUpperCase() != 'OPEN';
  bool get isFrozen => isFullyFrozen;
  String get freezeProgressLabel => '$acceptedCount/$peopleNeeded Frozen';
  bool get isExpiredUrgent => status.toUpperCase() == 'EXPIRED';

  /// Short "3h left" / "45m left" for an urgent need's deadline. Null once it
  /// has passed — callers should prefer isExpiredUrgent for that case.
  String? get urgencyCountdown {
    if (!isUrgent || deadline == null) return null;
    final remaining = deadline!.difference(DateTime.now());
    if (remaining.isNegative) return null;
    if (remaining.inHours >= 24) return '${remaining.inDays}d left';
    if (remaining.inHours >= 1) return '${remaining.inHours}h left';
    return '${remaining.inMinutes.clamp(1, 59)}m left';
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String get distanceLabel {
    if (distanceKm == null) return 'Nearby';
    if (distanceKm! < 1) return '${(distanceKm! * 1000).round()}m away';
    return '${distanceKm!.toStringAsFixed(1)}km away';
  }

  int get totalOfferCount {
    // The API is authoritative once the feed has loaded; the local entry keeps
    // a newly submitted offer visible before that count is refreshed.
    final localCount = (mockOffers[id] ?? []).length;
    return offerCount > localCount ? offerCount : localCount;
  }

  NeedOffer? get myOffer {
    final list = mockOffers[id] ?? [];
    final idx = list.indexWhere((o) => o.name == 'You' || o.initials == 'ME');
    return idx != -1 ? list[idx] : null;
  }

  bool get hasUserApplied => myOffer != null;
}

final List<Need> mockNeeds = [
  Need(
    id: 'n1',
    title: 'Looking for a Flutter developer to help fix layout bugs',
    description:
        'Need someone experienced with Flutter and Riverpod to quickly review my app layout and optimize UI widgets.',
    category: 'earn',
    authorName: 'Aarav Sharma',
    authorInitials: 'AS',
    location: 'Indiranagar, Bangalore',
    distanceKm: 1.2,
    createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
    budgetMin: 500,
    budgetMax: 1500,
    tags: ['flutter', 'dart', 'ui design'],
    posterGender: 'Male',
  ),
  Need(
    id: 'n2',
    title: 'Need a gym partner for morning workouts at Cult.fit',
    description:
        'Looking for an enthusiastic lifting buddy for heavy compound lifts (bench, squat, deadlift) at 7 AM.',
    category: 'connect',
    authorName: 'Priya Nair',
    authorInitials: 'PN',
    location: 'Koramangala, Bangalore',
    distanceKm: 0.8,
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    tags: ['lifting', 'fitness', 'gym'],
    posterGender: 'Female',
  ),
  Need(
    id: 'n3',
    title: 'Searching for a DSA mock interview partner',
    description:
        'Preparing for SDE-2 interviews. Looking to practice 2 LeetCode Medium problems daily and do peer mock interviews.',
    category: 'connect',
    authorName: 'Rohan Mehta',
    authorInitials: 'RM',
    location: 'HSR Layout, Bangalore',
    distanceKm: 2.5,
    createdAt: DateTime.now().subtract(const Duration(hours: 4)),
    tags: ['dsa', 'leetcode', 'interviews'],
    posterGender: 'Male',
  ),
  Need(
    id: 'n4',
    title: 'Need help moving heavy furniture across apartment building',
    description:
        'Need 1-2 people for 45 minutes to help move a sofa and dining table from 2nd to 4th floor.',
    category: 'earn',
    authorName: 'Ananya Verma',
    authorInitials: 'AV',
    location: 'Jayanagar, Bangalore',
    distanceKm: 3.1,
    createdAt: DateTime.now().subtract(const Duration(hours: 6)),
    budgetMin: 400,
    budgetMax: 800,
    tags: ['moving', 'help', 'manual labor'],
    posterGender: 'Female',
  ),
  Need(
    id: 'earn_1',
    title: 'Need someone to drop off my laptop charger in HSR Sector 2',
    description:
        'Left my Type-C charger at cafe, urgent drop off needed at HSR Sector 2 office.',
    category: 'earn',
    authorName: 'Vikram Seth',
    authorInitials: 'VS',
    location: 'HSR Layout · 0.8km',
    distanceKm: 0.8,
    createdAt: DateTime.now().subtract(const Duration(minutes: 35)),
    budgetMin: 350,
    budgetMax: 500,
    tags: ['delivery', 'urgent', 'tech'],
  ),
  Need(
    id: 'earn_2',
    title: 'Looking for a tutor for Flutter state management & Riverpod',
    description:
        'Need 2 hours of 1-on-1 practical hands-on guidance on Riverpod state management and architecture.',
    category: 'earn',
    authorName: 'Ananya Sharma',
    authorInitials: 'AS',
    location: 'Koramangala · 1.2km',
    distanceKm: 1.2,
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    budgetMin: 800,
    budgetMax: 1200,
    tags: ['flutter', 'tutor', 'coding'],
  ),
  Need(
    id: 'connect_1',
    title: 'Study buddy for System Design & Leetcode prep',
    description:
        'Preparing for tech interviews. Looking for someone to solve graph & DP problems with every evening.',
    category: 'connect',
    authorName: 'Rahul Patel',
    authorInitials: 'RP',
    location: 'Indiranagar · 1.5km',
    distanceKm: 1.5,
    createdAt: DateTime.now().subtract(const Duration(hours: 4)),
    tags: ['study', 'coding', 'leetcode'],
  ),
  Need(
    id: 'my_posted_1',
    title:
        'Looking for Flutter developer to collaborate on social open-source project',
    description:
        'Building a community app. Looking for interested Flutter developers to brainstorm & build features.',
    category: 'connect',
    authorName: 'You',
    authorInitials: 'ME',
    location: 'Nearby',
    createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    tags: ['flutter', 'open-source', 'community'],
  ),
];

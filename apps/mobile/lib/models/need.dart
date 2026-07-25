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

  const NeedOffer({
    required this.name,
    required this.initials,
    required this.note,
    required this.amount,
    required this.color,
  });
}

// needId → list of offers submitted for that need
final Map<String, List<NeedOffer>> mockOffers = {};

class Need {
  final String id;
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

  const Need({
    required this.id,
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
  });

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
    final userOffersCount = (mockOffers[id] ?? []).length;
    final base = category == 'earn' ? 2 : 0;
    return base + userOffersCount;
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
];

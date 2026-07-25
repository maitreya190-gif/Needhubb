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

// Mock feed data — replaced by real API in Phase 2
// Rule: budgetMin == null → connect (free), budgetMin != null → earn (paid)
final List<Need> mockNeeds = [
  Need(
    id: '1',
    title: 'Need a calculus tutor for 2 sessions',
    description: 'Struggling with integration by parts and series. Looking for someone patient who can explain clearly.',
    category: 'connect',
    authorName: 'Priya Sharma',
    authorInitials: 'PS',
    location: 'Koramangala',
    distanceKm: 0.8,
    createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
    tags: ['tutoring', 'maths', 'calculus'],
    posterGender: 'Female',
  ),
  Need(
    id: '2',
    title: 'Logo design for my food brand',
    description: 'Starting a homemade snacks business. Need a clean modern logo. Can pay ₹500–₹1500.',
    category: 'earn',
    authorName: 'Rohan Mehta',
    authorInitials: 'RM',
    location: 'Indiranagar',
    distanceKm: 1.4,
    createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    budgetMin: 500,
    budgetMax: 1500,
    tags: ['design', 'logo', 'freelance'],
    posterGender: 'Male',
  ),
  Need(
    id: '3',
    title: 'Study group for GATE 2026 — CS/IT',
    description: 'Forming a weekend study group at the public library. Targeting DS, Algorithms, and OS.',
    category: 'connect',
    authorName: 'Ananya Iyer',
    authorInitials: 'AI',
    location: 'HSR Layout',
    distanceKm: 2.1,
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    tags: ['study', 'GATE', 'CS'],
    posterGender: 'Female',
  ),
  Need(
    id: '4',
    title: 'Help needed moving furniture this weekend',
    description: 'Just 2 hours of help carrying boxes and a sofa. Will pay ₹300 + cover food.',
    category: 'earn',
    authorName: 'Karthik Nair',
    authorInitials: 'KN',
    location: 'BTM Layout',
    distanceKm: 3.2,
    createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    budgetMin: 300,
    tags: ['moving', 'help', 'physical'],
    posterGender: 'Male',
  ),
  Need(
    id: '5',
    title: 'React + Node dev needed for MVP build',
    description: 'Small startup building an MVP. Need someone for 10–15 hrs/week. Equity + stipend on offer.',
    category: 'earn',
    authorName: 'Sneha Rao',
    authorInitials: 'SR',
    location: 'Whitefield',
    distanceKm: 6.5,
    createdAt: DateTime.now().subtract(const Duration(hours: 8)),
    budgetMin: 8000,
    budgetMax: 15000,
    tags: ['dev', 'React', 'startup'],
    posterGender: 'Female',
  ),
  Need(
    id: '6',
    title: 'Photography gig — birthday party Sunday',
    description: '3-hour event at a venue in Jayanagar. Looking for someone with a decent DSLR or mirrorless.',
    category: 'earn',
    authorName: 'Dev Pillai',
    authorInitials: 'DP',
    location: 'Jayanagar',
    distanceKm: 4.0,
    createdAt: DateTime.now().subtract(const Duration(hours: 11)),
    budgetMin: 1000,
    budgetMax: 2000,
    tags: ['photography', 'event', 'gig'],
    posterGender: 'Male',
  ),
  Need(
    id: '7',
    title: 'Skill swap: guitar lessons for cooking lessons',
    description: 'I know guitar (5 yrs). Want to learn Indian cooking basics. Happy to swap sessions!',
    category: 'connect',
    authorName: 'Meera Krishnan',
    authorInitials: 'MK',
    location: 'Malleswaram',
    distanceKm: 5.3,
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
    tags: ['skill-swap', 'guitar', 'cooking'],
    posterGender: 'Female',
  ),
  Need(
    id: '8',
    title: 'Weekend hackathon — looking for teammates',
    description: 'InovaHack this weekend. Need a designer and a backend dev. Prizes worth ₹50k.',
    category: 'connect',
    authorName: 'Arjun Bhat',
    authorInitials: 'AB',
    location: 'Electronic City',
    distanceKm: 9.1,
    createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
    tags: ['hackathon', 'team', 'tech'],
  ),
];

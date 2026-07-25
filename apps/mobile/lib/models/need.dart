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

final List<Need> mockNeeds = [];

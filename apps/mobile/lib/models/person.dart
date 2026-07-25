import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class Person {
  final String id;
  final String name;
  final String initials;
  final Color avatarColor;
  final String location;
  final double distanceKm;
  final List<String> interests;
  final List<String> skills;
  final List<String> myInterests; // logged-in user's interests for overlap calc
  final String promptQ1;
  final String promptA1;
  final String promptQ2;
  final String promptA2;
  final String promptQ3;
  final String promptA3;
  final int reviewCount;
  final int points;
  final bool isOnline;
  final String? avatarUrl;
  final String? gender;

  const Person({
    required this.id,
    required this.name,
    required this.initials,
    required this.avatarColor,
    this.avatarUrl,
    this.gender,
    required this.location,
    required this.distanceKm,
    required this.interests,
    this.skills = const [],
    this.myInterests = const ['DSA', 'Coffee', 'Flutter', 'Startups'],
    required this.promptQ1,
    required this.promptA1,
    required this.promptQ2,
    required this.promptA2,
    required this.promptQ3,
    required this.promptA3,
    this.reviewCount = 0,
    this.points = 0,
    this.isOnline = false,
  });

  List<String> get sharedInterests =>
      interests.where((i) => myInterests.contains(i)).toList();

  List<String> get uniqueInterests =>
      interests.where((i) => !myInterests.contains(i)).toList();

  String get distanceLabel {
    if (distanceKm < 1) return '${(distanceKm * 1000).round()}m away';
    return '${distanceKm.toStringAsFixed(1)}km away';
  }
}

final List<Person> mockPeople = [];

Map<String, Person> get mockPersonLookup => {
      for (final p in mockPeople) p.name: p,
    };

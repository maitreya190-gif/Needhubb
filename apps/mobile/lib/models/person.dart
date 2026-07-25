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

  const Person({
    required this.id,
    required this.name,
    required this.initials,
    required this.avatarColor,
    required this.location,
    required this.distanceKm,
    required this.interests,
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

final List<Person> mockPeople = [
  const Person(
    id: 'p1',
    name: 'Aarav Menon',
    initials: 'AM',
    avatarColor: NeedHubTokens.forest,
    location: 'Koramangala',
    distanceKm: 0.5,
    interests: ['Lifting', 'Football', 'Anime', 'Startups'],
    promptQ1: "What I'm into right now",
    promptA1: 'Powerlifting 5 days a week and watching way too much anime.',
    promptQ2: "What I'm looking for",
    promptA2: 'A gym partner who won\'t skip leg day.',
    promptQ3: 'Ask me about',
    promptA3: 'Football tactics or starting a side project.',
    reviewCount: 8,
    points: 280,
    isOnline: true,
  ),
  const Person(
    id: 'p2',
    name: 'Meera Kulkarni',
    initials: 'MK',
    avatarColor: NeedHubTokens.clay,
    location: 'Indiranagar',
    distanceKm: 1.2,
    interests: ['DSA', 'Coffee', 'Sketching'],
    promptQ1: "What I'm into right now",
    promptA1: 'Grinding LeetCode and drawing during study breaks.',
    promptQ2: "What I'm looking for",
    promptA2: 'A DSA study partner — consistent, not just when exams hit.',
    promptQ3: 'Ask me about',
    promptA3: 'Graph algorithms or the best coffee shops in Indiranagar.',
    reviewCount: 12,
    points: 510,
    isOnline: true,
  ),
  const Person(
    id: 'p3',
    name: 'Rohan Thapar',
    initials: 'RT',
    avatarColor: NeedHubTokens.ochre,
    location: 'HSR Layout',
    distanceKm: 2.3,
    interests: ['Trekking', 'Photography', 'Guitar'],
    promptQ1: "What I'm into right now",
    promptA1: 'Planning a weekend trek and learning fingerstyle guitar.',
    promptQ2: "What I'm looking for",
    promptA2: 'Someone to trek Nandi Hills with next weekend.',
    promptQ3: 'Ask me about',
    promptA3: 'Camera settings or trail recommendations around Bangalore.',
    reviewCount: 5,
    points: 190,
    isOnline: false,
  ),
  const Person(
    id: 'p4',
    name: 'Ananya Sethi',
    initials: 'AS',
    avatarColor: NeedHubTokens.forest,
    location: 'BTM Layout',
    distanceKm: 3.1,
    interests: ['Flutter', 'DSA', 'Coffee', 'Startups'],
    promptQ1: "What I'm into right now",
    promptA1: 'Building a Flutter app and making espresso at home.',
    promptQ2: "What I'm looking for",
    promptA2: 'A dev partner for hackathons — ideally full-stack.',
    promptQ3: 'Ask me about',
    promptA3: 'State management in Flutter or cold brew ratios.',
    reviewCount: 19,
    points: 760,
    isOnline: false,
  ),
  const Person(
    id: 'p5',
    name: 'Kabir Deshmukh',
    initials: 'KD',
    avatarColor: NeedHubTokens.clay,
    location: 'Jayanagar',
    distanceKm: 4.8,
    interests: ['Movies', 'Anime', 'Chess'],
    promptQ1: "What I'm into right now",
    promptA1: 'Rewatching Evangelion and playing Rapid chess online.',
    promptQ2: "What I'm looking for",
    promptA2: 'An over-the-board chess partner at roughly 1400 ELO.',
    promptQ3: 'Ask me about',
    promptA3: 'Film recommendations or chess openings.',
    reviewCount: 3,
    points: 95,
    isOnline: true,
  ),
];

/// Fast name → Person lookup for profile views in chats / conversation screen
final Map<String, Person> mockPersonLookup = {
  for (final p in mockPeople) p.name: p,
};

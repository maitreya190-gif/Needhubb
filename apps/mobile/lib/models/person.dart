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

final List<Person> mockPeople = [
  const Person(
    id: 'p1',
    name: 'Aarav Sharma',
    initials: 'AS',
    avatarColor: NeedHubTokens.forest,
    gender: 'Male',
    location: 'Indiranagar, Bangalore',
    distanceKm: 1.2,
    interests: ['DSA', 'Flutter', 'Coffee', 'Startups'],
    skills: ['Flutter', 'Dart', 'UI Design'],
    promptQ1: "THE SKILL I'D LOVE TO TEACH",
    promptA1: 'Flutter UI architecture and state management with Riverpod.',
    promptQ2: 'MY IDEAL COLLAB',
    promptA2: 'Building open-source mobile tools and hackathon projects.',
    promptQ3: "THE NEED I'D POST RIGHT NOW",
    promptA3: 'Looking for someone to review app performance on real devices.',
    reviewCount: 8,
    points: 340,
    isOnline: true,
  ),
  const Person(
    id: 'p2',
    name: 'Priya Nair',
    initials: 'PN',
    avatarColor: NeedHubTokens.clay,
    gender: 'Female',
    location: 'Koramangala, Bangalore',
    distanceKm: 0.8,
    interests: ['Lifting', 'Trekking', 'Coffee', 'Photography'],
    skills: ['Fitness Coaching', 'Photography', 'Math tutoring'],
    promptQ1: "THE SKILL I'D LOVE TO TEACH",
    promptA1: 'Proper deadlift & squat form for heavy strength training.',
    promptQ2: 'MY IDEAL COLLAB',
    promptA2: 'Weekend sunrise trekking and outdoor fitness workouts.',
    promptQ3: "THE NEED I'D POST RIGHT NOW",
    promptA3: 'Gym partner for morning 7 AM strength sessions at Cult.fit.',
    reviewCount: 14,
    points: 520,
    isOnline: true,
  ),
  const Person(
    id: 'p3',
    name: 'Rohan Mehta',
    initials: 'RM',
    avatarColor: NeedHubTokens.ochre,
    gender: 'Male',
    location: 'HSR Layout, Bangalore',
    distanceKm: 2.5,
    interests: ['DSA', 'Chess', 'Anime', 'Startups'],
    skills: ['Python', 'Java', 'DSA tutoring'],
    promptQ1: "THE SKILL I'D LOVE TO TEACH",
    promptA1: 'Graphs, Dynamic Programming, and System Design concepts.',
    promptQ2: 'MY IDEAL COLLAB',
    promptA2: 'Daily LeetCode problem solving and mock technical interviews.',
    promptQ3: "THE NEED I'D POST RIGHT NOW",
    promptA3: 'Peer mock interviewer for SDE-2 coding interview prep.',
    reviewCount: 5,
    points: 210,
    isOnline: false,
  ),
  const Person(
    id: 'p4',
    name: 'Ananya Verma',
    initials: 'AV',
    avatarColor: NeedHubTokens.forest,
    gender: 'Female',
    location: 'Jayanagar, Bangalore',
    distanceKm: 3.1,
    interests: ['Guitar', 'Movies', 'Sketching', 'Coffee'],
    skills: ['Guitar lessons', 'UI Design', 'Writing'],
    promptQ1: "THE SKILL I'D LOVE TO TEACH",
    promptA1: 'Acoustic guitar fingerpicking and music theory basics.',
    promptQ2: 'MY IDEAL COLLAB',
    promptA2: 'Jamming sessions and composing indie acoustic tracks.',
    promptQ3: "THE NEED I'D POST RIGHT NOW",
    promptA3: 'Someone to help test my web app prototype.',
    reviewCount: 11,
    points: 410,
    isOnline: true,
  ),
];

Map<String, Person> get mockPersonLookup => {
      for (final p in mockPeople) p.name: p,
    };

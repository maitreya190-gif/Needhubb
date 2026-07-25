import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class FriendRequest {
  final String fromName;
  final String fromInitials;
  final Color fromColor;
  bool accepted;
  bool declined;

  FriendRequest({
    required this.fromName,
    required this.fromInitials,
    required this.fromColor,
    this.accepted = false,
    this.declined = false,
  });
}

final mockIncomingRequests = [
  FriendRequest(fromName: 'Anika Patel', fromInitials: 'AP', fromColor: NeedHubTokens.forest),
  FriendRequest(fromName: 'Karan Joshi', fromInitials: 'KJ', fromColor: NeedHubTokens.ochre),
];

// friendRequestNotifier is defined in user_state.dart — hydrated from the API.

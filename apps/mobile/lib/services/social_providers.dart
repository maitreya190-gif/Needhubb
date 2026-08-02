import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'chitchat_api.dart';
import 'friends_api.dart';
import 'messaging_api.dart';
import 'needs_api.dart';
import 'notifications_api.dart';
import 'personality_api.dart';
import 'profiles_api.dart';
import 'redemptions_api.dart';
import 'reviews_api.dart';
import 'uploads_api.dart';
import 'vouches_api.dart';

final friendsApiProvider = Provider<FriendsApi>((ref) {
  return FriendsApi(ref.watch(apiClientProvider));
});

final chitchatApiProvider = Provider<ChitchatApi>((ref) {
  return ChitchatApi(ref.watch(apiClientProvider));
});

final needsApiProvider = Provider<NeedsApi>((ref) {
  return NeedsApi(ref.watch(apiClientProvider));
});

final notificationsApiProvider = Provider<NotificationsApi>((ref) {
  return NotificationsApi(ref.watch(apiClientProvider));
});

final profilesApiProvider = Provider<ProfilesApi>((ref) {
  return ProfilesApi(ref.watch(apiClientProvider));
});

final vouchesApiProvider = Provider<VouchesApi>((ref) {
  return VouchesApi(ref.watch(apiClientProvider));
});

final personalityApiProvider = Provider<PersonalityApi>((ref) {
  return PersonalityApi(ref.watch(apiClientProvider));
});

final redemptionsApiProvider = Provider<RedemptionsApi>((ref) {
  return RedemptionsApi(ref.watch(apiClientProvider));
});

final reviewsApiProvider = Provider<ReviewsApi>((ref) {
  return ReviewsApi(ref.watch(apiClientProvider));
});

final messagingApiProvider = Provider<MessagingApi>((ref) {
  return MessagingApi(ref.watch(apiClientProvider));
});

final uploadsApiProvider = Provider<UploadsApi>((ref) {
  return UploadsApi(ref.watch(apiClientProvider));
});

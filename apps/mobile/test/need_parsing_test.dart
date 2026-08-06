// Parsing regressions for the feed payload.
//
// The gender filter silently emptied the whole feed in production because
// `posterGender` was never read out of the API response, so every need looked
// genderless and `passesHardFilters` rejected all of them. The API had always
// sent it — only the client mapping was missing.

import 'package:flutter_test/flutter_test.dart';
import 'package:needhub/services/needs_api.dart';

Map<String, dynamic> payload({
  String? gender,
  List<Map<String, dynamic>>? interests,
  List<String>? tags,
}) =>
    {
      'id': 'n1',
      'title': 'Need a Flutter dev',
      'description': 'Build a screen',
      'needType': 'EARN',
      'status': 'OPEN',
      'createdAt': '2026-03-01T10:00:00.000Z',
      'budgetMin': 500,
      'budgetMax': 2000,
      if (tags != null) 'tags': tags,
      'poster': {
        'id': 'u1',
        'displayName': 'Asha Rao',
        'profile': {
          'avatarUrl': null,
          'bio': 'dev',
          if (gender != null) 'gender': gender,
          if (interests != null) 'interests': interests,
        },
      },
    };

void main() {
  group('poster gender', () {
    test('is read from the API response', () {
      final need = needFromSocketData(payload(gender: 'Female'));
      expect(need.posterGender, 'Female');
    });

    test('stays null when the poster never set one', () {
      final need = needFromSocketData(payload());
      expect(need.posterGender, isNull);
    });

    test('is preserved verbatim for hyphenated values', () {
      final need = needFromSocketData(payload(gender: 'Non-binary'));
      expect(need.posterGender, 'Non-binary');
    });
  });

  group('other filter inputs survive parsing', () {
    test('budget range is read so range filters can work', () {
      final need = needFromSocketData(payload());
      expect(need.budgetMin, 500);
      expect(need.budgetMax, 2000);
    });

    test('server tags are read so topic chips can match', () {
      final need = needFromSocketData(payload(tags: ['Flutter', 'Dev']));
      expect(need.tags, containsAll(<String>['Flutter', 'Dev']));
    });

    test('poster interests are flattened out of the nested join rows', () {
      final need = needFromSocketData(payload(interests: [
        {
          'interest': {'label': 'Chess'}
        },
      ]));
      expect(need.posterInterests, ['Chess']);
    });
  });
}

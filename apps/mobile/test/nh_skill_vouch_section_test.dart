// Widget tests for the skill-vouch display section.
//
// Everything rendered here is exactly what the server sent — no credibility
// weight, no AI reasoning ever reaches this widget in the first place, so
// there is nothing to accidentally leak. What matters here is layout (a
// profile with several skills and testimonials is the realistic case most
// likely to overflow) and that the Vouch/Edit action only appears when a
// callback is actually supplied — never on your own profile.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needhub/services/profiles_api.dart';
import 'package:needhub/services/vouches_api.dart';
import 'package:needhub/theme/tokens.dart';
import 'package:needhub/widgets/nh_skill_vouch_section.dart';

Widget wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 380, child: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  const t = NeedHubThemes.paper;

  group('empty and populated states', () {
    testWidgets('shows an empty-state message with no skills', (tester) async {
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: const [],
        skillVouches: const {},
        t: t,
      )));
      expect(find.textContaining('No skills listed'), findsOneWidget);
    });

    testWidgets('a skill with zero vouches reads "No vouches yet"',
        (tester) async {
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: const [SkillEntry(id: 's1', label: 'Flutter')],
        skillVouches: const {},
        t: t,
      )));
      expect(find.text('Flutter'), findsOneWidget);
      expect(find.text('No vouches yet'), findsOneWidget);
    });

    testWidgets('shows the vouch count and pluralizes correctly',
        (tester) async {
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: const [SkillEntry(id: 's1', label: 'Flutter')],
        skillVouches: {
          's1': const SkillVouchSummary(
            skillId: 's1',
            label: 'Flutter',
            vouchCount: 3,
            verifiedVouchCount: 0,
            recentVouchers: [],
          ),
        },
        t: t,
      )));
      expect(find.text('3 vouches'), findsOneWidget);
    });

    testWidgets('a full profile of several skills with testimonials lays out without overflow',
        (tester) async {
      final skills = List.generate(
          6, (i) => SkillEntry(id: 's$i', label: 'Skill number $i'));
      final vouches = {
        for (final s in skills)
          s.id: SkillVouchSummary(
            skillId: s.id,
            label: s.label,
            vouchCount: 4,
            verifiedVouchCount: 2,
            recentVouchers: List.generate(
              4,
              (j) => RecentVoucher(
                voucherId: 'v$j',
                voucherName: 'Voucher Number $j',
                verified: j.isEven,
                testimonial: 'A genuinely useful and detailed testimonial here.',
                createdAt: DateTime.now(),
              ),
            ),
          ),
      };
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: skills,
        skillVouches: vouches,
        t: t,
      )));
      expect(tester.takeException(), isNull);
    });
  });

  group('the Verified badge', () {
    testWidgets('appears when at least one vouch is verified', (tester) async {
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: const [SkillEntry(id: 's1', label: 'Flutter')],
        skillVouches: {
          's1': const SkillVouchSummary(
            skillId: 's1',
            label: 'Flutter',
            vouchCount: 1,
            verifiedVouchCount: 1,
            recentVouchers: [],
          ),
        },
        t: t,
      )));
      expect(find.text('Verified'), findsOneWidget);
    });

    testWidgets('does not appear when no vouch is verified', (tester) async {
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: const [SkillEntry(id: 's1', label: 'Flutter')],
        skillVouches: {
          's1': const SkillVouchSummary(
            skillId: 's1',
            label: 'Flutter',
            vouchCount: 2,
            verifiedVouchCount: 0,
            recentVouchers: [],
          ),
        },
        t: t,
      )));
      expect(find.text('Verified'), findsNothing);
    });
  });

  group('the vouch/edit action', () {
    testWidgets('is absent when no onVouch callback is supplied — own profile',
        (tester) async {
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: const [SkillEntry(id: 's1', label: 'Flutter')],
        skillVouches: const {},
        t: t,
      )));
      expect(find.text('Vouch'), findsNothing);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('reads "Vouch" when the viewer has not vouched yet',
        (tester) async {
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: const [SkillEntry(id: 's1', label: 'Flutter')],
        skillVouches: const {},
        t: t,
        onVouch: (_, __) {},
      )));
      expect(find.text('Vouch'), findsOneWidget);
    });

    testWidgets('reads "Edit" when the viewer already vouched for this skill',
        (tester) async {
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: const [SkillEntry(id: 's1', label: 'Flutter')],
        skillVouches: const {},
        t: t,
        myVouchIdsBySkill: const {'s1': 'vouch-1'},
        onVouch: (_, __) {},
      )));
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Vouch'), findsNothing);
    });

    testWidgets('tapping calls back with the skill and the existing vouch id',
        (tester) async {
      SkillEntry? tappedSkill;
      String? tappedVouchId;
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: const [SkillEntry(id: 's1', label: 'Flutter')],
        skillVouches: const {},
        t: t,
        myVouchIdsBySkill: const {'s1': 'vouch-1'},
        onVouch: (skill, vouchId) {
          tappedSkill = skill;
          tappedVouchId = vouchId;
        },
      )));
      await tester.tap(find.text('Edit'));
      await tester.pump();
      expect(tappedSkill?.id, 's1');
      expect(tappedVouchId, 'vouch-1');
    });
  });

  group('expanding testimonials', () {
    testWidgets('a skill with testimonials is expandable and shows them',
        (tester) async {
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: const [SkillEntry(id: 's1', label: 'Flutter')],
        skillVouches: {
          's1': SkillVouchSummary(
            skillId: 's1',
            label: 'Flutter',
            vouchCount: 1,
            verifiedVouchCount: 0,
            recentVouchers: [
              RecentVoucher(
                voucherId: 'v1',
                voucherName: 'Aarav',
                verified: false,
                testimonial: 'Great to work with.',
                createdAt: DateTime.now(),
              ),
            ],
          ),
        },
        t: t,
      )));

      expect(find.text('Great to work with.'), findsNothing); // collapsed
      await tester.tap(find.text('Flutter'));
      await tester.pumpAndSettle();
      expect(find.text('Aarav'), findsOneWidget);
      expect(find.textContaining('Great to work with.'), findsOneWidget);
    });

    testWidgets('has no expand/collapse chevron icon, even when expandable',
        (tester) async {
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: const [SkillEntry(id: 's1', label: 'Flutter')],
        skillVouches: {
          's1': SkillVouchSummary(
            skillId: 's1',
            label: 'Flutter',
            vouchCount: 1,
            verifiedVouchCount: 0,
            recentVouchers: [
              RecentVoucher(
                voucherId: 'v1',
                voucherName: 'Aarav',
                verified: false,
                testimonial: 'Great to work with.',
                createdAt: DateTime.now(),
              ),
            ],
          ),
        },
        t: t,
      )));

      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);
    });
  });

  group('skill ordering', () {
    testWidgets('vouched-for skills render before ones with no vouches, order otherwise preserved',
        (tester) async {
      await tester.pumpWidget(wrap(NhSkillVouchSection(
        skills: const [
          SkillEntry(id: 's1', label: 'Alpha'),
          SkillEntry(id: 's2', label: 'Beta'),
          SkillEntry(id: 's3', label: 'Gamma'),
          SkillEntry(id: 's4', label: 'Delta'),
        ],
        skillVouches: {
          's3': const SkillVouchSummary(
            skillId: 's3', label: 'Gamma', vouchCount: 2, verifiedVouchCount: 0, recentVouchers: [],
          ),
          's4': const SkillVouchSummary(
            skillId: 's4', label: 'Delta', vouchCount: 0, verifiedVouchCount: 0, recentVouchers: [],
          ),
        },
        t: t,
      )));

      final labels = tester
          .widgetList<Text>(find.descendant(
            of: find.byType(NhSkillVouchSection),
            matching: find.byType(Text),
          ))
          .map((w) => w.data)
          .whereType<String>()
          .where((s) => ['Alpha', 'Beta', 'Gamma', 'Delta'].contains(s))
          .toList();

      // Gamma has vouches (moves to front); Delta has an explicit zero-vouch
      // entry (stays put); Alpha/Beta have no entry at all (stay put, in
      // their original relative order).
      expect(labels, ['Gamma', 'Alpha', 'Beta', 'Delta']);
    });
  });
}

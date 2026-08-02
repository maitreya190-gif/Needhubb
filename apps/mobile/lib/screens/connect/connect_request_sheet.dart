import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/person.dart';
import '../../theme/tokens.dart';
import '../../../l10n/app_strings.dart';

class ConnectRequestSheet extends StatefulWidget {
  final Person person;

  const ConnectRequestSheet({super.key, required this.person});

  @override
  State<ConnectRequestSheet> createState() => _ConnectRequestSheetState();
}

class _ConnectRequestSheetState extends State<ConnectRequestSheet> {
  final _noteController = TextEditingController();
  String? _selectedActivity;
  bool _sent = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 20),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: _sent ? _SuccessView(person: widget.person, t: t) : _FormView(
        person: widget.person,
        t: t,
        noteController: _noteController,
        selectedActivity: _selectedActivity,
        onActivitySelected: (a) => setState(() => _selectedActivity = a),
        onSend: () => setState(() => _sent = true),
      ),
    );
  }
}

class _FormView extends StatelessWidget {
  final Person person;
  final NeedHubTokens t;
  final TextEditingController noteController;
  final String? selectedActivity;
  final ValueChanged<String> onActivitySelected;
  final VoidCallback onSend;

  const _FormView({
    required this.person,
    required this.t,
    required this.noteController,
    required this.selectedActivity,
    required this.onActivitySelected,
    required this.onSend,
  });

  static const _activitiesEn = ['Study together', 'Grab a coffee', 'Pair up', 'Trek'];
  static List<String> _activityLabels() => [
        S.current.activityStudy,
        S.current.activityCoffee,
        S.current.activityPairUp,
        S.current.activityTrek,
      ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Handle
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: t.rail,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),

        Text(
          S.current.sendConnectRequest,
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'to ${person.name}',
          style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
        ),
        const SizedBox(height: 20),

        // Activity idea chips
        Text(
          S.current.suggestAnActivity,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: t.muted2,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 10),
        Builder(builder: (context) {
          final labels = _activityLabels();
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_activitiesEn.length, (i) {
              final englishValue = _activitiesEn[i];
              final displayLabel = labels[i];
              final active = selectedActivity == englishValue;
              return GestureDetector(
                onTap: () => onActivitySelected(englishValue),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: active
                        ? NeedHubTokens.forest.withValues(alpha: 0.12)
                        : t.paper,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: active ? NeedHubTokens.forest : t.rail,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    displayLabel,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? NeedHubTokens.forest : t.muted2,
                    ),
                  ),
                ),
              );
            }),
          );
        }),
        const SizedBox(height: 16),

        // Note
        Text(
          S.current.addANote,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: t.muted2,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: t.paper,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: t.rail, width: 1.5),
          ),
          child: TextField(
            controller: noteController,
            minLines: 3,
            maxLines: 5,
            style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
            decoration: InputDecoration(
              hintText: '${S.current.connectNoteHint} ${person.sharedInterests.isNotEmpty ? person.sharedInterests.first : "have similar interests"}…',
              hintStyle: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(14),
              filled: false,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Safety hint
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NeedHubTokens.forest.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined,
                  size: 16, color: NeedHubTokens.forest),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.current.connectSafetyTip,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    color: NeedHubTokens.forest,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onSend,
            style: ElevatedButton.styleFrom(
              backgroundColor: NeedHubTokens.forest,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              textStyle: GoogleFonts.bricolageGrotesque(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
            child: Text(S.current.sendRequest),
          ),
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  final Person person;
  final NeedHubTokens t;

  const _SuccessView({required this.person, required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: NeedHubTokens.forest.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.check_rounded,
              color: NeedHubTokens.forest, size: 30),
        ),
        const SizedBox(height: 16),
        Text(
          S.current.requestSent,
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${person.name} ${S.current.requestSentDesc}',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 14,
            color: t.muted,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.current.done,
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

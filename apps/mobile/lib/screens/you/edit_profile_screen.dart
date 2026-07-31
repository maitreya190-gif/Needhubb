import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/user_state.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/profiles_api.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_avatar.dart';
import '../../widgets/nh_button.dart';
import '../../widgets/nh_text_field.dart';
import '../auth/location_picker_screen.dart';

const _interestOptions = [
  'Lifting', 'Football', 'Cricket', 'DSA', 'Coffee', 'Trekking',
  'Photography', 'Guitar', 'Flutter', 'Movies', 'Anime', 'Chess',
  'Sketching', 'Startups', 'Running', 'Cooking',
];

const _skillOptions = [
  'Java', 'Python', 'Flutter', 'UI Design', 'Writing', 'Math tutoring',
  'Video editing', 'Note-taking', 'Guitar lessons', 'Proofreading',
  'Tutoring', 'Web Dev', 'Design',
];

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _bioController;
  late TextEditingController _locationController;
  late TextEditingController _promptSkillController;
  late TextEditingController _promptCollabController;
  late TextEditingController _promptNeedController;
  String? _gender;

  final Set<String> _selectedInterests = {
    'DSA', 'Coffee', 'Flutter', 'Startups', 'Photography',
  };
  final Set<String> _selectedSkills = {
    'Tutoring', 'Web Dev', 'Design',
  };
  String? _avatarPath;
  bool _saving = false;
  bool _locating = false;

  Future<void> _openMapPicker() async {
    final result = await Navigator.of(context).push<LocationPickResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const LocationPickerScreen(),
      ),
    );
    if (result != null && mounted) {
      setState(() => _locationController.text = result.label);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Please enable location services.')));
        }
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Location permission was denied.')));
        }
        return;
      }
      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition();
        pos ??= await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.lowest,
          timeLimit: const Duration(seconds: 3),
        );
      } catch (e) {
        if (e.toString().contains('TimeoutException')) {
          pos = Position(
            latitude: 19.0760,
            longitude: 72.8777,
            timestamp: DateTime.now(),
            accuracy: 100,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        } else {
          rethrow;
        }
      }
      
      if (!mounted) return;

      final bool? isExact = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'Location Precision',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Do you want to share your exact location or an approximate 2km radius locality?',
            style: GoogleFonts.hankenGrotesk(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('2km Radius',
                  style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB85C38)),
              child: Text('Exact Location',
                  style: GoogleFonts.hankenGrotesk(
                      fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      );

      if (isExact == null) return;

      String shortLabel = '';
      try {
        final res = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 5))).get(
          'https://nominatim.openstreetmap.org/reverse',
          queryParameters: {
            'format': 'json',
            'lat': pos.latitude,
            'lon': pos.longitude,
            'zoom': 14,
          },
          options: Options(headers: {'User-Agent': 'NeedhubApp/1.0'}),
        );
        if (res.data != null && res.data['display_name'] != null) {
          final address = res.data['address'] as Map<String, dynamic>?;
          shortLabel = res.data['display_name'];
          if (address != null) {
            final city = address['city'] ?? address['town'] ?? address['village'] ?? address['county'];
            final state = address['state'];
            final suburb = address['suburb'] ?? address['neighbourhood'];
            if (suburb != null && city != null) {
              shortLabel = '$suburb, $city';
            } else if (city != null && state != null) {
              shortLabel = '$city, $state';
            }
          }
        }
      } catch (_) {}

      if (shortLabel.isEmpty) {
        final lat = pos.latitude.toStringAsFixed(3);
        final lon = pos.longitude.toStringAsFixed(3);
        shortLabel = 'Lat $lat, Lon $lon';
      }

      final label = isExact ? shortLabel : '$shortLabel (Approx)';

      if (!mounted) return;
      setState(() {
        _locationController.text = label;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not fetch location: $e')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    _nameController = TextEditingController(text: auth.displayName ?? '');
    _bioController = TextEditingController(text: bioNotifier.value);
    _locationController =
        TextEditingController(text: locationNotifier.value);
    _promptSkillController =
        TextEditingController(text: promptSkillNotifier.value);
    _promptCollabController =
        TextEditingController(text: promptCollabNotifier.value);
    _promptNeedController =
        TextEditingController(text: promptNeedNotifier.value);
    _gender = genderNotifier.value;

    final currentInterests = myProfileNotifier.value?.interestLabels.isNotEmpty == true
        ? myProfileNotifier.value!.interestLabels
        : customInterestsNotifier.value;
    if (currentInterests.isNotEmpty) {
      _selectedInterests.clear();
      _selectedInterests.addAll(currentInterests);
    }

    final currentSkills = myProfileNotifier.value?.skillLabels.isNotEmpty == true
        ? myProfileNotifier.value!.skillLabels
        : customSkillsNotifier.value;
    if (currentSkills.isNotEmpty) {
      _selectedSkills.clear();
      _selectedSkills.addAll(currentSkills);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _promptSkillController.dispose();
    _promptCollabController.dispose();
    _promptNeedController.dispose();
    super.dispose();
  }

  Future<void> _promptAdd(BuildContext context, {required bool isSkill}) async {
    final label = isSkill ? 'skill' : 'interest';
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddOtherSheet(
        label: label,
        hint: isSkill ? 'e.g. Public speaking' : 'e.g. Board games',
      ),
    );
    if (!mounted) return;
    final trimmed = result?.trim() ?? '';
    if (trimmed.isEmpty) return;
    if (isSkill) {
      addCustomSkill(trimmed);
      setState(() => _selectedSkills.add(trimmed));
    } else {
      addCustomInterest(trimmed);
      setState(() => _selectedInterests.add(trimmed));
    }
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop photo',
          toolbarColor: const Color(0xFFB85C38),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFB85C38),
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Crop photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped != null && mounted) {
      setState(() => _avatarPath = cropped.path);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    // Update local profile state immediately so edits/interests reflect instantly on profile
    customInterestsNotifier.value = _selectedInterests.toList();
    customSkillsNotifier.value = _selectedSkills.toList();
    bioNotifier.value = _bioController.text.trim();
    if (_locationController.text.trim().isNotEmpty) {
      locationNotifier.value = _locationController.text.trim();
    }
    if (_promptSkillController.text.trim().isNotEmpty) {
      promptSkillNotifier.value = _promptSkillController.text.trim();
    }
    if (_promptCollabController.text.trim().isNotEmpty) {
      promptCollabNotifier.value = _promptCollabController.text.trim();
    }
    if (_promptNeedController.text.trim().isNotEmpty) {
      promptNeedNotifier.value = _promptNeedController.text.trim();
    }
    genderNotifier.value = _gender;
    if (_avatarPath != null) {
      avatarUrlNotifier.value = _avatarPath;
    }

    try {
      final api = ref.read(apiClientProvider);

      // Upload avatar first if a new one was picked
      if (_avatarPath != null) {
        try {
          final form = FormData.fromMap({
            'file': await MultipartFile.fromFile(
              _avatarPath!,
              filename: _avatarPath!.split('/').last,
            ),
          });
          final res = await api.postForm('/profile/me/avatar', form);
          avatarUrlNotifier.value = res['avatarUrl'] as String? ?? avatarUrlNotifier.value;
        } catch (e) {
          debugPrint('Avatar upload warning: $e');
        }
      }

      // Sync with backend API
      try {
        final profilesApi = ProfilesApi(api);
        final updated = await profilesApi.update(
          bio: _bioController.text.trim(),
          gender: _gender,
          location: _locationController.text.trim(),
          promptSkill: _promptSkillController.text.trim(),
          promptCollab: _promptCollabController.text.trim(),
          promptNeed: _promptNeedController.text.trim(),
          displayName: _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : null,
          interests: _selectedInterests.toList(),
          skills: _selectedSkills.toList(),
        );
        myProfileNotifier.value = updated;
        if (updated.displayName != null && updated.displayName!.isNotEmpty) {
          await ref.read(authProvider.notifier).updateDisplayName(updated.displayName!);
        }
        if (updated.interestLabels.isNotEmpty) {
          customInterestsNotifier.value = updated.interestLabels;
        }
        if (updated.skillLabels.isNotEmpty) {
          customSkillsNotifier.value = updated.skillLabels;
        }
      } catch (e) {
        debugPrint('Backend profile update warning: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        backgroundColor: t.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Edit profile',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.ink,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(context).padding.bottom + 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar area
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    ValueListenableBuilder<String?>(
                      valueListenable: avatarUrlNotifier,
                      builder: (_, savedUrl, __) => NhAvatar(
                        avatarUrl: _avatarPath ?? savedUrl,
                        initials: _initials(_nameController.text),
                        size: 90,
                        borderRadius: 26,
                        backgroundColor: NeedHubTokens.forest,
                        fontSize: 32,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: NeedHubTokens.clay,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: t.paper, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Display Name
            NhTextField(
              label: 'Display Name',
              hint: 'Your display name',
              controller: _nameController,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),

            // Bio
            _MultilineField(
              label: 'BIO',
              hint: 'Write a short bio about yourself (e.g. Passionate developer, coffee lover & avid reader…)',
              controller: _bioController,
              t: t,
              minLines: 3,
              maxLines: 5,
            ),
            const SizedBox(height: 20),

            // Location
            NhTextField(
              label: 'Location',
              hint: 'City or neighbourhood',
              controller: _locationController,
              textInputAction: TextInputAction.done,
              readOnly: true,
              onTap: _openMapPicker,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: NeedHubTokens.clay),
                      )
                    : const Icon(Icons.my_location_rounded,
                        size: 18, color: NeedHubTokens.clay),
                label: Text(
                  _locating ? 'Getting location…' : 'Use my current location',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: NeedHubTokens.clay,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: BorderSide(
                      color: NeedHubTokens.clay.withOpacity(0.35),
                      width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openMapPicker,
                icon: const Icon(Icons.map_outlined, size: 18, color: NeedHubTokens.clay),
                label: Text(
                  'Pick on map',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: NeedHubTokens.clay,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: BorderSide(
                      color: NeedHubTokens.clay.withOpacity(0.35),
                      width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Interests section
            Text(
              'INTERESTS',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted2,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<List<String>>(
              valueListenable: customInterestsNotifier,
              builder: (_, custom, __) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...[..._interestOptions, ...custom].map((interest) {
                    final selected = _selectedInterests.contains(interest);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (selected) {
                          _selectedInterests.remove(interest);
                        } else {
                          _selectedInterests.add(interest);
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? NeedHubTokens.forest.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: selected ? NeedHubTokens.forest : t.rail,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          interest,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? NeedHubTokens.forest : t.muted2,
                          ),
                        ),
                      ),
                    );
                  }),
                  _AddChip(
                    label: 'Add other',
                    color: NeedHubTokens.forest,
                    onTap: () => _promptAdd(context, isSkill: false),
                    t: t,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Skills section
            Text(
              'SKILLS',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted2,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<List<String>>(
              valueListenable: customSkillsNotifier,
              builder: (_, custom, __) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...[..._skillOptions, ...custom].map((skill) {
                    final selected = _selectedSkills.contains(skill);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (selected) {
                          _selectedSkills.remove(skill);
                        } else {
                          _selectedSkills.add(skill);
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? NeedHubTokens.ochre.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: selected ? NeedHubTokens.ochre : t.rail,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          skill,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? NeedHubTokens.ochre : t.muted2,
                          ),
                        ),
                      ),
                    );
                  }),
                  _AddChip(
                    label: 'Add other',
                    color: NeedHubTokens.ochre,
                    onTap: () => _promptAdd(context, isSkill: true),
                    t: t,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Gender
            Text(
              'GENDER',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted2,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                'Female',
                'Male',
                'Non-binary',
                'Prefer not to say'
              ]
                  .map((g) => _EditGenderChip(
                        label: g,
                        selected: _gender == g,
                        onTap: () => setState(() => _gender = g),
                        t: t,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 28),

            // Prompt fields
            Text(
              "THE SKILL I'D LOVE TO TEACH",
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted2,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 8),
            _MultilineField(
              label: '',
              hint: 'e.g. Public speaking — I can help you structure talks and overcome stage fear.',
              controller: _promptSkillController,
              t: t,
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            Text(
              'MY IDEAL COLLAB',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted2,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 8),
            _MultilineField(
              label: '',
              hint: 'e.g. A designer who loves clean UI and shipping fast.',
              controller: _promptCollabController,
              t: t,
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            Text(
              "THE NEED I'D POST RIGHT NOW",
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted2,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 8),
            _MultilineField(
              label: '',
              hint: 'e.g. Someone to help test my mobile app and give honest feedback.',
              controller: _promptNeedController,
              t: t,
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 32),

            // Save button
            NhPrimaryButton(
              label: 'Save changes',
              onPressed: _save,
              loading: _saving,
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _MultilineField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final NeedHubTokens t;
  final int minLines;
  final int maxLines;

  const _MultilineField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.t,
    this.minLines = 1,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: t.muted2,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: t.rail, width: 1.5),
          ),
          child: TextField(
            controller: controller,
            minLines: minLines,
            maxLines: maxLines,
            style: GoogleFonts.hankenGrotesk(fontSize: 15, color: t.ink),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.hankenGrotesk(
                  fontSize: 15, color: t.muted),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15, vertical: 13),
              filled: false,
            ),
          ),
        ),
      ],
    );
  }
}

class _AddOtherSheet extends StatefulWidget {
  final String label;
  final String hint;

  const _AddOtherSheet({required this.label, required this.hint});

  @override
  State<_AddOtherSheet> createState() => _AddOtherSheetState();
}

class _AddOtherSheetState extends State<_AddOtherSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: t.rail, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Add another ${widget.label}',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: t.ink,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: t.paper,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.rail, width: 1.5),
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(context).pop(v),
                style:
                    GoogleFonts.hankenGrotesk(fontSize: 15, color: t.ink),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: GoogleFonts.hankenGrotesk(
                      fontSize: 15, color: t.muted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  filled: false,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      side: BorderSide(color: t.rail, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Cancel',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t.muted2)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_controller.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NeedHubTokens.forest,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Add',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _AddChip({
    required this.label,
    required this.color,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: color.withValues(alpha: 0.4),
              width: 1.5,
              style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditGenderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _EditGenderChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? NeedHubTokens.clay.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? NeedHubTokens.clay : t.rail,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? NeedHubTokens.clay : t.muted2,
          ),
        ),
      ),
    );
  }
}

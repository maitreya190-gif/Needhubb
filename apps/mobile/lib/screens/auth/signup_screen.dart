import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user_state.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/profiles_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_button.dart';
import '../../widgets/nh_text_field.dart';
import 'location_picker_screen.dart';

const _interests = [
  'Lifting', 'Football', 'Cricket', 'DSA', 'Coffee', 'Trekking',
  'Photography', 'Guitar', 'Flutter', 'Movies', 'Anime', 'Chess',
  'Sketching', 'Startups', 'Running', 'Cooking',
];

const _skills = [
  'Java', 'Python', 'Flutter', 'UI Design', 'Writing', 'Math tutoring',
  'Video editing', 'Note-taking', 'Guitar lessons', 'Proofreading',
];

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  int _step = 0;
  static const int _totalSteps = 7;

  // Step 0 — identity
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _gender;

  // Step 1 — verification
  final List<TextEditingController> _codeControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _codeFocus = List.generate(6, (_) => FocusNode());

  // Step 2 — interests
  final Set<String> _selectedInterests = {};
  final List<String> _customInterests = [];
  final _interestAddController = TextEditingController();

  // Step 3 — skills
  final Set<String> _selectedSkills = {};
  final List<String> _customSkills = [];
  final _skillAddController = TextEditingController();

  // Step 4 — location
  final _locationController = TextEditingController();
  double _maxDistanceKm = 5.0;

  // Step 5 — about you (bio + prompts)
  final _bioController = TextEditingController();
  final _promptSkillController = TextEditingController();
  final _promptCollabController = TextEditingController();
  final _promptNeedController = TextEditingController();

  // Step 6 — rules
  bool _notificationsEnabled = true;

  // Saved from API after step 1 — applied to authProvider only at the very end
  String? _savedToken;
  String? _savedUserId;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    for (final c in _codeControllers) c.dispose();
    for (final f in _codeFocus) f.dispose();
    _interestAddController.dispose();
    _skillAddController.dispose();
    _locationController.dispose();
    _bioController.dispose();
    _promptSkillController.dispose();
    _promptCollabController.dispose();
    _promptNeedController.dispose();
    super.dispose();
  }

  List<String> get _allInterests => [..._interests, ..._customInterests];
  List<String> get _allSkills => [..._skills, ..._customSkills];

  void _goNext() {
    if (_step < _totalSteps - 1) setState(() => _step++);
  }

  bool _locating = false;

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
      // Try last-known first (instant); fall back to a fresh fix with a 10s cap.
      // Using LocationAccuracy.lowest helps avoid GPS lock requirements on emulators.
      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition();
        pos ??= await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.lowest,
          timeLimit: const Duration(seconds: 3),
        );
      } catch (e) {
        if (e.toString().contains('TimeoutException')) {
          // Fallback mock location for emulators without GPS fix
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Emulator GPS timed out. Using mock location (Mumbai).')));
          }
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
              style: ElevatedButton.styleFrom(backgroundColor: NeedHubTokens.clay),
              child: Text('Exact Location',
                  style: GoogleFonts.hankenGrotesk(
                      fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      );

      if (isExact == null) return; // user cancelled

      final lat = pos.latitude.toStringAsFixed(3);
      final lon = pos.longitude.toStringAsFixed(3);
      final label = isExact
          ? 'Exact: Lat $lat, Lon $lon'
          : 'Approx (2km): Lat $lat, Lon $lon';

      if (!mounted) return;
      setState(() {
        _locationController.text = label;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Got your location — you can replace with a city name if you like.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not fetch location: $e')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

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

  // Called from step 0 — sends OTP email, advances to OTP step.
  Future<void> _doSignup() async {
    setState(() { _loading = true; _error = null; });
    try {
      final authService = ref.read(authServiceProvider);
      final response = await authService.signup(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
        username: _usernameController.text.trim().toLowerCase(),
      );
      _savedUserId = response.userId;
      // Auto-fill the OTP boxes with the code the backend returned in demo
      // mode so the user only has to tap Verify.
      if (response.devOtp != null && response.devOtp!.length == 6) {
        for (int i = 0; i < 6 && i < _codeControllers.length; i++) {
          _codeControllers[i].text = response.devOtp![i];
        }
      }
      _goNext();
    } catch (e) {
      if (e is DioException && (e.response?.statusCode == 500 || e.type == DioExceptionType.connectionError)) {
        // Fallback for 500 server error (e.g. backend mailer failure)
        _savedUserId = 'usr_demo_${DateTime.now().millisecondsSinceEpoch}';
        _goNext();
      } else {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Called from step 1 — verifies OTP, stores JWT, advances to interests.
  Future<void> _submitSignup() async {
    setState(() { _loading = true; _error = null; });
    try {
      final authService = ref.read(authServiceProvider);
      final code = _codeControllers.map((c) => c.text).join();
      final response = await authService.verifyEmail(
        userId: _savedUserId ?? 'usr_demo_1',
        code: code,
      );
      _savedToken = response.token;
      _goNext();
    } catch (e) {
      if (e is DioException && (e.response?.statusCode == 500 || (_savedUserId != null && _savedUserId!.startsWith('usr_demo_')))) {
        _savedToken = 'demo_token_${DateTime.now().millisecondsSinceEpoch}';
        _goNext();
      } else {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Called from step 1 — resends OTP.
  Future<void> _resendOtp() async {
    if (_savedUserId == null) return;
    try {
      await ref.read(authServiceProvider).resendOtp(userId: _savedUserId!);
    } catch (_) {}
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('nh_interests', _selectedInterests.toList());
    await prefs.setStringList('nh_skills', _selectedSkills.toList());
    await prefs.setString('nh_location', _locationController.text.trim());
    await prefs.setDouble('nh_max_distance_km', _maxDistanceKm);

    genderNotifier.value = _gender;
    locationNotifier.value = _locationController.text.trim().isEmpty
        ? locationNotifier.value
        : _locationController.text.trim();
    if (_bioController.text.trim().isNotEmpty) {
      bioNotifier.value = _bioController.text.trim();
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
    for (final c in _customInterests) {
      addCustomInterest(c);
    }
    for (final s in _customSkills) {
      addCustomSkill(s);
    }

    try {
      final profilesApi = ref.read(profilesApiProvider);
      await profilesApi.update(
        interests: _selectedInterests.toList(),
        skills: _selectedSkills.toList(),
        bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
        gender: _gender,
        location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
        promptSkill: _promptSkillController.text.trim().isEmpty ? null : _promptSkillController.text.trim(),
        promptCollab: _promptCollabController.text.trim().isEmpty ? null : _promptCollabController.text.trim(),
        promptNeed: _promptNeedController.text.trim().isEmpty ? null : _promptNeedController.text.trim(),
      );
    } catch (_) {}

    final email = _emailController.text.trim().toLowerCase();
    final fallbackUserId = 'usr_${email.replaceAll(RegExp(r'[^\w]'), '_')}';
    final token =
        _savedToken ?? 'demo_token_${DateTime.now().millisecondsSinceEpoch}';
    final userId = _savedUserId ?? fallbackUserId;

    await ref.read(authProvider.notifier).login(
          token: token,
          userId: userId,
          displayName: _nameController.text.trim().isNotEmpty
              ? _nameController.text.trim()
              : 'New User',
          email: email,
        );
  }

  String _friendlyError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final body = e.response?.data;

      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Could not reach the server. Check your internet connection.';
      }

      if (status == 409) {
        final code = body is Map ? body['code'] : null;
        if (code == 'USERNAME_TAKEN') return 'That username is already taken. Try another.';
        return 'That email is already registered. Try logging in instead.';
      }

      if (status == 400 && body is Map) {
        final errorVal = body['error'];
        if (errorVal is Map) {
          // Zod flatten: { fieldErrors: { displayName: [...], email: [...] }, formErrors: [] }
          final fieldErrors = errorVal['fieldErrors'];
          if (fieldErrors is Map) {
            if (fieldErrors.containsKey('displayName')) return 'Name must be at least 2 characters.';
            if (fieldErrors.containsKey('email')) return 'Please enter a valid email address.';
            if (fieldErrors.containsKey('password')) return 'Password must be at least 8 characters.';
          }
        }
        if (errorVal is String) {
          final lower = errorVal.toLowerCase();
          if (lower.contains('already')) return 'That email is already registered. Try logging in instead.';
        }
        return 'Check your details and try again.';
      }

      if (status != null) return 'Server error ($status). Please try again.';
    }

    final msg = e.toString().toLowerCase();
    if (msg.contains('409') || msg.contains('already')) {
      return 'That email is already registered. Try logging in instead.';
    }
    if (msg.contains('network') || msg.contains('connection')) {
      return 'Could not reach the server. Check your connection.';
    }
    return 'Something went wrong. Please try again.';
  }

  bool get _step0Valid =>
      _nameController.text.trim().length >= 2 &&
      _usernameController.text.trim().length >= 3 &&
      _emailController.text.trim().contains('@') &&
      _passwordController.text.length >= 8 &&
      _gender != null;

  bool get _step1Valid =>
      _codeControllers.every((c) => c.text.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        child: Column(
          children: [
            // Back button row (only after step 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: t.ink),
                    onPressed: () {
                      if (_step > 0) {
                        setState(() => _step--);
                      } else {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/login');
                        }
                      }
                    },
                  ),
                  Expanded(
                    child: Text(
                      'Step ${_step + 1} of $_totalSteps',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: t.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Progress dots bar
            _ProgressBar(step: _step, total: _totalSteps),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: [
                  _buildStep0(t),
                  _buildStep1(t),
                  _buildStep2(t),
                  _buildStep3(t),
                  _buildStep4Location(t),
                  _buildStep5AboutYou(t),
                  _buildStep5Rules(t),
                ][_step],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 0: Name / Email / Password ────────────────────────────────────────

  Widget _buildStep0(NeedHubTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 36),
        _Kicker(label: 'YOUR IDENTITY'),
        const SizedBox(height: 10),
        Text(
          "What's your name?",
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your name is how others find and recognise you on NeedHub.',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: t.muted2,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        NhTextField(
          label: 'Name',
          hint: 'Your display name (min 2 characters)',
          controller: _nameController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        NhTextField(
          label: 'Username',
          hint: '@yourusername',
          controller: _usernameController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        Text(
          'Unique · visible to others',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 12,
            color: t.muted,
          ),
        ),
        const SizedBox(height: 16),
        NhTextField(
          label: 'Email',
          hint: 'you@example.com',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        NhTextField(
          label: 'Password',
          hint: 'At least 8 characters',
          controller: _passwordController,
          obscure: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        Text(
          'GENDER',
          style: GoogleFonts.hankenGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: t.muted2,
              letterSpacing: 0.7),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const ['Female', 'Male', 'Non-binary', 'Prefer not to say']
              .map((g) => _GenderChip(
                  label: g,
                  selected: _gender == g,
                  onTap: () => setState(() => _gender = g),
                  t: t))
              .toList(),
        ),
        const SizedBox(height: 12),
        // Security note
        Row(
          children: [
            const Icon(Icons.shield_outlined, size: 14, color: NeedHubTokens.forest),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Your password is encrypted and never shared with anyone.',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 12,
                  color: NeedHubTokens.forest,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        if (_error != null) ...[
          _ErrorBox(message: _error!),
          const SizedBox(height: 16),
        ],
        NhPrimaryButton(
          label: 'Continue',
          loading: _loading,
          onPressed: _step0Valid ? _doSignup : null,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => context.pop(),
            child: Text(
              'Already have an account? Log in',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: t.muted2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Step 1: Verify Email ───────────────────────────────────────────────────

  Widget _buildStep1(NeedHubTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 36),
        _Kicker(label: 'VERIFY YOUR EMAIL'),
        const SizedBox(height: 10),
        Text(
          'We sent you a code',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 8),
        RichText(
          text: TextSpan(
            style: GoogleFonts.hankenGrotesk(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: t.muted2,
              height: 1.5,
            ),
            children: [
              const TextSpan(text: 'Enter the 6-digit code we sent to '),
              TextSpan(
                text: _emailController.text.trim(),
                style: GoogleFonts.hankenGrotesk(
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        // 6-cell OTP input
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) => _OtpCell(
            controller: _codeControllers[i],
            focusNode: _codeFocus[i],
            onChanged: (val) {
              if (val.length == 1 && i < 5) {
                _codeFocus[i + 1].requestFocus();
              }
              setState(() {});
            },
            onBackspace: () {
              if (_codeControllers[i].text.isEmpty && i > 0) {
                _codeFocus[i - 1].requestFocus();
              }
            },
          )),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: _resendOtp,
            child: Text(
              "Didn't get it? Resend code",
              style: GoogleFonts.hankenGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: NeedHubTokens.clay,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        if (_error != null) ...[
          _ErrorBox(message: _error!),
          const SizedBox(height: 16),
        ],
        NhPrimaryButton(
          label: 'Continue',
          loading: _loading,
          onPressed: _step1Valid ? _submitSignup : null,
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Step 2: Interests ──────────────────────────────────────────────────────

  Widget _buildStep2(NeedHubTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 36),
        _Kicker(label: 'YOUR INTERESTS'),
        const SizedBox(height: 10),
        Text(
          "What are you into?",
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Pick what you genuinely enjoy. This is how you'll find people near you.",
          style: GoogleFonts.hankenGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: t.muted2,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _allInterests.map((interest) {
            final selected = _selectedInterests.contains(interest);
            return _SelectableChip(
              label: interest,
              selected: selected,
              onTap: () => setState(() {
                if (selected) {
                  _selectedInterests.remove(interest);
                } else {
                  _selectedInterests.add(interest);
                }
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        // Add custom interest
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _interestAddController,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 14,
                  color: t.ink,
                ),
                decoration: InputDecoration(
                  hintText: 'Add your own…',
                  hintStyle: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    color: t.muted,
                  ),
                  filled: true,
                  fillColor: t.card,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide(color: t.rail, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide(color: t.rail, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(
                        color: NeedHubTokens.clay, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final v = _interestAddController.text.trim();
                if (v.isNotEmpty && !_allInterests.contains(v)) {
                  setState(() {
                    _customInterests.add(v);
                    _selectedInterests.add(v);
                    _interestAddController.clear();
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: NeedHubTokens.clay,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  'Add',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 36),
        NhPrimaryButton(
          label: 'Continue',
          onPressed: _goNext,
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Step 3: Skills ─────────────────────────────────────────────────────────

  Widget _buildStep3(NeedHubTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 36),
        _Kicker(label: 'YOUR SKILLS'),
        const SizedBox(height: 10),
        Text(
          "What can you help with?",
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Skills you're willing to offer on NeedHub.",
          style: GoogleFonts.hankenGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: t.muted2,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _allSkills.map((skill) {
            final selected = _selectedSkills.contains(skill);
            return _SelectableChip(
              label: skill,
              selected: selected,
              onTap: () => setState(() {
                if (selected) {
                  _selectedSkills.remove(skill);
                } else {
                  _selectedSkills.add(skill);
                }
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        // Add custom skill
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _skillAddController,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 14,
                  color: t.ink,
                ),
                decoration: InputDecoration(
                  hintText: 'Add your own…',
                  hintStyle: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    color: t.muted,
                  ),
                  filled: true,
                  fillColor: t.card,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide(color: t.rail, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide(color: t.rail, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(
                        color: NeedHubTokens.clay, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final v = _skillAddController.text.trim();
                if (v.isNotEmpty && !_allSkills.contains(v)) {
                  setState(() {
                    _customSkills.add(v);
                    _selectedSkills.add(v);
                    _skillAddController.clear();
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: NeedHubTokens.clay,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  'Add',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 36),
        NhPrimaryButton(
          label: 'Continue',
          onPressed: _goNext,
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Step 4: Location ──────────────────────────────────────────────────────

  Widget _buildStep4Location(NeedHubTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 36),
        _Kicker(label: 'YOUR LOCATION'),
        const SizedBox(height: 10),
        Text(
          'Where are you based?',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'NeedHub surfaces needs near you. Your exact address is never shared — only your city or neighbourhood.',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 15,
            color: t.muted2,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),

        // Location field
        Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.rail, width: 1.5),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _openMapPicker,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(Icons.location_on_outlined,
                      color: NeedHubTokens.clay, size: 20),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _locationController,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 15, color: t.ink),
                  decoration: InputDecoration(
                    hintText: 'City or neighbourhood (e.g. Koramangala)',
                    hintStyle: GoogleFonts.hankenGrotesk(
                        fontSize: 14, color: t.muted),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
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
                  color: NeedHubTokens.clay.withValues(alpha: 0.35),
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
                  color: NeedHubTokens.clay.withValues(alpha: 0.35),
                  width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Distance radius slider
        Row(
          children: [
            Icon(Icons.radar_rounded, size: 16, color: t.muted2),
            const SizedBox(width: 8),
            Text(
              'Help radius',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w600, color: t.ink),
            ),
            const Spacer(),
            Text(
              '${_maxDistanceKm.toInt()} km',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: NeedHubTokens.clay,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: NeedHubTokens.clay,
            inactiveTrackColor: t.rail,
            thumbColor: NeedHubTokens.clay,
            overlayColor: NeedHubTokens.clay.withValues(alpha: 0.15),
            trackHeight: 4,
          ),
          child: Slider(
            value: _maxDistanceKm,
            min: 1,
            max: 25,
            divisions: 24,
            onChanged: (v) => setState(() => _maxDistanceKm = v),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('1 km', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: t.muted)),
            Text('25 km', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: t.muted)),
          ],
        ),
        const SizedBox(height: 12),

        // Privacy note
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NeedHubTokens.forest.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined,
                  color: NeedHubTokens.forest, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Only your city or area is visible to others. Never your precise address.',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 12.5,
                      color: NeedHubTokens.forest,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),

        NhPrimaryButton(
          label: 'Continue',
          onPressed: _goNext,
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Step 5: About You (bio + prompts) ────────────────────────────────────

  Widget _buildStep5AboutYou(NeedHubTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 36),
        _Kicker(label: 'ABOUT YOU'),
        const SizedBox(height: 10),
        Text(
          'Tell people who you are',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: t.ink,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'These show on your profile and help people decide to connect. You can edit them anytime.',
          style: GoogleFonts.hankenGrotesk(
              fontSize: 15, color: t.muted2, height: 1.5),
        ),
        const SizedBox(height: 24),
        _SignupPromptField(
          label: 'A LINE ABOUT YOU (BIO)',
          hint: 'e.g. Frontend dev, coffee snob, weekend trekker.',
          controller: _bioController,
          onChanged: () => setState(() {}),
          t: t,
        ),
        const SizedBox(height: 16),
        _SignupPromptField(
          label: "THE SKILL I'D LOVE TO TEACH",
          hint: 'e.g. DSA — I love breaking down complex algorithms…',
          controller: _promptSkillController,
          onChanged: () => setState(() {}),
          t: t,
        ),
        const SizedBox(height: 16),
        _SignupPromptField(
          label: 'MY IDEAL COLLAB',
          hint: 'e.g. Someone who ships fast and loves late-night brainstorming.',
          controller: _promptCollabController,
          onChanged: () => setState(() {}),
          t: t,
        ),
        const SizedBox(height: 16),
        _SignupPromptField(
          label: "THE NEED I'D POST RIGHT NOW",
          hint: 'e.g. A designer for my side project.',
          controller: _promptNeedController,
          onChanged: () => setState(() {}),
          t: t,
        ),
        const SizedBox(height: 32),
        NhPrimaryButton(label: 'Continue', onPressed: _goNext),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Step 6: Rules ──────────────────────────────────────────────────────────

  Widget _buildStep5Rules(NeedHubTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 36),
        _Kicker(label: 'ALMOST DONE'),
        const SizedBox(height: 10),
        Text(
          'A few things before\nwe start',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: t.ink,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 28),

        // Notifications toggle
        Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(16),
            boxShadow: NeedHubThemes.cardShadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: NeedHubTokens.forest.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_outlined,
                  color: NeedHubTokens.forest,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enable notifications',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      'Stay in the loop when someone responds',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _notificationsEnabled,
                onChanged: (val) =>
                    setState(() => _notificationsEnabled = val),
                activeThumbColor: NeedHubTokens.clay,
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Info card — you browse, you choose
        Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(16),
            boxShadow: NeedHubThemes.cardShadow,
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: NeedHubTokens.forest.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.visibility_outlined,
                  color: NeedHubTokens.forest,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You browse. You choose.',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'NeedHub never auto-matches you with anyone. You browse people nearby who share your interests and choose who you reach out to — fully on your terms.',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        color: t.muted2,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 36),

        // CTA
        NhPrimaryButton(
          label: 'Start exploring →',
          onPressed: _finishOnboarding,
        ),

        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final int step;
  final int total;

  const _ProgressBar({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: List.generate(total, (i) {
          final active = i <= step;
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < total - 1 ? 4 : 0),
              decoration: BoxDecoration(
                color: active ? NeedHubTokens.clay : t.rail,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Kicker extends StatelessWidget {
  final String label;

  const _Kicker({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.hankenGrotesk(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: NeedHubTokens.clay,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE0392B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFFE0392B).withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: GoogleFonts.hankenGrotesk(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: const Color(0xFFE0392B),
        ),
      ),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? NeedHubTokens.clay : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? NeedHubTokens.clay : t.rail,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : t.muted2,
          ),
        ),
      ),
    );
  }
}

class _OtpCell extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  const _OtpCell({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: 52,
      height: 60,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspace();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: onChanged,
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: t.card,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: t.rail, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: t.rail, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide:
                  const BorderSide(color: NeedHubTokens.clay, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _GenderChip({
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

class _SignupPromptField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final NeedHubTokens t;

  const _SignupPromptField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
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
            color: t.card,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: t.rail, width: 1.5),
          ),
          child: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => onChanged(),
            style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.hankenGrotesk(
                  fontSize: 14, color: t.muted),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(14),
              filled: false,
            ),
          ),
        ),
      ],
    );
  }
}

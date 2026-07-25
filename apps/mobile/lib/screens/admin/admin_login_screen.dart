import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/admin_api.dart';
import '../../theme/tokens.dart';
import 'admin_dashboard_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String _error = '';
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final secret = _controller.text.trim();
    if (secret.isEmpty) return;

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      AdminApi.instance.setSecret(secret);
      await AdminApi.instance.stats();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
      );
    } on DioException catch (e) {
      AdminApi.instance.setSecret('');
      final isNetwork = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.unknown;
      setState(() {
        _error = isNetwork
            ? 'Cannot reach the server.\nMake sure the API is running.'
            : 'Invalid admin secret.';
        _loading = false;
      });
    } catch (_) {
      AdminApi.instance.setSecret('');
      setState(() {
        _error = 'Something went wrong. Try again.';
        _loading = false;
      });
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
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              24, 8, 24, MediaQuery.of(context).padding.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Shield icon — monochrome
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.chip,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.shield_outlined, color: t.ink, size: 22),
              ),
              const SizedBox(height: 20),

              Text(
                'ADMIN ACCESS',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: t.muted2,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                'NeedHub Admin',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: t.ink,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter the admin secret to access the dashboard.',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 14, color: t.muted, height: 1.45),
              ),
              const SizedBox(height: 36),

              Text(
                'ADMIN SECRET',
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
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _error.isNotEmpty ? t.ink : t.rail,
                    width: 1.5,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  obscureText: _obscure,
                  style: GoogleFonts.hankenGrotesk(fontSize: 15, color: t.ink),
                  decoration: InputDecoration(
                    hintText: '••••••••••••',
                    hintStyle:
                        GoogleFonts.hankenGrotesk(fontSize: 15, color: t.muted),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: t.muted,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _signIn(),
                  autofocus: true,
                ),
              ),

              if (_error.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _error,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ],

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.surfaceDark,
                    foregroundColor: t.onDark,
                    disabledBackgroundColor: t.rail,
                    disabledForegroundColor: t.muted,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    textStyle: GoogleFonts.bricolageGrotesque(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  child: _loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: t.onDark),
                        )
                      : const Text('Sign in →'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

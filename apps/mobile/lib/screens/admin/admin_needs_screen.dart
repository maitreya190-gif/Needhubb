import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/admin_api.dart';
import '../../theme/tokens.dart';
import 'admin_shared.dart';

class AdminNeedsScreen extends StatefulWidget {
  const AdminNeedsScreen({super.key});

  @override
  State<AdminNeedsScreen> createState() => _AdminNeedsScreenState();
}

class _AdminNeedsScreenState extends State<AdminNeedsScreen> {
  List<AdminNeed> _needs = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final n = await AdminApi.instance.needs();
      if (mounted) {
        setState(() {
        _needs = n;
        _loading = false;
      });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
        _error = e.toString();
        _loading = false;
      });
      }
    }
  }

  Future<void> _delete(AdminNeed need) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdminConfirmDialog(
        title: 'Remove need?',
        body: '"${need.title}" by ${need.posterName} will be deleted.',
      ),
    );
    if (ok != true) return;
    try {
      await AdminApi.instance.deleteNeed(need.id);
      setState(() => _needs.removeWhere((n) => n.id == need.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Color _typeColor(String type) {
    switch (type.toLowerCase()) {
      case 'earn':
        return NeedHubTokens.ochre;
      case 'connect':
        return NeedHubTokens.forest;
      default:
        return NeedHubTokens.clay;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        backgroundColor: t.surfaceDark,
        elevation: 0,
        iconTheme: IconThemeData(color: t.onDark),
        title: Text(
          'Needs / Posts',
          style: GoogleFonts.bricolageGrotesque(
              fontSize: 18, fontWeight: FontWeight.w700, color: t.onDark),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: t.onDarkMuted),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? AdminErrorView(error: _error, onRetry: _load)
              : _needs.isEmpty
                  ? const AdminEmptyView(message: 'No needs found')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                      itemCount: _needs.length,
                      itemBuilder: (_, i) {
                        final need = _needs[i];
                        final color = _typeColor(need.needType);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: t.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: t.rail, width: 1),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: IntrinsicHeight(
                              child: Row(
                                children: [
                                  Container(width: 5, color: color),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(13),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                                child: Text(
                                                  need.needType.toUpperCase(),
                                                  style: GoogleFonts
                                                      .hankenGrotesk(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.white,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: t.chip,
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                                child: Text(
                                                  need.status,
                                                  style: GoogleFonts
                                                      .hankenGrotesk(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: t.muted2,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            need.title,
                                            style: GoogleFonts.hankenGrotesk(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: t.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'by ${need.posterName}',
                                            style: GoogleFonts.hankenGrotesk(
                                                fontSize: 12, color: t.muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _delete(need),
                                    icon: const Icon(Icons.delete_outline_rounded,
                                        color: NeedHubTokens.clay, size: 20),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

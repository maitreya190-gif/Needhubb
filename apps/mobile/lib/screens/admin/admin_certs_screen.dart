import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/admin_api.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_full_screen_image_viewer.dart';
import 'admin_shared.dart';

class AdminCertsScreen extends StatefulWidget {
  const AdminCertsScreen({super.key});

  @override
  State<AdminCertsScreen> createState() => _AdminCertsScreenState();
}

class _AdminCertsScreenState extends State<AdminCertsScreen> {
  List<AdminCert> _certs = [];
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
      final c = await AdminApi.instance.certs();
      if (mounted) setState(() {
        _certs = c;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _review(AdminCert cert, String status) async {
    int? points;
    if (status == 'APPROVED') {
      points = await _askPoints();
      if (points == null) return;
    }
    try {
      await AdminApi.instance.reviewCert(cert.id, status, points: points);
      setState(() => _certs.removeWhere((c) => c.id == cert.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'APPROVED'
                ? 'Certificate approved (+$points pts)'
                : 'Certificate rejected'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<int?> _askPoints() async {
    final t = context.tokens;
    final ctrl = TextEditingController(text: '70');
    final result = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Points to award',
          style: GoogleFonts.bricolageGrotesque(
              fontSize: 18, fontWeight: FontWeight.w700, color: t.ink),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: GoogleFonts.hankenGrotesk(fontSize: 15, color: t.ink),
          decoration: InputDecoration(
            hintText: 'e.g. 70',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.rail),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.hankenGrotesk(color: t.muted2)),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(ctrl.text) ?? 70),
            style: ElevatedButton.styleFrom(
              backgroundColor: NeedHubTokens.forest,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Approve',
                style:
                    GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
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
          'Certificate Queue',
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
              : _certs.isEmpty
                  ? const AdminEmptyView(message: 'No pending certificates 🎉')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                      itemCount: _certs.length,
                      itemBuilder: (_, i) => _CertTile(
                        cert: _certs[i],
                        t: t,
                        onApprove: () => _review(_certs[i], 'APPROVED'),
                        onReject: () => _review(_certs[i], 'REJECTED'),
                      ),
                    ),
    );
  }
}

class _CertTile extends StatelessWidget {
  final AdminCert cert;
  final NeedHubTokens t;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _CertTile({
    required this.cert,
    required this.t,
    required this.onApprove,
    required this.onReject,
  });

  bool get _isImage {
    final url = cert.fileUrl.toLowerCase();
    return url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.webp') ||
        url.endsWith('.gif');
  }

  void _viewCert(BuildContext context) {
    if (cert.fileUrl.isEmpty) return;
    if (_isImage) {
      NHFullScreenImageViewer.open(
        context,
        imageUrl: cert.fileUrl,
        title: cert.type,
        subtitle: cert.userName,
      );
    } else {
      // Non-image (PDF etc.) — show a dialog with the URL
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: t.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Certificate File',
              style: GoogleFonts.bricolageGrotesque(
                  fontSize: 16, fontWeight: FontWeight.w700, color: t.ink)),
          content: SelectableText(
            cert.fileUrl,
            style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close',
                  style: GoogleFonts.hankenGrotesk(color: t.muted2)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.rail, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Certificate image preview (tap to fullscreen)
            if (cert.fileUrl.isNotEmpty)
              GestureDetector(
                onTap: () => _viewCert(context),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  child: _isImage
                      ? Image.network(
                          cert.fileUrl,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) => progress == null
                              ? child
                              : Container(
                                  height: 180,
                                  color: NeedHubTokens.ochre.withValues(alpha: 0.07),
                                  child: const Center(
                                      child: CircularProgressIndicator()),
                                ),
                          errorBuilder: (_, __, ___) => _docPlaceholder(),
                        )
                      : _docPlaceholder(),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: NeedHubTokens.ochre.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.verified_outlined,
                            color: NeedHubTokens.ochre, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cert.type,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: t.ink,
                              ),
                            ),
                            Text(
                              cert.userName,
                              style: GoogleFonts.hankenGrotesk(
                                  fontSize: 12, color: t.muted),
                            ),
                          ],
                        ),
                      ),
                      // View button
                      if (cert.fileUrl.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _viewCert(context),
                          icon: Icon(
                            _isImage
                                ? Icons.zoom_in_rounded
                                : Icons.open_in_new_rounded,
                            size: 16,
                            color: NeedHubTokens.forest,
                          ),
                          label: Text(
                            'View',
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: NeedHubTokens.forest,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onReject,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: NeedHubTokens.clay,
                            side: BorderSide(
                                color:
                                    NeedHubTokens.clay.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text('Reject',
                              style: GoogleFonts.hankenGrotesk(
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onApprove,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NeedHubTokens.forest,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text('Approve',
                              style: GoogleFonts.hankenGrotesk(
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docPlaceholder() {
    return Container(
      height: 120,
      width: double.infinity,
      color: NeedHubTokens.ochre.withValues(alpha: 0.07),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf_rounded,
              color: NeedHubTokens.ochre, size: 36),
          const SizedBox(height: 6),
          Text('Document attached — tap View to open',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: NeedHubTokens.ochre)),
        ],
      ),
    );
  }
}

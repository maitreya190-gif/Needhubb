import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/admin_api.dart';
import '../../theme/tokens.dart';
import 'admin_shared.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<AdminUser> _users = [];
  bool _loading = true;
  String _error = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load([String? query]) async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final u = await AdminApi.instance.users(search: query);
      if (mounted) setState(() {
        _users = u;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _delete(AdminUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdminConfirmDialog(
        title: 'Remove user?',
        body: '${user.displayName} (${user.email}) will be permanently deleted.',
      ),
    );
    if (ok != true) return;
    try {
      await AdminApi.instance.deleteUser(user.id);
      setState(() => _users.removeWhere((u) => u.id == user.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
          'Users',
          style: GoogleFonts.bricolageGrotesque(
              fontSize: 18, fontWeight: FontWeight.w700, color: t.onDark),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: t.onDarkMuted),
            onPressed: () =>
                _load(_search.text.isEmpty ? null : _search.text),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.rail, width: 1),
              ),
              child: TextField(
                controller: _search,
                style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
                decoration: InputDecoration(
                  hintText: 'Search by name or email…',
                  hintStyle: GoogleFonts.hankenGrotesk(
                      fontSize: 14, color: t.muted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: t.muted, size: 20),
                ),
                onSubmitted: (q) => _load(q.isEmpty ? null : q),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? AdminErrorView(error: _error, onRetry: _load)
                    : _users.isEmpty
                        ? const AdminEmptyView(message: 'No users found')
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                            itemCount: _users.length,
                            itemBuilder: (_, i) => _UserTile(
                              user: _users[i],
                              t: t,
                              onDelete: () => _delete(_users[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final AdminUser user;
  final NeedHubTokens t;
  final VoidCallback onDelete;

  const _UserTile(
      {required this.user, required this.t, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final initials =
        user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.rail, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: NeedHubTokens.forest.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: NeedHubTokens.forest,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.ink),
                  ),
                  Text(
                    user.email,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 12, color: t.muted),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      AdminMiniChip(label: '${user.needsCount} needs'),
                      const SizedBox(width: 6),
                      AdminMiniChip(label: '${user.reportsCount} reports'),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline_rounded,
                  color: NeedHubTokens.clay, size: 20),
              tooltip: 'Remove user',
            ),
          ],
        ),
      ),
    );
  }
}

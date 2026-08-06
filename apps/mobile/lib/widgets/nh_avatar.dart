import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Same --dart-define=API_URL used by api_client.dart. Falls back to the
// Android emulator alias for local dev.
const _apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:3000',
);

String? resolveAvatarUrl(String? rawUrl) {
  if (rawUrl == null) return null;
  final url = rawUrl.trim();
  if (url.isEmpty) return null;

  // Local device file path
  if (url.startsWith('/') && !url.startsWith('/uploads/')) {
    return url;
  }
  if (url.startsWith('file://')) {
    return url;
  }

  // Rewrite legacy localhost hosts to whatever API_URL is configured
  if (url.contains('localhost:3000')) {
    return url.replaceAll('http://localhost:3000', _apiBaseUrl);
  }
  if (url.contains('127.0.0.1:3000')) {
    return url.replaceAll('http://127.0.0.1:3000', _apiBaseUrl);
  }
  // Emulator-only host — rewrite to configured API_URL when running elsewhere
  if (url.contains('10.0.2.2:3000') && _apiBaseUrl != 'http://10.0.2.2:3000') {
    return url.replaceAll('http://10.0.2.2:3000', _apiBaseUrl);
  }

  // Relative upload path — prepend the configured API base
  if (url.startsWith('/uploads/') || url.startsWith('uploads/')) {
    final path = url.startsWith('/') ? url : '/$url';
    return '$_apiBaseUrl$path';
  }

  return url;
}

class NhAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final double size;
  final double borderRadius;
  final Color backgroundColor;
  final Color textColor;
  final double fontSize;

  const NhAvatar({
    super.key,
    this.avatarUrl,
    required this.initials,
    this.size = 40,
    this.borderRadius = 12,
    this.backgroundColor = const Color(0xFF1B4D3E),
    this.textColor = Colors.white,
    this.fontSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = resolveAvatarUrl(avatarUrl);
    final hasImage = resolved != null && resolved.isNotEmpty;

    Widget child;
    if (hasImage) {
      if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
        child = Image.network(
          resolved,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallback(),
        );
      } else if (resolved.startsWith('/') || resolved.startsWith('file://')) {
        final filePath = resolved.startsWith('file://') ? resolved.replaceFirst('file://', '') : resolved;
        final file = File(filePath);
        if (file.existsSync()) {
          child = Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallback(),
          );
        } else {
          child = _buildFallback();
        }
      } else {
        child = _buildFallback();
      }
    } else {
      child = _buildFallback();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _buildFallback() {
    return Text(
      initials,
      style: GoogleFonts.bricolageGrotesque(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        color: textColor,
      ),
    );
  }
}

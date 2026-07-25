import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  // Rewrite localhost / 127.0.0.1 for Android emulator
  if (!kIsWeb && Platform.isAndroid) {
    if (url.contains('localhost:3000')) {
      return url.replaceAll('localhost:3000', '10.0.2.2:3000');
    }
    if (url.contains('127.0.0.1:3000')) {
      return url.replaceAll('127.0.0.1:3000', '10.0.2.2:3000');
    }
  }

  // Relative upload path
  if (url.startsWith('/uploads/') || url.startsWith('uploads/')) {
    final path = url.startsWith('/') ? url : '/$url';
    final host = (!kIsWeb && Platform.isAndroid) ? 'http://10.0.2.2:3000' : 'http://localhost:3000';
    return '$host$path';
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

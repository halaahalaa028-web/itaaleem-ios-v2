import 'package:flutter/material.dart';

/// Third-party brand colors — the only hardcoded colors allowed, since
/// they're the platforms' own identities. Everything else comes from the
/// theme's [ColorScheme].
abstract final class BrandColors {
  static const facebook = Color(0xFF1877F2);
  static const whatsapp = Color(0xFF25D366);
  static const youtube = Color(0xFFFF0000);
  static const instagram = Color(0xFF833AB4);
  static const telegram = Color(0xFF229ED9);
  static const twitter = Color(0xFF1D9BF0);

  /// The platform's color in the current theme; `null` → use the theme's
  /// own (website), TikTok follows the theme's on-surface (black / white).
  static Color of(String platform, ColorScheme scheme) => switch (platform) {
    'facebook' => facebook,
    'whatsapp' => whatsapp,
    'youtube' => youtube,
    'instagram' => instagram,
    'telegram' => telegram,
    'twitter' => twitter,
    'tiktok' => scheme.onSurface,
    _ => scheme.primary,
  };
}

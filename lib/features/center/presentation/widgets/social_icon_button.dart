import 'package:flutter/material.dart';
import 'package:itaaleem/core/theme/brand_colors.dart';

const _socialIcons = <String, IconData>{
  'facebook': Icons.facebook_rounded,
  'whatsapp': Icons.chat_outlined,
  'youtube': Icons.smart_display_outlined,
  'tiktok': Icons.tiktok,
  'instagram': Icons.camera_alt_outlined,
  'telegram': Icons.telegram,
  'website': Icons.language_rounded,
  'twitter': Icons.alternate_email_rounded,
};

const _socialLabels = <String, String>{
  'facebook': 'فيسبوك',
  'whatsapp': 'واتساب',
  'youtube': 'يوتيوب',
  'tiktok': 'تيك توك',
  'instagram': 'إنستجرام',
  'telegram': 'تليجرام',
  'website': 'الموقع',
  'twitter': 'إكس',
};

/// Whether [platform] has an icon (unknown platforms aren't rendered).
bool isKnownSocialPlatform(String platform) =>
    _socialIcons.containsKey(platform);

/// A round, brand-tinted button for one of a center's social platforms
/// (facebook/whatsapp/youtube/tiktok/instagram/telegram/website). Renders
/// nothing for an unrecognized key, so callers can iterate unfiltered.
class SocialIconButton extends StatelessWidget {
  const SocialIconButton({
    super.key,
    required this.platform,
    required this.onTap,
    this.size = 44,
  });

  final String platform;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = _socialIcons[platform];
    if (icon == null) return const SizedBox.shrink();
    final color = BrandColors.of(platform, Theme.of(context).colorScheme);

    return Tooltip(
      message: _socialLabels[platform] ?? platform,
      child: Material(
        color: color.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, color: color, size: size * 0.5),
          ),
        ),
      ),
    );
  }
}

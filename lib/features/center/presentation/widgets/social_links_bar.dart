import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/center/presentation/widgets/social_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:url_launcher/url_launcher.dart';

/// The entries of [socialLinks] that can actually be shown: a known
/// platform with a non-empty url, in the server's order.
List<MapEntry<String, String>> usableSocialLinks(
  Map<String, String?> socialLinks,
) => [
  for (final e in socialLinks.entries)
    if (isKnownSocialPlatform(e.key) && (e.value?.trim().isNotEmpty ?? false))
      MapEntry(e.key, e.value!.trim()),
];

/// Whether [SocialLinksBar] would render anything for [socialLinks].
bool hasUsableSocialLinks(Map<String, String?> socialLinks) =>
    usableSocialLinks(socialLinks).isNotEmpty;

/// A row of [SocialIconButton]s for a [CenterModel.socialLinks] map — one
/// per known platform with a non-empty URL, each opening outside the app.
/// Renders nothing if there are no usable entries, so callers can drop it
/// in unconditionally.
class SocialLinksBar extends StatelessWidget {
  const SocialLinksBar({
    super.key,
    required this.socialLinks,
    this.iconSize = 44,
    this.title = 'تابعنا',
  });

  final Map<String, String?> socialLinks;
  final double iconSize;

  /// Small secondary label above the icons; `null` for none.
  final String? title;

  Future<void> _open(BuildContext context, String platform, String url) async {
    var target = url;
    // A bare WhatsApp number → wa.me.
    if (platform == 'whatsapp' && !target.contains('://')) {
      final digits = target.replaceAll(RegExp(r'[^0-9]'), '');
      target = 'https://wa.me/$digits';
    } else if (!target.contains('://')) {
      target = 'https://$target';
    }
    final uri = Uri.tryParse(target);
    final launched =
        uri != null &&
        await launchUrlSafely(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      AppToast.showError(context, 'تعذر فتح الرابط');
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = usableSocialLinks(socialLinks);
    if (entries.isEmpty) return const SizedBox.shrink();

    final row = Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final entry in entries)
          SocialIconButton(
            platform: entry.key,
            size: iconSize,
            onTap: () => _open(context, entry.key, entry.value),
          ),
      ],
    );
    if (title == null) return Center(child: row);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title!,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        row,
      ],
    );
  }
}

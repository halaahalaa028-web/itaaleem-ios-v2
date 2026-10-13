import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppSnackType { success, error, info }

/// Short success/error feedback only (never data like numbers or links —
/// those go in a [showAppSheet]). Floating, rounded, with an icon, tinted
/// by [type], gone after 3 seconds.
void showAppSnack(
  BuildContext context,
  String message, {
  AppSnackType type = AppSnackType.success,
}) {
  switch (type) {
    case AppSnackType.success:
      AppToast.showSuccess(context, message);
    case AppSnackType.error:
      AppToast.showError(context, message);
    case AppSnackType.info:
      AppToast.showInfo(context, message);
  }
}

/// The app's one bottom-sheet look: drag handle, an icon + title (and
/// optional subtitle), then [builder]'s content, max 720 wide on tablets,
/// lifted above the keyboard.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  IconData? icon,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      final text = Theme.of(sheetContext).textTheme;
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: scheme.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.base),
              builder(sheetContext),
            ],
          ),
        ),
      );
    },
  );
}

/// A soft content card inside an [showAppSheet].
class AppSheetCard extends StatelessWidget {
  const AppSheetCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

/// Egyptian mobile numbers (01xxxxxxxxx) in [text], also when written with
/// Arabic-Indic digits or a +20 prefix. Normalized to `01xxxxxxxxx`.
List<String> findEgyptianPhones(String text) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final western = text.split('').map((c) {
    final i = arabic.indexOf(c);
    return i >= 0 ? '$i' : c;
  }).join();
  final matches = RegExp(
    r'(?:\+?20|0020)?\s*(1[0125](?:[\s-]?\d){8})|(01[0125](?:[\s-]?\d){8})',
  ).allMatches(western);
  final phones = <String>{};
  for (final m in matches) {
    final raw = (m.group(1) ?? m.group(2) ?? '').replaceAll(RegExp(r'\D'), '');
    phones.add(raw.startsWith('0') ? raw : '0$raw');
  }
  return phones.toList();
}

/// "اتصال" / "واتساب" / copy for one phone number — the sheet's way of
/// showing a number instead of a SnackBar.
class PhoneActions extends StatelessWidget {
  const PhoneActions({super.key, required this.phone});

  /// `01xxxxxxxxx` (any other format is dialed as-is).
  final String phone;

  /// Egyptian `0…` → `20…` for wa.me; anything else keeps its digits.
  static String _waNumber(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.startsWith('0') ? '20${digits.substring(1)}' : digits;
  }

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrlSafely(
      uri,
      mode: uri.scheme == 'tel'
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      showAppSnack(context, 'تعذر الفتح', type: AppSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                phone,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            IconButton(
              tooltip: 'نسخ الرقم',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: phone));
                if (context.mounted) showAppSnack(context, 'تم نسخ الرقم');
              },
              icon: Icon(Icons.copy_rounded, color: scheme.primary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    _open(context, Uri(scheme: 'tel', path: phone)),
                icon: const Icon(Icons.call_rounded, size: 20),
                label: const Text('اتصال'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: radius),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _open(
                  context,
                  Uri.parse('https://wa.me/${_waNumber(phone)}'),
                ),
                icon: const Icon(Icons.chat_rounded, size: 20),
                label: const Text('واتساب'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: radius),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

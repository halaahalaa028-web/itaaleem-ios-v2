import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';
import 'package:itaaleem/features/settings/presentation/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// The store link from `rate_app`, or `null` while it's off / missing.
final rateAppUrlProvider = Provider<String?>((ref) {
  final settings = ref.watch(appSettingsProvider).valueOrNull;
  if (settings == null || !settings.rateAppEnabled) return null;
  return settings.rateAppUrl;
});

/// Opens the store page outside the app.
Future<void> openRateApp(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final ok =
      uri != null &&
      await launchUrlSafely(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) AppToast.showError(context, 'تعذر فتح الرابط');
}

/// Lectures seen completed, across subjects. Device-level on purpose (kept
/// out of the logout wipe list) — the prompt is about the app, not the
/// account.
const _completedKey = 'rate_prompt_completed_ids';
const _shownKey = 'rate_prompt_shown';
const _threshold = 5;

/// Android only: once the student has completed [_threshold] lectures, a
/// light one-time "عاجبك التطبيق؟" sheet. Never again after it's shown.
Future<void> maybePromptRateApp(
  BuildContext context,
  WidgetRef ref,
  Iterable<int> completedLessonIds,
) async {
  if (PlatformUtils.isIOS) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_shownKey) ?? false) return;
  final ids = {...?prefs.getStringList(_completedKey)}
    ..addAll(completedLessonIds.map((e) => '$e'));
  await prefs.setStringList(_completedKey, ids.toList());
  if (ids.length < _threshold) return;
  final url = ref.read(rateAppUrlProvider);
  if (url == null || !context.mounted) return;
  await prefs.setBool(_shownKey, true);
  if (!context.mounted) return;

  final rate = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final text = Theme.of(sheetContext).textTheme;
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
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
              Icon(Icons.star_rounded, size: 44, color: scheme.primary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'عاجبك التطبيق؟ قيّمه',
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'رأيك بيفرق معانا وبيساعد طلاب تانيين يلاقونا',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.base),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('قيّم الآن'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: const Text('لاحقاً'),
              ),
            ],
          ),
        ),
      );
    },
  );
  await waitForRouteExit();
  if (rate == true && context.mounted) await openRateApp(context, url);
}

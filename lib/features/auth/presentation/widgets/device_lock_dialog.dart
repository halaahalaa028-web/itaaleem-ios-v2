import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:itaaleem/features/center/domain/entities/center_model.dart';
import 'package:itaaleem/features/settings/presentation/providers/settings_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// Explains a `device_limit` rejection (at login, or mid-session after the
/// center admin reset the student's devices) in a dialog rather than a
/// passing toast, with a way to reach whoever can move the account.
///
/// "تواصل مع الإدارة" prefers the [center]'s WhatsApp/phone when known, then
/// the platform's support WhatsApp/phone, and finally the support screen.
Future<void> showDeviceLockDialog(
  BuildContext context,
  WidgetRef ref, {
  String? message,
  CenterModel? center,
}) {
  final text = (message == null || message.trim().isEmpty)
      ? deviceLockFallbackMessage
      : message;
  final colorScheme = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        Icons.phonelink_lock_rounded,
        size: 40,
        color: colorScheme.error,
      ),
      title: const Text(
        'الحساب مفتوح على جهاز آخر',
        textAlign: TextAlign.center,
      ),
      content: Text(text, textAlign: TextAlign.center),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('حسنًا'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.support_agent_rounded),
          label: const Text('تواصل مع الإدارة'),
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            final uri = await _contactUri(ref, center);
            if (uri != null &&
                await launchUrlSafely(
                  uri,
                  mode: LaunchMode.externalApplication,
                )) {
              return;
            }
            if (context.mounted) context.push(supportPath);
          },
        ),
      ],
    ),
  );
}

Future<Uri?> _contactUri(WidgetRef ref, CenterModel? center) async {
  Uri? whatsapp(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (v.startsWith('http')) return Uri.tryParse(v);
    final digits = v.replaceAll(RegExp('[^0-9]'), '');
    return digits.isEmpty ? null : Uri.parse('https://wa.me/$digits');
  }

  Uri? tel(String? v) =>
      (v == null || v.trim().isEmpty) ? null : Uri(scheme: 'tel', path: v);

  if (center != null) {
    final uri =
        whatsapp(center.socialLinks['whatsapp']) ??
        tel(center.phoneNumbers.isEmpty ? null : center.phoneNumbers.first);
    if (uri != null) return uri;
  }
  try {
    final settings = await ref.read(appSettingsProvider.future);
    return whatsapp(settings.whatsappNumber) ?? tel(settings.supportPhone);
  } catch (_) {
    return null;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/features/auth/data/account_data_wiper.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';

/// Logs out — first asking for confirmation when offline videos would be
/// deleted with the account's data (see `wipeAccountData`).
Future<void> confirmAndLogout(BuildContext context, WidgetRef ref) async {
  if (await hasOfflineVideos(ref)) {
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.download_done_rounded),
        title: const Text('تسجيل الخروج'),
        content: const Text('سيتم حذف الفيديوهات المحملة من هذا الجهاز'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }
  await ref.read(authControllerProvider.notifier).logout();
}

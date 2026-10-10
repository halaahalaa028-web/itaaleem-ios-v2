import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_models.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';
import 'package:itaaleem/features/center_admin/providers/center_admin_providers.dart';

/// Cancel / reactivate / cancel-all for subscriptions — shared by the
/// subscriptions list, the students list and the student detail screen.
///
/// Every sheet only returns its values; the API call and the toast run here
/// through [runAdminAction], which captures the container and the root
/// context before awaiting (the row that opened the sheet is usually
/// rebuilt away by the refresh).

/// The server keeps two subscription kinds in separate tables (ids can
/// collide), so cancel/reactivate must say which one a row is.
String? subscriptionKind(AdminRecord r) =>
    r.text(['kind', 'subscription_kind', 'source', 'type']);

Map<String, dynamic> _withKind(
  AdminRecord r, [
  Map<String, dynamic> extra = const {},
]) => {if (subscriptionKind(r) != null) 'kind': subscriptionKind(r), ...extra};

bool isSubscriptionCancelled(AdminRecord r) =>
    r.status == 'cancelled' || r.status == 'canceled';

/// `POST subscriptions/{id}/cancel {kind, reason?}` after a confirmation
/// sheet with an optional reason.
Future<void> cancelSubscription(
  BuildContext context,
  WidgetRef ref,
  AdminRecord sub, {
  required String studentName,
}) async {
  final values = await showAdminForm(
    context,
    title: 'إلغاء اشتراك $studentName؟ الطالب هيفقد الوصول للمحتوى فورًا.',
    submitLabel: 'تأكيد الإلغاء',
    fields: const [
      AdminField(
        'reason',
        'سبب الإلغاء (اختياري)',
        icon: Icons.notes_rounded,
        maxLines: 2,
      ),
    ],
  );
  if (values == null || !context.mounted) return;
  await runAdminAction(
    context,
    ref,
    () => ref
        .read(centerAdminRepositoryProvider)
        .action('subscriptions/${sub.id}/cancel', _withKind(sub, values)),
    success: 'تم إلغاء الاشتراك',
  );
}

/// `POST students/{id}/subscriptions/cancel-all {reason?}` after a
/// confirmation sheet; toasts the server's message ("تم إلغاء 3 اشتراك").
Future<void> cancelAllStudentSubscriptions(
  BuildContext context,
  WidgetRef ref, {
  required int studentId,
  required String studentName,
}) async {
  final values = await showAdminForm(
    context,
    title:
        'سيتم إلغاء كل اشتراكات الطالب $studentName، '
        'ولن يستطيع الوصول للمحتوى المدفوع',
    submitLabel: 'إلغاء كل الاشتراكات',
    fields: const [
      AdminField(
        'reason',
        'سبب الإلغاء (اختياري)',
        icon: Icons.notes_rounded,
        maxLines: 2,
      ),
    ],
  );
  if (values == null || !context.mounted) return;
  await runAdminAction<String>(
    context,
    ref,
    () => ref
        .read(centerAdminRepositoryProvider)
        .cancelAllSubscriptions(studentId, reason: values['reason'] as String?),
    success: 'تم إلغاء كل اشتراكات الطالب',
    successOf: (message) => message,
  );
}

/// `POST subscriptions/{id}/reactivate {kind, extend_days?}`. A 422 shows
/// the server's message; when the period already ended, the admin is asked
/// for the number of days and it's retried with `extend_days`.
Future<void> reactivateSubscription(
  BuildContext context,
  WidgetRef ref,
  AdminRecord sub,
) async {
  final repo = ref.read(centerAdminRepositoryProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final toastContext = Navigator.of(context, rootNavigator: true).context;
  final path = 'subscriptions/${sub.id}/reactivate';
  try {
    await repo.action(path, _withKind(sub));
  } on ValidationFailure catch (f) {
    if (!context.mounted) return;
    if (!_needsDays(sub, f.message)) {
      AppToast.showError(context, f.message);
      return;
    }
    final values = await showAdminForm(
      context,
      title: '${f.message}\nكام يوم تحب تمدّ الاشتراك؟',
      submitLabel: 'إعادة التفعيل',
      fields: const [
        AdminField(
          'extend_days',
          'عدد الأيام',
          icon: Icons.more_time_rounded,
          initial: '30',
          numeric: true,
          required: true,
        ),
      ],
    );
    if (values == null || !context.mounted) return;
    await runAdminAction(
      context,
      ref,
      () => repo.action(path, _withKind(sub, values)),
      success: 'تم إعادة تفعيل الاشتراك',
    );
    return;
  } catch (e) {
    if (toastContext.mounted) {
      AppToast.showError(toastContext, failureOf(e).message);
    }
    return;
  }
  invalidateAdminContainer(container);
  if (toastContext.mounted) {
    AppToast.showSuccess(toastContext, 'تم إعادة تفعيل الاشتراك');
  }
}

/// "Already active" needs nothing; an ended period needs `extend_days`.
bool _needsDays(AdminRecord sub, String message) {
  final m = message.toLowerCase();
  if (m.contains('نشط') || m.contains('active')) return false;
  final end = sub.date(['expires_at', 'end_date', 'ends_at']);
  return m.contains('extend') ||
      m.contains('أيام') ||
      m.contains('ايام') ||
      m.contains('مدة') ||
      m.contains('مده') ||
      m.contains('انته') ||
      m.contains('expired') ||
      (end != null && end.isBefore(DateTime.now()));
}

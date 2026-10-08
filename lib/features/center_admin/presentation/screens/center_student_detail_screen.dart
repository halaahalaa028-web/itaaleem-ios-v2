import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_error_state.dart';
import 'package:itaaleem/core/widgets/app_progress_bar.dart';
import 'package:itaaleem/core/widgets/app_shimmer.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_models.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_subscription_actions.dart';
import 'package:itaaleem/features/center_admin/providers/center_admin_providers.dart';

/// `GET /center-admin/students/{id}` — profile, subscriptions (activate /
/// suspend each), per-subject progress (watch % + exam scores).
class CenterStudentDetailScreen extends ConsumerWidget {
  const CenterStudentDetailScreen({
    super.key,
    required this.studentId,
    this.preview,
  });

  final int studentId;

  /// The list row, shown instantly while the full record loads.
  final AdminRecord? preview;

  String get _path => 'students/$studentId';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(centerAdminRecordProvider(_path));
    final student = async.valueOrNull ?? preview;

    return Scaffold(
      appBar: AppBar(title: Text(student?.title ?? 'تفاصيل الطالب')),
      body: AppBackground(
        child: RefreshIndicator(
          onRefresh: () {
            ref.invalidate(centerStudentSubscriptionsProvider(studentId));
            return ref.refresh(centerAdminRecordProvider(_path).future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (student != null) _ProfileCard(student: student),
              if (student != null)
                _ResetDevicesButton(
                  studentId: studentId,
                  studentName: student.title,
                ),
              if (async.isLoading && async.valueOrNull == null) ...[
                const SizedBox(height: AppSpacing.lg),
                const ShimmerList(count: 3),
              ] else if (async.hasError && async.valueOrNull == null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: AppErrorState(
                    message: failureOf(async.error!).message,
                    onRetry: () =>
                        ref.invalidate(centerAdminRecordProvider(_path)),
                  ),
                )
              else if (async.valueOrNull case final full?) ...[
                _Subscriptions(student: full, studentId: studentId),
                _Progress(student: full),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `POST students/{id}/reset-devices` after a confirmation — for a student
/// who changed phones and is now blocked by the one-device lock.
class _ResetDevicesButton extends ConsumerWidget {
  const _ResetDevicesButton({
    required this.studentId,
    required this.studentName,
  });

  final int studentId;
  final String studentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.phonelink_erase_rounded),
        label: const Text('إعادة تعيين الأجهزة'),
        onPressed: () async {
          final ok = await confirmAdmin(
            context,
            title: 'إعادة تعيين أجهزة $studentName',
            message:
                'سيتم تسجيل خروج الطالب من كل الأجهزة، '
                'ويقدر يدخل من جهاز جديد',
            confirmLabel: 'إعادة التعيين',
            destructive: true,
          );
          if (!ok || !context.mounted) return;
          await runAdminAction<String>(
            context,
            ref,
            () => ref
                .read(centerAdminRepositoryProvider)
                .resetStudentDevices(studentId),
            success: 'تم إعادة تعيين أجهزة الطالب',
            successOf: (message) => message,
          );
        },
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.student});

  final AdminRecord student;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final watch = student.number([
      'watch_percentage',
      'videos_watch_percentage',
      'overall_progress',
    ]);
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          children: [
            AdminAvatar(
              name: student.title,
              imageUrl: student.image,
              radius: 40,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              student.title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.md),
            AdminInfoRow(
              icon: Icons.phone_rounded,
              label: 'الهاتف',
              value: student.phone,
            ),
            AdminInfoRow(
              icon: Icons.email_rounded,
              label: 'الإيميل',
              value: student.email,
            ),
            AdminInfoRow(
              icon: Icons.class_rounded,
              label: 'الصف',
              value: student.nestedName('grade'),
            ),
            AdminInfoRow(
              icon: Icons.event_rounded,
              label: 'تاريخ التسجيل',
              value: adminDate(student.date(['created_at', 'joined_at'])),
            ),
            AdminInfoRow(
              icon: Icons.history_rounded,
              label: 'آخر نشاط',
              value: adminAgo(
                student.date([
                  'last_activity_at',
                  'last_active_at',
                  'last_seen_at',
                ]),
              ),
            ),
            if (watch != null) ...[
              const SizedBox(height: AppSpacing.md),
              _PercentBar(label: 'نسبة مشاهدة الفيديوهات', percent: watch),
            ],
          ],
        ),
      ),
    );
  }
}

/// `GET students/{id}/subscriptions` — every subscription (active and
/// cancelled, both kinds); per row: activate/suspend, cancel or
/// reactivate, plus "إلغاء كل الاشتراكات" for the student.
class _Subscriptions extends ConsumerWidget {
  const _Subscriptions({required this.student, required this.studentId});

  final AdminRecord student;
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(centerStudentSubscriptionsProvider(studentId));
    // The detail payload's own list while the dedicated call loads/fails.
    final subs = async.valueOrNull ?? student.list('subscriptions');
    final repo = ref.read(centerAdminRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;
    final anyActive = subs.any((s) => !isSubscriptionCancelled(s));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSectionTitle(
          'الاشتراكات (${subs.length})',
          action: anyActive
              ? TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: () => cancelAllStudentSubscriptions(
                    context,
                    ref,
                    studentId: studentId,
                    studentName: student.title,
                  ),
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: const Text('إلغاء كل الاشتراكات'),
                )
              : null,
        ),
        if (async.isLoading && subs.isEmpty)
          const ShimmerList(count: 2)
        else if (subs.isEmpty)
          const Text('لا توجد اشتراكات لهذا الطالب')
        else
          for (final s in subs)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AdminRecordCard(
                title:
                    s.nestedName('subject') ??
                    s.nestedName('package') ??
                    s.title,
                lines: [
                  'من ${adminDate(s.date(['starts_at', 'start_date']))} '
                      'إلى ${adminDate(s.date(['expires_at', 'end_date', 'ends_at']))}',
                ],
                trailing: adminStatusBadge(s.status),
                menu: [
                  if (isSubscriptionCancelled(s))
                    AdminMenuAction(
                      'إعادة التفعيل',
                      Icons.restart_alt_rounded,
                      () => reactivateSubscription(context, ref, s),
                    )
                  else ...[
                    if (s.status == 'active')
                      AdminMenuAction(
                        'إيقاف',
                        Icons.pause_circle_rounded,
                        () => runAdminAction(
                          context,
                          ref,
                          () => repo.action('subscriptions/${s.id}/suspend'),
                          success: 'تم إيقاف الاشتراك',
                        ),
                      )
                    else
                      AdminMenuAction(
                        'تفعيل',
                        Icons.play_circle_rounded,
                        () => runAdminAction(
                          context,
                          ref,
                          () => repo.action('subscriptions/${s.id}/activate'),
                          success: 'تم تفعيل الاشتراك',
                        ),
                      ),
                    AdminMenuAction(
                      'إلغاء هذه المادة',
                      Icons.cancel_rounded,
                      () => cancelSubscription(
                        context,
                        ref,
                        s,
                        studentName: student.title,
                      ),
                      destructive: true,
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.student});

  final AdminRecord student;

  @override
  Widget build(BuildContext context) {
    final progress = [
      ...student.list('progress'),
      ...student.list('subjects_progress'),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSectionTitle('التقدم في المواد'),
        if (progress.isEmpty)
          const Text('لا توجد بيانات تقدم بعد')
        else
          for (final p in progress)
            Card(
              elevation: 1,
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.nestedName('subject') ?? p.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _PercentBar(
                      label: 'المشاهدة',
                      percent:
                          p.number([
                            'watch_percentage',
                            'progress',
                            'percentage',
                          ]) ??
                          0,
                    ),
                    if (p.number([
                          'exams_average',
                          'average_score',
                          'exam_average',
                        ])
                        case final avg?) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _PercentBar(label: 'متوسط الامتحانات', percent: avg),
                    ],
                    for (final e in p.list('exams'))
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          '• ${e.title}: ${e.number(['percentage', 'score']) ?? '—'}%',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _PercentBar extends StatelessWidget {
  const _PercentBar({required this.label, required this.percent});

  final String label;
  final num percent;

  @override
  Widget build(BuildContext context) {
    final p = (percent <= 1 && percent > 0 ? percent * 100 : percent)
        .clamp(0, 100)
        .toDouble();
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: text.bodySmall)),
            Text(
              '${p.round()}%',
              style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        AppProgressBar(progress: p / 100, height: 6),
      ],
    );
  }
}

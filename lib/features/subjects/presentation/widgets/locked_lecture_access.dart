import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/features/subjects/presentation/providers/subjects_providers.dart';
import 'package:itaaleem/features/subjects/presentation/widgets/subject_detail/subject_access_card.dart';

/// Back to the subject's page (where the "اشترك في المادة" card lives),
/// opening its code sheet right away.
void openSubjectActivation(BuildContext context, WidgetRef ref, int subjectId) {
  ref.read(pendingActivationSheetProvider.notifier).state = subjectId;
  // Lectures are always opened from their subject's page.
  if (context.canPop()) {
    context.pop();
  } else {
    context.push('/subject-detail/$subjectId');
  }
}

/// Under a locked lecture: a short note that it belongs to a subject, and a
/// "فعّل المادة" button back to that subject's activation card. All the
/// access options (code / request / purchase) live on the subject page.
class LockedLectureAccess extends ConsumerWidget {
  const LockedLectureAccess({super.key, required this.subjectId});

  final int subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final subject = ref.watch(
      subjectDetailsProvider(subjectId).select((s) => s.valueOrNull),
    );
    final name = subject?.name.trim() ?? '';
    // This lecture is locked, so the subject page shows a card.
    final canActivate =
        subject != null &&
        effectiveAccessCard(subject, hasLockedLessons: true) != null;
    final radius = BorderRadius.circular(12);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: radius,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.lock_rounded, color: scheme.primary, size: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  name.isEmpty
                      ? 'المحاضرة دي ضمن المادة'
                      : 'المحاضرة دي ضمن مادة $name',
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (canActivate) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => openSubjectActivation(context, ref, subjectId),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: radius),
              ),
              child: const Text('فعّل المادة'),
            ),
          ],
        ],
      ),
    );
  }
}

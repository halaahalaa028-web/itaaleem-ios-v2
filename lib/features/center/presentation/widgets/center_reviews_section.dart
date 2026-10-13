import 'package:flutter/material.dart';
import 'package:itaaleem/core/widgets/app_shimmer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/widgets/app_button.dart';
import 'package:itaaleem/core/widgets/app_card.dart';
import 'package:itaaleem/core/widgets/empty_state.dart';
import 'package:itaaleem/core/widgets/section_header.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/center/data/models/center_review.dart';
import 'package:itaaleem/features/center/presentation/providers/reviews_providers.dart';
import 'package:itaaleem/features/center/presentation/widgets/review_widgets.dart';

/// Edit/delete menu for the student's own review — shared by the home
/// section and the full reviews screen.
class OwnReviewMenu extends ConsumerWidget {
  const OwnReviewMenu({
    super.key,
    required this.centerId,
    required this.review,
  });

  final int centerId;
  final CenterReview review;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف التقييم'),
        content: const Text('متأكد إنك عايز تحذف تقييمك؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'حذف',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.palette.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref
          .read(reviewsControllerProvider(centerId).notifier)
          .delete(review.id);
      if (context.mounted) AppToast.showSuccess(context, 'تم حذف تقييمك');
    } catch (e) {
      if (context.mounted) AppToast.showError(context, failureOf(e).message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: context.palette.textTertiary),
      onSelected: (v) {
        if (v == 'edit') {
          showReviewSheet(context, centerId: centerId, existing: review);
        } else {
          _delete(context, ref);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('تعديل')),
        PopupMenuItem(value: 'delete', child: Text('حذف')),
      ],
    );
  }
}

/// Home-screen ratings block: average + count + distribution, the latest 3
/// comments, "see all", and the add/edit CTA for the student's own review.
class CenterReviewsSection extends ConsumerWidget {
  const CenterReviewsSection({
    super.key,
    required this.centerId,
    this.fallbackRating = 0,
  });

  final int centerId;

  /// The center's own `rating` — used when the reviews endpoint doesn't
  /// send an average.
  final double fallbackRating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reviewsControllerProvider(centerId));
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'التقييمات',
            onSeeAll: (async.valueOrNull?.items.isNotEmpty ?? false)
                ? () => context.push('$centerReviewsPath/$centerId')
                : null,
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          ),
          async.when(
            loading: () => const AppShimmer(
              child: Column(
                children: [
                  ShimmerCard(thumbnailSize: 40),
                  SizedBox(height: AppSpacing.listItemSpacing),
                  ShimmerCard(thumbnailSize: 40),
                ],
              ),
            ),
            error: (e, _) => AppCard(
              child: Column(
                children: [
                  Text(
                    'تعذر تحميل التقييمات',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton.text(
                    'إعادة المحاولة',
                    onPressed: () =>
                        ref.invalidate(reviewsControllerProvider(centerId)),
                  ),
                ],
              ),
            ),
            data: (state) => _Content(
              centerId: centerId,
              state: state,
              fallbackRating: fallbackRating,
            ),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.centerId,
    required this.state,
    required this.fallbackRating,
  });

  final int centerId;
  final ReviewsState state;
  final double fallbackRating;

  @override
  Widget build(BuildContext context) {
    final items = state.items;
    final count = state.summary?.count ?? state.total ?? items.length;
    final computed = items.isEmpty
        ? 0.0
        : items.fold<int>(0, (a, r) => a + r.rating) / items.length;
    final average =
        state.summary?.average ??
        (fallbackRating > 0 ? fallbackRating : computed);
    final mine = state.mine;
    final others = items.where((r) => !r.isOwner).take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryCard(
          average: average,
          count: count,
          distribution: state.summary?.distribution,
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: OutlinedButton.icon(
            onPressed: () =>
                showReviewSheet(context, centerId: centerId, existing: mine),
            icon: Icon(
              mine == null ? Icons.star_outline_rounded : Icons.edit_outlined,
              size: 18,
            ),
            label: Text(mine == null ? 'أضف تقييمك' : 'تعديل تقييمك'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(160, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        if (mine != null) ...[
          const SizedBox(height: AppSpacing.base),
          const _Label('تقييمك'),
          ReviewCard(
            review: mine,
            trailing: OwnReviewMenu(centerId: centerId, review: mine),
          ),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.base),
          const _Label('آخر التعليقات'),
          for (final r in others)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ReviewCard(review: r),
            ),
        ] else if (items.isEmpty)
          const EmptyState(
            message: 'لا توجد تقييمات بعد — كن أول من يقيّم',
            verticalPadding: AppSpacing.md,
          ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// One row: the big average with stars + count on the start side, the
/// 5★→1★ bars on the other. Without a distribution: number + stars only,
/// centered.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.average,
    required this.count,
    required this.distribution,
  });

  final double average;
  final int count;
  final Map<int, int>? distribution;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dist = distribution;
    final total = dist == null ? 0 : dist.values.fold<int>(0, (a, b) => a + b);
    final hasBars = dist != null && total > 0;

    final score = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          average.toStringAsFixed(1),
          style: text.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        StarRow(rating: average, size: 16),
        const SizedBox(height: 2),
        Text(
          '$count تقييم',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: hasBars
          ? Row(
              children: [
                score,
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var star = 5; star >= 1; star--)
                        _DistributionBar(
                          star: star,
                          fraction: (dist[star] ?? 0) / total,
                        ),
                    ],
                  ),
                ),
              ],
            )
          : Center(child: score),
    );
  }
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({required this.star, required this.fraction});

  final int star;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Row(
              children: [
                Text('$star', style: small),
                Icon(Icons.star_rounded, size: 11, color: context.palette.gold),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 5,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(context.palette.gold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

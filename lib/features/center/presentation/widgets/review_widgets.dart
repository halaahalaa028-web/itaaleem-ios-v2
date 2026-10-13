import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_sheet.dart';
import 'package:itaaleem/features/center/data/models/center_review.dart';
import 'package:itaaleem/features/center/presentation/providers/reviews_providers.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';

/// Read-only row of gold stars for [rating] (supports halves for averages).
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, this.size = 16});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star_rounded
                : rating >= i - 0.5
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded,
            size: size,
            color: rating >= i - 0.5
                ? context.palette.gold
                : Theme.of(context).colorScheme.outlineVariant,
          ),
      ],
    );
  }
}

/// Tappable 1–5 star selector (light haptic on every tap).
class StarPicker extends StatelessWidget {
  const StarPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 44,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              onChanged(i);
            },
            iconSize: size,
            padding: const EdgeInsets.all(AppSpacing.xs),
            constraints: const BoxConstraints(),
            icon: AnimatedScale(
              scale: i <= value ? 1.08 : 1,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                color: i <= value
                    ? context.palette.gold
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// "من يومين"، "من أسبوع"... for [date].
String relativeArabicDate(DateTime date, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(date.toLocal());
  if (diff.inMinutes < 1) return 'دلوقتي';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return m == 1
        ? 'من دقيقة'
        : m == 2
        ? 'من دقيقتين'
        : 'من $m دقيقة';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return h == 1
        ? 'من ساعة'
        : h == 2
        ? 'من ساعتين'
        : 'من $h ساعات';
  }
  final d = diff.inDays;
  if (d == 1) return 'امبارح';
  if (d == 2) return 'من يومين';
  if (d < 7) return 'من $d أيام';
  if (d < 14) return 'من أسبوع';
  if (d < 30) return 'من ${d ~/ 7} أسابيع';
  if (d < 60) return 'من شهر';
  if (d < 365) return 'من ${d ~/ 30} شهور';
  return d < 730 ? 'من سنة' : 'من ${d ~/ 365} سنين';
}

/// A calm, stable color per name — hue-shifted from the theme's primary so
/// it always matches the app (and gets darker/lighter with the theme).
Color nameColor(String name, ColorScheme scheme) {
  const shifts = [0.0, 40.0, 80.0, 150.0, 200.0, 260.0, 310.0];
  final hash = name.runes.fold<int>(0, (a, r) => (a * 31 + r) & 0x7fffffff);
  final base = HSLColor.fromColor(scheme.primary);
  final dark = scheme.brightness == Brightness.dark;
  return base
      .withHue((base.hue + shifts[hash % shifts.length]) % 360)
      .withSaturation(0.45)
      .withLightness(dark ? 0.35 : 0.55)
      .toColor();
}

/// The student's photo, or the name's first letter in a [nameColor] circle.
class ReviewerAvatar extends StatelessWidget {
  const ReviewerAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.radius = 20,
  });

  final String name;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    final url = avatarUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: nameColor(trimmed, scheme),
      foregroundImage: url == null || url.isEmpty
          ? null
          : CachedNetworkImageProvider(url),
      child: Text(
        trimmed.isEmpty ? '؟' : trimmed.characters.first,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: radius * 0.85,
          fontWeight: FontWeight.w800,
          color: scheme.onPrimary,
        ),
      ),
    );
  }
}

/// One review: avatar, name + small stars, relative date, then the comment
/// (3 lines, "عرض المزيد"). Compact when there's no comment.
class ReviewCard extends StatefulWidget {
  const ReviewCard({super.key, required this.review, this.trailing});

  final CenterReview review;

  /// e.g. an edit/delete menu on the student's own review.
  final Widget? trailing;

  @override
  State<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<ReviewCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final review = widget.review;
    final created = review.createdAt;
    final comment = review.comment;
    final commentStyle = text.bodyMedium?.copyWith(height: 1.6);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReviewerAvatar(
                name: review.studentName,
                avatarUrl: review.studentAvatar,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            review.isOwner
                                ? '${review.studentName} (تقييمك)'
                                : review.studentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        StarRow(rating: review.rating.toDouble(), size: 14),
                      ],
                    ),
                    if (created != null || !review.isApproved)
                      Row(
                        children: [
                          if (created != null)
                            Text(
                              relativeArabicDate(created),
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          if (review.isOwner && !review.isApproved) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'بانتظار الموافقة',
                                style: text.labelSmall?.copyWith(
                                  color: scheme.onTertiaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              ?widget.trailing,
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final painter = TextPainter(
                  text: TextSpan(text: comment, style: commentStyle),
                  maxLines: 3,
                  textDirection: Directionality.of(context),
                )..layout(maxWidth: constraints.maxWidth);
                final overflows = painter.didExceedMaxLines;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment,
                      maxLines: _expanded ? null : 3,
                      overflow: _expanded ? null : TextOverflow.ellipsis,
                      style: commentStyle,
                    ),
                    if (overflows)
                      GestureDetector(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            _expanded ? 'عرض أقل' : 'عرض المزيد',
                            style: text.labelMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// "أضف تقييمك" / "تعديل تقييمك" sheet: big stars, optional comment,
/// "إرسال". Reloads the reviews on success.
Future<void> showReviewSheet(
  BuildContext context, {
  required int centerId,
  CenterReview? existing,
}) async {
  final sent = await showAppSheet<bool>(
    context: context,
    title: existing == null ? 'أضف تقييمك' : 'تعديل تقييمك',
    subtitle: 'ما تقييمك للسنتر؟',
    builder: (_) => _ReviewForm(centerId: centerId, existing: existing),
  );
  await waitForRouteExit();
  if (sent != true || !context.mounted) return;
  showAppSnack(
    context,
    existing == null
        ? 'شكرًا! تقييمك هيظهر بعد مراجعة إدارة المركز'
        : 'تم تحديث تقييمك، هيظهر بعد مراجعة إدارة المركز',
  );
}

class _ReviewForm extends ConsumerStatefulWidget {
  const _ReviewForm({required this.centerId, this.existing});

  final int centerId;
  final CenterReview? existing;

  @override
  ConsumerState<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends ConsumerState<_ReviewForm> {
  late int _rating = widget.existing?.rating ?? 0;
  late final _comment = TextEditingController(text: widget.existing?.comment);
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_rating == 0) {
      setState(() => _error = 'اختار عدد النجوم الأول');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final controller = ref.read(
      reviewsControllerProvider(widget.centerId).notifier,
    );
    final text = _comment.text.trim();
    try {
      final existing = widget.existing;
      if (existing == null) {
        await controller.submit(_rating, text);
      } else {
        await controller.updateReview(existing.id, _rating, text);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = failureOf(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StarPicker(
          value: _rating,
          onChanged: (v) => setState(() {
            _rating = v;
            _error = null;
          }),
        ),
        const SizedBox(height: AppSpacing.base),
        TextField(
          controller: _comment,
          enabled: !_sending,
          minLines: 3,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            hintText: 'اكتب تعليقك (اختياري)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.base),
        FilledButton(
          onPressed: _sending ? null : _send,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _sending
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('إرسال'),
        ),
      ],
    );
  }
}

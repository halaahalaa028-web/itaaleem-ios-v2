import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:itaaleem/features/subjects/domain/entities/subject.dart';
import 'package:itaaleem/features/subjects/presentation/widgets/subject_icon.dart';

/// Wide cover for a subject card / header: its `icon_url` filling the box,
/// or a soft gradient in the subject's palette color with a large icon. Used
/// as the Hero (`subject-cover-<id>`) between the list and the detail page.
class SubjectCover extends StatelessWidget {
  const SubjectCover({super.key, required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final url = subject.iconUrl;
    final fallback = _Fallback(subject: subject);
    if (url == null || url.isEmpty) return fallback;
    return LayoutBuilder(
      builder: (context, constraints) => CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.high,
        memCacheWidth: constraints.hasBoundedWidth
            ? (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                  .round()
            : null,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final color = SubjectIcon.colorFor(subject.id);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Center(
        child: SubjectIcon(
          iconUrl: null,
          seed: subject.id,
          name: subject.name,
          size: 64,
          iconSize: 34,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

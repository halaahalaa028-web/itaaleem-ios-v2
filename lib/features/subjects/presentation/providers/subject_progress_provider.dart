import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/providers/cache_for.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/features/courses/domain/entities/lecture_details.dart';
import 'package:itaaleem/features/subjects/domain/entities/subject.dart';

/// Each lesson's saved playback progress, keyed by lesson id — one
/// `GET /subjects/{id}/progress` for the whole subject (it used to fan out
/// a `/lessons/{id}/progress` call per lecture, which tripped the rate
/// limit on subjects with many lectures).
final subjectLessonsProgressProvider = FutureProvider.autoDispose
    .family<Map<int, LectureProgress>, int>((ref, subjectId) {
      return ref.cached(() async {
        final response = await ref
            .read(dioClientProvider)
            .get<dynamic>(ApiEndpoints.subjectProgress(subjectId));
        return parseSubjectProgress(response.data);
      }, duration: const Duration(minutes: 1));
    });

/// `{progress: {"52": {watched_seconds, total_seconds, percentage,
/// completed | is_completed}}}` (also accepts it nested under `data`).
Map<int, LectureProgress> parseSubjectProgress(Object? body) {
  Object? raw = body;
  if (raw is Map && raw['data'] is Map) raw = raw['data'];
  if (raw is Map && raw['progress'] is Map) raw = raw['progress'];
  if (raw is! Map) return const {};
  int toInt(Object? v) => num.tryParse('${v ?? ''}')?.toInt() ?? 0;
  final result = <int, LectureProgress>{};
  raw.forEach((key, value) {
    final id = int.tryParse('$key');
    if (id == null || value is! Map) return;
    result[id] = LectureProgress(
      positionSeconds: toInt(value['watched_seconds'] ?? value['position']),
      durationSeconds: toInt(value['total_seconds'] ?? value['duration']),
      progressPercentage:
          num.tryParse('${value['percentage'] ?? ''}')?.toDouble() ?? 0,
      isCompleted: value['completed'] == true || value['is_completed'] == true,
    );
  });
  if (kDebugMode) {
    debugPrint('[subjectLessonsProgress] ${result.length} lessons');
  }
  return result;
}

/// 0.0–1.0 watched fraction of one lesson; position/duration wins when both
/// are known, since `progress_percentage` is reported on a 0–100 scale.
double lessonWatchedFraction(LectureProgress p) {
  if (p.isCompleted) return 1;
  if (p.durationSeconds > 0 && p.positionSeconds > 0) {
    return (p.positionSeconds / p.durationSeconds).clamp(0.0, 1.0);
  }
  return (p.progressPercentage / 100).clamp(0.0, 1.0);
}

/// What the subject screen needs out of [subjectLessonsProgressProvider]:
/// which lessons are done / in progress, the "آخر مشاهدة" one, and where
/// "متابعة التعلم" should land.
class SubjectProgressSummary {
  const SubjectProgressSummary._({
    required this.total,
    required this.completedIds,
    required this.inProgress,
    required this.lastWatchedId,
    required this.continueLesson,
  });

  /// [lessons] must already be in display order.
  factory SubjectProgressSummary.from(
    List<SubjectLesson> lessons,
    Map<int, LectureProgress> progress,
  ) {
    final completed = <int>{};
    final inProgress = <int, double>{};
    for (final lesson in lessons) {
      final p = progress[lesson.id];
      if (p == null) continue;
      final fraction = lessonWatchedFraction(p);
      if (fraction >= 0.9) {
        completed.add(lesson.id);
      } else if (fraction > 0 || p.positionSeconds > 5) {
        inProgress[lesson.id] = fraction;
      }
    }

    // The API keeps no "watched at" timestamp, so the furthest lesson the
    // student has touched stands in for the most recently watched one:
    // the last one in progress, else the last one completed.
    int? lastWatched;
    for (final lesson in lessons.reversed) {
      if (inProgress.containsKey(lesson.id)) {
        lastWatched = lesson.id;
        break;
      }
    }
    if (lastWatched == null) {
      for (final lesson in lessons.reversed) {
        if (completed.contains(lesson.id)) {
          lastWatched = lesson.id;
          break;
        }
      }
    }

    // Resume the lesson in progress; otherwise move on to the first lesson
    // after the last finished one (or start from the very first).
    SubjectLesson? target;
    if (lastWatched != null && inProgress.containsKey(lastWatched)) {
      target = lessons.firstWhere((l) => l.id == lastWatched);
    } else if (lessons.isNotEmpty) {
      final lastIndex = lastWatched == null
          ? -1
          : lessons.indexWhere((l) => l.id == lastWatched);
      target = lessons
          .skip(lastIndex + 1)
          .firstWhere(
            (l) => !completed.contains(l.id),
            orElse: () => lessons[lastIndex < 0 ? 0 : lastIndex],
          );
    }

    return SubjectProgressSummary._(
      total: lessons.length,
      completedIds: completed,
      inProgress: inProgress,
      lastWatchedId: lastWatched,
      continueLesson: target,
    );
  }

  final int total;
  final Set<int> completedIds;

  /// Lesson id → watched fraction, for lessons started but not finished.
  final Map<int, double> inProgress;
  final int? lastWatchedId;
  final SubjectLesson? continueLesson;

  int get completedCount => completedIds.length;
  double get fraction => total == 0 ? 0 : completedCount / total;
  bool get hasStarted => completedIds.isNotEmpty || inProgress.isNotEmpty;
}

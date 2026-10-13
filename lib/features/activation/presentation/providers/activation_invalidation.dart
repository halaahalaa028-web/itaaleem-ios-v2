import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/content/content_policy.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/courses/presentation/providers/courses_providers.dart';
import 'package:itaaleem/features/exams/presentation/providers/exams_providers.dart';
import 'package:itaaleem/features/home/presentation/providers/home_subjects_provider.dart';
import 'package:itaaleem/features/subjects/presentation/providers/subjects_providers.dart';

/// After a successful `POST /activate-code`: reload everything whose lock
/// state may have changed (subjects, lectures, exams, files, watermark) and
/// the student's profile, so newly unlocked content shows up right away.
void invalidateAfterActivation(WidgetRef ref) {
  ref.invalidate(coursesProvider);
  ref.invalidate(availableCoursesProvider);
  ref.invalidate(homeSubjectsProvider);
  ref.invalidate(subjectsListProvider);
  ref.invalidate(subjectDetailsProvider);
  ref.invalidate(homeLessonsProvider);
  ref.invalidate(attachmentsProvider);
  ref.invalidate(lessonAttachmentsProvider);
  ref.invalidate(examsListProvider);
  ref.invalidate(subjectExamsProvider);
  ref.invalidate(lectureExamsProvider);
  ref.invalidate(examDetailsProvider);
  ref.invalidate(lessonWatermarkProvider);
  unawaited(ref.read(authControllerProvider.notifier).refreshProfile());
}

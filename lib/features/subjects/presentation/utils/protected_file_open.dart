import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/app/router/route_args.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/utils/open_file_in_app.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/subjects/data/content_file_access.dart';
import 'package:itaaleem/features/subjects/domain/entities/subject.dart';
import 'package:itaaleem/features/subjects/presentation/widgets/lesson_access.dart';
import 'package:itaaleem/features/subjects/presentation/widgets/lesson_pdf_view.dart';

/// Opens a lesson's own PDF — or, when it's locked for this student, drops
/// any cached copy and shows the same sheet as a locked video (on iOS the
/// "contact the center" sheet). The viewer is never opened while locked.
Future<void> openLessonPdf(BuildContext context, SubjectLesson lesson) async {
  if (lesson.pdfLocked) {
    await LessonPdfView.evictCache(lesson.pdfRef);
    if (context.mounted) {
      await showPaidContentSheet(context, lessonId: lesson.id);
    }
    return;
  }
  await context.push<void>(
    lessonPdfPath,
    extra: LessonPdfArgs(
      title: lesson.title,
      pdfUrl: lesson.pdfUrl,
      downloadable: lesson.isDownloadable,
      fileRef: lesson.pdfRef,
    ),
  );
}

/// Same for a subject attachment: lock sheet when locked; PDFs go to the
/// in-app viewer with their stable [ContentFileRef]; other files get a
/// fresh signed URL first (they expire after ~10 minutes).
Future<void> openAttachment(
  BuildContext context,
  WidgetRef ref,
  SubjectAttachment file, {
  bool lessonLocked = false,
}) async {
  final fileRef = file.ref;
  if (file.isLocked || lessonLocked) {
    if (fileRef != null) await LessonPdfView.evictCache(fileRef);
    if (context.mounted) {
      await showPaidContentSheet(context, lessonId: file.lessonId);
    }
    return;
  }
  if (file.isPdf) {
    await context.push<void>(
      lessonPdfPath,
      extra: LessonPdfArgs(
        title: file.name,
        pdfUrl: file.url.isEmpty ? null : file.url,
        downloadable: file.isDownloadable,
        fileRef: fileRef,
      ),
    );
    return;
  }
  var url = file.url;
  if (fileRef != null) {
    try {
      url = await resolveContentUrl(ref.read(dioClientProvider), fileRef);
    } on ContentLockedException catch (e) {
      if (context.mounted) AppToast.showError(context, e.displayMessage);
      return;
    } catch (_) {
      // Fall back to the URL we have.
    }
  }
  if (!context.mounted) return;
  await openFileInApp(
    context,
    url,
    title: file.name,
    type: file.type,
    downloadable: file.isDownloadable,
  );
}

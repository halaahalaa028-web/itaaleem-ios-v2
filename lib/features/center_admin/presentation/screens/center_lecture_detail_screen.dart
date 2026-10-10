import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/utils/open_file_in_app.dart';
import 'package:itaaleem/core/widgets/app_error_state.dart';
import 'package:itaaleem/core/widgets/app_shimmer.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_models.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';
import 'package:itaaleem/features/center_admin/providers/center_admin_providers.dart';

/// `GET /center-admin/lectures/{id}` — one lecture: info, its videos and
/// its attachments (`files` / `attachments` / `pdfs` inside the record).
class CenterLectureDetailScreen extends ConsumerWidget {
  const CenterLectureDetailScreen({
    super.key,
    required this.lectureId,
    this.preview,
  });

  final int lectureId;
  final AdminRecord? preview;

  String get _path => 'lectures/$lectureId';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(centerAdminRecordProvider(_path));
    final lecture = async.valueOrNull ?? preview;
    final full = async.valueOrNull;
    final videos = full == null
        ? const <AdminRecord>[]
        : [...full.list('videos'), ...full.list('lesson_videos')];
    final files = full == null
        ? const <AdminRecord>[]
        : [
            ...full.list('attachments'),
            ...full.list('files'),
            ...full.list('pdfs'),
          ];

    return Scaffold(
      appBar: AppBar(title: Text(lecture?.title ?? 'تفاصيل المحاضرة')),
      body: AppBackground(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(centerAdminRecordProvider(_path).future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (lecture != null)
                GlassCard(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AdminInfoRow(
                        icon: Icons.menu_book_rounded,
                        label: 'المادة',
                        value: lecture.nestedName('subject'),
                      ),
                      AdminInfoRow(
                        icon: Icons.person_rounded,
                        label: 'المدرس',
                        value:
                            lecture.nestedName('teacher') ??
                            lecture.text(['teacher_name']),
                      ),
                      AdminInfoRow(
                        icon: Icons.visibility_rounded,
                        label: 'المشاهدات',
                        value:
                            '${lecture.count(['views_count', 'views', 'watch_count']) ?? 0}',
                      ),
                      AdminInfoRow(
                        icon: Icons.event_rounded,
                        label: 'تاريخ الإضافة',
                        value: adminDate(lecture.date(['created_at'])),
                      ),
                      if (lecture.text(['description']) case final d?) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(d),
                      ],
                    ],
                  ),
                ),
              if (async.isLoading && full == null) ...[
                const SizedBox(height: AppSpacing.lg),
                const ShimmerList(count: 3),
              ] else if (async.hasError && full == null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: AppErrorState(
                    message: failureOf(async.error!).message,
                    onRetry: () =>
                        ref.invalidate(centerAdminRecordProvider(_path)),
                  ),
                )
              else if (full != null) ...[
                AdminSectionTitle('الفيديوهات (${videos.length})'),
                if (videos.isEmpty)
                  const Text('لا توجد فيديوهات في هذه المحاضرة')
                else
                  for (final v in videos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AdminRecordCard(
                        title: v.title,
                        leading: const AdminAvatar(
                          name: '',
                          icon: Icons.play_arrow_rounded,
                        ),
                        lines: [
                          if (v.count(['duration_minutes']) case final m?)
                            '$m دقيقة',
                        ],
                      ),
                    ),
                AdminSectionTitle('المرفقات (${files.length})'),
                if (files.isEmpty)
                  const Text('لا توجد مرفقات في هذه المحاضرة')
                else
                  for (final f in files)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _AttachmentRow(file: f),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.file});

  final AdminRecord file;

  @override
  Widget build(BuildContext context) {
    final url = ApiEndpoints.mediaUrl(
      file.text(['url', 'file_url', 'path', 'file']),
    );
    return AdminRecordCard(
      title: file.title,
      leading: const AdminAvatar(
        name: '',
        icon: Icons.insert_drive_file_rounded,
      ),
      lines: [
        adminDate(file.date(['created_at'])),
      ],
      onTap: url == null
          ? null
          : () => openFileInApp(context, url, title: file.title),
    );
  }
}

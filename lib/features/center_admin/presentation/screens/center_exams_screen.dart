import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_models.dart';
import 'package:itaaleem/features/center_admin/presentation/center_admin_routes.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_data_table.dart';

/// `GET /center-admin/exams` — filter by subject; tap for student results.
class CenterExamsScreen extends StatefulWidget {
  const CenterExamsScreen({super.key});

  @override
  State<CenterExamsScreen> createState() => _CenterExamsScreenState();
}

class _CenterExamsScreenState extends State<CenterExamsScreen> {
  int? _subjectId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الامتحانات')),
      body: AppBackground(
        child: AdminDataTable(
          path: 'exams',
          filters: {'subject_id': _subjectId},
          searchHint: 'ابحث بعنوان الامتحان',
          emptyTitle: 'لا توجد امتحانات',
          emptyIcon: Icons.quiz_outlined,
          header: AdminSubjectFilter(
            selected: _subjectId,
            onChanged: (id) => setState(() => _subjectId = id),
          ),
          itemBuilder: (context, r) {
            final avg = r.number(['average_score', 'average', 'avg_score']);
            return AdminRecordCard(
              title: r.title,
              leading: const AdminAvatar(name: '', icon: Icons.quiz_rounded),
              lines: [
                r.nestedName('subject'),
                [
                  if (r.count(['questions_count']) case final q?) '$q سؤال',
                  if (r.count(['attempts_count', 'attempts']) case final a?)
                    '$a محاولة',
                  if (avg != null) 'المتوسط ${avg.round()}%',
                ].join(' • '),
              ],
              onTap: () => context.push(centerAdminExamPath(r.id), extra: r),
            );
          },
        ),
      ),
    );
  }
}

/// One exam, two tabs: النتائج (`GET exams/{id}/results`) and الأسئلة
/// (`GET exams/{id}/questions`, with the correct answer marked).
class CenterExamResultsScreen extends StatelessWidget {
  const CenterExamResultsScreen({
    super.key,
    required this.examId,
    this.preview,
  });

  final int examId;
  final AdminRecord? preview;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(preview?.title ?? 'الامتحان'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'النتائج'),
              Tab(text: 'الأسئلة'),
            ],
          ),
        ),
        body: AppBackground(
          child: TabBarView(
            children: [
              _results(),
              _ExamQuestions(examId: examId),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results() {
    return AdminDataTable(
      path: 'exams/$examId/results',
      searchHint: 'ابحث باسم الطالب',
      emptyTitle: 'لم يحل أحد هذا الامتحان بعد',
      emptyIcon: Icons.fact_check_outlined,
      itemBuilder: (context, r) {
        final name = r.nestedName('student') ?? r.title;
        final pct = r.number(['percentage', 'score_percentage', 'score']);
        final passed = r.flag(['is_passed', 'passed']);
        return AdminRecordCard(
          title: name,
          leading: AdminAvatar(
            name: name,
            imageUrl: r.nested('student')?.image,
          ),
          lines: [
            adminDate(r.date(['submitted_at', 'created_at'])),
          ],
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pct == null ? '—' : '${pct.round()}%',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (passed != null)
                adminStatusBadge(passed ? 'active' : 'expired'),
            ],
          ),
        );
      },
    );
  }
}

class _ExamQuestions extends StatelessWidget {
  const _ExamQuestions({required this.examId});

  final int examId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AdminDataTable(
      path: 'exams/$examId/questions',
      emptyTitle: 'لا توجد أسئلة في هذا الامتحان',
      emptyIcon: Icons.help_outline_rounded,
      itemBuilder: (context, q) {
        final options = [
          ...q.list('options'),
          ...q.list('answers'),
          ...q.list('choices'),
        ];
        final correctText = q.text(['correct_answer', 'answer']);
        bool isCorrect(AdminRecord o) =>
            o.flag(['is_correct', 'correct']) ??
            (correctText != null &&
                (o.text(['text', 'option', 'answer', 'title', 'label']) ==
                        correctText ||
                    '${o.id}' == correctText));
        return GlassCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                q.text(['question', 'text', 'title', 'body']) ?? '—',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              for (final o in options)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(
                        isCorrect(o)
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: isCorrect(o)
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          o.text([
                                'text',
                                'option',
                                'answer',
                                'title',
                                'label',
                              ]) ??
                              '—',
                          style: isCorrect(o)
                              ? TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              if (options.isEmpty && correctText != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'الإجابة الصحيحة: $correctText',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

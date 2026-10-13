import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_models.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_data_table.dart';
import 'package:itaaleem/features/center_admin/providers/center_admin_providers.dart';
import 'package:share_plus/share_plus.dart';

/// A code's state as the list shows it.
enum _CodeState { available, used, disabled, expired }

extension on _CodeState {
  String get label => switch (this) {
    _CodeState.available => 'متاح',
    _CodeState.used => 'مستخدم',
    _CodeState.disabled => 'موقوف',
    _CodeState.expired => 'منتهي',
  };
}

/// `GET /center-admin/activation-codes` (paginated, searchable, filtered by
/// status / batch / course) + "توليد أكواد": a whole course or one subject,
/// up to 1000 at once, as a named batch (`POST activation-codes
/// {scope_type, grade_id, subject_id, count, batch_name, expires_at,
/// duration_days}`). The older "several subjects + months" form is kept in
/// the ⋮ menu. Each code: copy, disable; each batch: show, disable.
class CenterActivationCodesScreen extends ConsumerStatefulWidget {
  const CenterActivationCodesScreen({super.key});

  static String? codeOf(AdminRecord r) =>
      r.text(['code', 'activation_code', 'value']);

  @override
  ConsumerState<CenterActivationCodesScreen> createState() =>
      _CenterActivationCodesScreenState();
}

/// The server's `status` when it's one of ours; otherwise derived: used
/// (a student/used_at/is_used), expired (a past `expires_at`), available.
_CodeState _stateOf(AdminRecord r) {
  final s = r.status ?? '';
  for (final st in _CodeState.values) {
    if (s == st.name) return st;
  }
  if (s.contains('disable') || s == 'inactive') return _CodeState.disabled;
  if (s.contains('used') && !s.contains('unused') ||
      r.flag(['is_used', 'used']) == true ||
      r.date(['used_at', 'redeemed_at']) != null ||
      r.nestedName('student') != null ||
      r.nestedName('used_by') != null) {
    return _CodeState.used;
  }
  final expires = r.date(['expires_at', 'expiry_date', 'valid_until']);
  if (s.contains('expire') ||
      (expires != null && expires.isBefore(DateTime.now()))) {
    return _CodeState.expired;
  }
  return _CodeState.available;
}

/// What the code opens: "مادة: …" (+ its course), the legacy subjects
/// list, or — for an older code with no subject — "كورس كامل".
String _scopeOf(AdminRecord r) {
  final grade = r.text(['grade_name']) ?? r.nestedName('grade');
  final subject = r.text(['subject_name']) ?? r.nestedName('subject');
  if (subject != null) return ['مادة: $subject', ?grade].join(' — ');
  final names = r.list('subjects').map((s) => s.title).toList();
  if (names.isNotEmpty) return names.join('، ');
  return grade == null ? 'كورس كامل' : 'كورس كامل: $grade';
}

class _CenterActivationCodesScreenState
    extends ConsumerState<CenterActivationCodesScreen> {
  _CodeState? _status;
  int? _gradeId;
  String? _gradeName;
  int? _subjectId;
  String? _subjectName;
  ({String id, String name})? _batch;

  Future<void> _generate() async {
    final result = await showModalBottomSheet<GeneratedCodesBatch>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _GenerateCodesSheet(),
    );
    if (result == null) return;
    await _showCreated(result);
  }

  /// The older form: several subjects + months.
  Future<void> _createLegacy() async {
    final created = await showModalBottomSheet<List<AdminRecord>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _CreateCodeSheet(),
    );
    if (created == null) return;
    await _showCreated(GeneratedCodesBatch(codes: created));
  }

  Future<void> _showCreated(GeneratedCodesBatch result) async {
    await waitForRouteExit();
    if (!mounted) return;
    invalidateAdminSection(ref, 'activation-codes');
    final batchId = result.batchId;
    if (batchId != null) {
      setState(
        () => _batch = (id: batchId, name: result.batchName ?? 'المجموعة'),
      );
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CreatedCodesSheet(
        batchName: result.batchName,
        codes: [
          for (final r in result.codes)
            if (CenterActivationCodesScreen.codeOf(r) case final c?) c,
        ],
      ),
    );
  }

  Future<void> _pickCourse() async {
    final List<AdminRecord> courses;
    try {
      courses = await ref.read(centerCoursesProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (courses.isEmpty) {
      AppToast.showError(context, 'لا توجد كورسات');
      return;
    }
    final picked = await showModalBottomSheet<AdminRecord>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.clear_all_rounded),
            title: const Text('كل الكورسات'),
            onTap: () => Navigator.pop(context, const AdminRecord({})),
          ),
          for (final c in courses)
            ListTile(
              leading: const Icon(Icons.school_rounded),
              title: Text(c.title),
              selected: c.id == _gradeId,
              onTap: () => Navigator.pop(context, c),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await waitForRouteExit();
    if (!mounted) return;
    setState(() {
      _gradeId = picked.id > 0 ? picked.id : null;
      _gradeName = picked.id > 0 ? picked.title : null;
      _subjectId = null;
      _subjectName = null;
    });
  }

  /// The subject filter — the chosen course's subjects.
  Future<void> _pickSubject() async {
    final gradeId = _gradeId;
    if (gradeId == null) {
      AppToast.showError(context, 'اختر الكورس الأول');
      return;
    }
    final List<AdminRecord> subjects;
    try {
      subjects = await ref.read(centerCourseSubjectsProvider(gradeId).future);
    } catch (e) {
      if (mounted) AppToast.showError(context, failureOf(e).message);
      return;
    }
    if (!mounted) return;
    if (subjects.isEmpty) {
      AppToast.showError(context, 'لا توجد مواد في هذا الكورس');
      return;
    }
    final picked = await showModalBottomSheet<AdminRecord>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.clear_all_rounded),
            title: const Text('كل المواد'),
            onTap: () => Navigator.pop(context, const AdminRecord({})),
          ),
          for (final s in subjects)
            ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: Text(s.title),
              selected: s.id == _subjectId,
              onTap: () => Navigator.pop(context, s),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await waitForRouteExit();
    if (!mounted) return;
    setState(() {
      _subjectId = picked.id > 0 ? picked.id : null;
      _subjectName = picked.id > 0 ? picked.title : null;
    });
  }

  Future<void> _disableCode(AdminRecord r) async {
    final code = CenterActivationCodesScreen.codeOf(r) ?? '';
    final ok = await confirmAdmin(
      context,
      title: 'إيقاف الكود',
      message: 'إيقاف الكود $code؟ لن يمكن استخدامه بعد ذلك.',
      confirmLabel: 'إيقاف',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await runAdminAction(
      context,
      ref,
      () => ref
          .read(centerAdminRepositoryProvider)
          .action('activation-codes/${r.id}/disable'),
      success: 'تم إيقاف الكود',
    );
  }

  Future<void> _disableBatch(String batchId, String name) async {
    final ok = await confirmAdmin(
      context,
      title: 'إيقاف المجموعة',
      message:
          'إيقاف كل الأكواد غير المستخدمة في "$name"؟ لا يمكن التراجع عن ذلك.',
      confirmLabel: 'إيقاف المجموعة',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await runAdminAction(
      context,
      ref,
      () => ref
          .read(centerAdminRepositoryProvider)
          .action('activation-codes/batches/$batchId/disable'),
      success: 'تم إيقاف المجموعة',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final batch = _batch;

    final filters = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in <_CodeState?>[null, ..._CodeState.values])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: AppSpacing.sm,
                    ),
                    child: ChoiceChip(
                      label: Text(f?.label ?? 'الكل'),
                      selected: _status == f,
                      onSelected: (_) => setState(() => _status = f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              InputChip(
                avatar: const Icon(Icons.school_rounded, size: 18),
                label: Text(_gradeName ?? 'كل الكورسات'),
                onPressed: _pickCourse,
                onDeleted: _gradeId == null
                    ? null
                    : () => setState(() {
                        _gradeId = null;
                        _gradeName = null;
                        _subjectId = null;
                        _subjectName = null;
                      }),
              ),
              if (_gradeId != null)
                InputChip(
                  avatar: const Icon(Icons.menu_book_rounded, size: 18),
                  label: Text(_subjectName ?? 'كل المواد'),
                  onPressed: _pickSubject,
                  onDeleted: _subjectId == null
                      ? null
                      : () => setState(() {
                          _subjectId = null;
                          _subjectName = null;
                        }),
                ),
              if (batch != null) ...[
                InputChip(
                  avatar: const Icon(Icons.inventory_2_rounded, size: 18),
                  label: Text('المجموعة: ${batch.name}'),
                  onDeleted: () => setState(() => _batch = null),
                ),
                ActionChip(
                  avatar: Icon(
                    Icons.block_rounded,
                    size: 18,
                    color: scheme.error,
                  ),
                  label: Text(
                    'إيقاف المجموعة',
                    style: TextStyle(color: scheme.error),
                  ),
                  onPressed: () => _disableBatch(batch.id, batch.name),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('أكواد التفعيل'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'legacy') _createLegacy();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'legacy',
                child: Text('إنشاء أكواد لعدة مواد (الطريقة القديمة)'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('توليد أكواد'),
      ),
      body: AppBackground(
        child: AdminDataTable(
          path: 'activation-codes',
          filters: {
            'status': _status?.name,
            'grade_id': _gradeId,
            'subject_id': _subjectId,
            'batch_id': batch?.id,
          },
          searchHint: 'ابحث بالكود',
          header: filters,
          emptyTitle: 'لا توجد أكواد',
          emptyIcon: Icons.vpn_key_outlined,
          bottomPadding: 96,
          itemBuilder: (context, r) {
            final code = CenterActivationCodesScreen.codeOf(r) ?? '—';
            final state = _stateOf(r);
            final scope = _scopeOf(r);
            final months = r.count(['duration_months']);
            final days = r.count(['duration_days']);
            final batchId = r.text(['batch_id']);
            final batchName = r.text(['batch_name']);
            final usedBy =
                r.nestedName('student') ??
                r.nestedName('used_by') ??
                r.text(['student_name', 'used_by_name']);
            final expires = r.date(['expires_at']);
            return AdminRecordCard(
              title: code,
              leading: AdminAvatar(
                name: '',
                icon: switch (state) {
                  _CodeState.available => Icons.vpn_key_rounded,
                  _CodeState.used => Icons.how_to_reg_rounded,
                  _CodeState.disabled => Icons.block_rounded,
                  _CodeState.expired => Icons.timer_off_rounded,
                },
              ),
              lines: [
                if (scope.isNotEmpty) scope,
                [
                  if (batchName != null) 'المجموعة: $batchName',
                  if (usedBy != null) 'استخدمه: $usedBy',
                  if (days != null) '$days يوم',
                  if (days == null && months != null) '$months شهر',
                  if (expires != null) 'ينتهي ${adminDate(expires)}',
                ].join(' • '),
              ],
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StateChip(state: state),
                  IconButton(
                    tooltip: 'نسخ',
                    icon: Icon(Icons.copy_rounded, color: scheme.primary),
                    onPressed: () => _copy(context, code),
                  ),
                ],
              ),
              menu: [
                if (state == _CodeState.available)
                  AdminMenuAction(
                    'إيقاف الكود',
                    Icons.block_rounded,
                    () => _disableCode(r),
                    destructive: true,
                  ),
                if (batchId != null) ...[
                  AdminMenuAction(
                    'عرض أكواد المجموعة',
                    Icons.inventory_2_rounded,
                    () => setState(
                      () => _batch = (id: batchId, name: batchName ?? batchId),
                    ),
                  ),
                  AdminMenuAction(
                    'إيقاف المجموعة',
                    Icons.block_rounded,
                    () => _disableBatch(batchId, batchName ?? batchId),
                    destructive: true,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final _CodeState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (state) {
      _CodeState.available => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      _CodeState.used => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _CodeState.disabled => (scheme.errorContainer, scheme.onErrorContainer),
      _CodeState.expired => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        state.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// "توليد أكواد" — always one subject (`scope_type: subject`): course →
/// subject → count (1–1000) → duration in days → batch name (optional) →
/// expiry (optional).
class _GenerateCodesSheet extends ConsumerStatefulWidget {
  const _GenerateCodesSheet();

  @override
  ConsumerState<_GenerateCodesSheet> createState() =>
      _GenerateCodesSheetState();
}

class _GenerateCodesSheetState extends ConsumerState<_GenerateCodesSheet> {
  static const _maxCount = 1000;

  final _formKey = GlobalKey<FormState>();
  final _count = TextEditingController(text: '50');
  final _batchName = TextEditingController();
  final _days = TextEditingController(text: '30');
  int? _courseId;
  int? _subjectId;
  DateTime? _expiresAt;
  bool _submitting = false;

  @override
  void dispose() {
    _count.dispose();
    _batchName.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 90)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) setState(() => _expiresAt = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(centerAdminRepositoryProvider)
          .generateActivationCodes(
            scopeType: 'subject',
            gradeId: _courseId!,
            subjectId: _subjectId,
            count: int.parse(_count.text.trim()),
            batchName: _batchName.text,
            expiresAt: _expiresAt,
            durationDays: int.tryParse(_days.text.trim()),
          );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppToast.showError(context, failureOf(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final coursesAsync = ref.watch(centerCoursesProvider);
    final courseId = _courseId;
    final subjectsAsync = courseId == null
        ? null
        : ref.watch(centerCourseSubjectsProvider(courseId));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'توليد أكواد تفعيل',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.base),
              coursesAsync.when(
                loading: () => const ShimmerBox(height: 56, radius: 12),
                error: (e, _) => _InlineRetry(
                  message: failureOf(e).message,
                  onRetry: () => ref.invalidate(centerCoursesProvider),
                ),
                data: (courses) => DropdownButtonFormField<int>(
                  initialValue: _courseId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'الكورس',
                    prefixIcon: Icon(Icons.school_rounded),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in courses)
                      DropdownMenuItem(value: c.id, child: Text(c.title)),
                  ],
                  onChanged: (v) => setState(() {
                    _courseId = v;
                    _subjectId = null;
                  }),
                  validator: (v) => v == null ? 'اختر الكورس' : null,
                ),
              ),
              if (subjectsAsync != null) ...[
                const SizedBox(height: AppSpacing.md),
                subjectsAsync.when(
                  loading: () => const ShimmerBox(height: 56, radius: 12),
                  error: (e, _) => _InlineRetry(
                    message: failureOf(e).message,
                    onRetry: () =>
                        ref.invalidate(centerCourseSubjectsProvider(courseId!)),
                  ),
                  data: (subjects) => DropdownButtonFormField<int>(
                    key: ValueKey(courseId),
                    initialValue: _subjectId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'المادة',
                      prefixIcon: Icon(Icons.menu_book_rounded),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final s in subjects)
                        DropdownMenuItem(value: s.id, child: Text(s.title)),
                    ],
                    onChanged: (v) => setState(() => _subjectId = v),
                    validator: (v) => v == null ? 'اختر المادة' : null,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _count,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  labelText: 'عدد الأكواد',
                  helperText: 'من 1 إلى 1000 كود في المرة',
                  prefixIcon: Icon(Icons.numbers_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null) return 'اكتب عدد الأكواد';
                  if (n < 1) return 'أقل عدد كود واحد';
                  if (n > _maxCount) return 'أقصى عدد $_maxCount كود في المرة';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _days,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  labelText: 'مدة الاشتراك بالأيام',
                  prefixIcon: Icon(Icons.timelapse_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n < 1) return 'اكتب المدة بالأيام';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _batchName,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'اسم المجموعة (اختياري)',
                  hintText: 'مثال: دفعة أكتوبر',
                  prefixIcon: Icon(Icons.inventory_2_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _pickExpiry,
                icon: const Icon(Icons.event_rounded),
                label: Text(
                  _expiresAt == null
                      ? 'تاريخ انتهاء الأكواد (اختياري)'
                      : 'تنتهي الأكواد: ${adminDate(_expiresAt)}',
                ),
              ),
              if (_expiresAt != null)
                TextButton(
                  onPressed: () => setState(() => _expiresAt = null),
                  child: const Text('بدون تاريخ انتهاء'),
                ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.vpn_key_rounded),
                label: const Text('توليد الأكواد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _copy(BuildContext context, String code) {
  Clipboard.setData(ClipboardData(text: code));
  AppToast.showSuccess(context, 'تم نسخ الكود');
}

class _CreateCodeSheet extends ConsumerStatefulWidget {
  const _CreateCodeSheet();

  @override
  ConsumerState<_CreateCodeSheet> createState() => _CreateCodeSheetState();
}

class _CreateCodeSheetState extends ConsumerState<_CreateCodeSheet> {
  static const _maxCount = 500;

  final _formKey = GlobalKey<FormState>();
  final _count = TextEditingController(text: '10');
  final _selected = <int>{};
  int _months = 1;
  bool _submitting = false;
  String? _subjectsError;

  static const _durations = <(int, String)>[
    (1, 'شهر'),
    (3, '3 شهور'),
    (6, '6 شهور'),
    (12, 'سنة'),
  ];

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final countOk = _formKey.currentState?.validate() ?? false;
    setState(
      () => _subjectsError = _selected.isEmpty
          ? 'اختر مادة واحدة على الأقل'
          : null,
    );
    if (!countOk || _selected.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      final created = await ref
          .read(centerAdminRepositoryProvider)
          .createActivationCodes(
            count: int.parse(_count.text.trim()),
            subjectIds: _selected.toList(),
            durationMonths: _months,
          );
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppToast.showError(context, failureOf(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final subjectsAsync = ref.watch(centerSubjectsListProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إنشاء أكواد تفعيل',
                style: text.titleMedium?.copyWith(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              TextFormField(
                controller: _count,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: const InputDecoration(
                  labelText: 'عدد الأكواد',
                  helperText: 'من 1 إلى 500 كود في المرة',
                  prefixIcon: Icon(Icons.numbers_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null) return 'اكتب عدد الأكواد';
                  if (n < 1) return 'أقل عدد كود واحد';
                  if (n > _maxCount) return 'أقصى عدد $_maxCount كود في المرة';
                  return null;
                },
              ),
              Row(
                children: [
                  const Expanded(child: AdminSectionTitle('المواد')),
                  if (subjectsAsync.valueOrNull case final subjects?
                      when subjects.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        final all = subjects.map((s) => s.id).toSet();
                        if (_selected.containsAll(all)) {
                          _selected.clear();
                        } else {
                          _selected.addAll(all);
                          _subjectsError = null;
                        }
                      }),
                      child: Text(
                        _selected.length == subjects.length
                            ? 'إلغاء التحديد'
                            : 'كل المواد',
                      ),
                    ),
                ],
              ),
              subjectsAsync.when(
                loading: () => const ShimmerBox(height: 40, radius: 999),
                error: (e, _) => Text(failureOf(e).message),
                data: (subjects) => Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final s in subjects)
                      FilterChip(
                        label: Text(s.title),
                        selected: _selected.contains(s.id),
                        onSelected: (on) => setState(() {
                          on ? _selected.add(s.id) : _selected.remove(s.id);
                          if (on) _subjectsError = null;
                        }),
                      ),
                  ],
                ),
              ),
              if (_subjectsError != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _subjectsError!,
                    style: text.bodySmall?.copyWith(color: scheme.error),
                  ),
                ),
              const AdminSectionTitle('مدة الاشتراك'),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final (months, label) in _durations)
                    ChoiceChip(
                      label: Text(label),
                      selected: _months == months,
                      onSelected: (_) => setState(() => _months = months),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.vpn_key_rounded),
                label: const Text('إنشاء الأكواد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The codes just created: copy one, copy all, or share them as text.
class _CreatedCodesSheet extends StatelessWidget {
  const _CreatedCodesSheet({required this.codes, this.batchName});

  final List<String> codes;
  final String? batchName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final all = codes.join('\n');
    final batch = batchName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            codes.isEmpty ? 'تم إنشاء الأكواد' : 'تم إنشاء ${codes.length} كود',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (batch != null && batch.isNotEmpty)
            Text(
              'المجموعة: $batch',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          if (codes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
              child: Text(
                'هتلاقي الأكواد الجديدة في القائمة',
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            const SizedBox(height: AppSpacing.md),
            // Up to 1000 codes: a bounded, lazily built list.
            SizedBox(
              height: (codes.length * 56.0).clamp(
                56.0,
                MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: ListView.separated(
                itemCount: codes.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, i) => Container(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.base,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          codes[i],
                          textDirection: TextDirection.ltr,
                          style: text.titleMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'نسخ',
                        icon: Icon(
                          Icons.copy_rounded,
                          color: scheme.onPrimaryContainer,
                        ),
                        onPressed: () => _copy(context, codes[i]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: all));
                      AppToast.showSuccess(context, 'تم نسخ كل الأكواد');
                    },
                    icon: const Icon(Icons.copy_all_rounded),
                    label: const Text('نسخ كل الأكواد'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                        text: [
                          'أكواد التفعيل${batch == null ? '' : ' — $batch'}:',
                          all,
                        ].join('\n'),
                      ),
                    ),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('مشاركة'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A form field's load error: the message and "إعادة المحاولة".
class _InlineRetry extends StatelessWidget {
  const _InlineRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(message, style: TextStyle(color: scheme.error)),
        ),
        TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:itaaleem/core/widgets/app_shimmer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_models.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';
import 'package:itaaleem/features/center_admin/providers/center_admin_providers.dart';
import 'package:share_plus/share_plus.dart';

/// A code's state as the list shows it.
enum _CodeState { available, used, expired }

extension on _CodeState {
  String get label => switch (this) {
    _CodeState.available => 'متاح',
    _CodeState.used => 'مستخدم',
    _CodeState.expired => 'منتهي',
  };
}

/// `GET /center-admin/activation-codes` + "إنشاء أكواد تفعيل" (count +
/// subjects + duration → `POST activation-codes {count, subject_ids,
/// duration_months}`), each code copyable, filterable by state.
class CenterActivationCodesScreen extends ConsumerStatefulWidget {
  const CenterActivationCodesScreen({super.key});

  static String? codeOf(AdminRecord r) =>
      r.text(['code', 'activation_code', 'value']);

  @override
  ConsumerState<CenterActivationCodesScreen> createState() =>
      _CenterActivationCodesScreenState();
}

/// used: a student/used_at/is_used/status says so; expired: status or a
/// past `expires_at`; otherwise available.
_CodeState _stateOf(AdminRecord r) {
  final s = r.status ?? '';
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

String _subjectsOf(AdminRecord r) {
  final names = r.list('subjects').map((s) => s.title).toList();
  if (names.isEmpty) {
    final one = r.nestedName('subject');
    if (one != null) names.add(one);
  }
  return names.join('، ');
}

class _CenterActivationCodesScreenState
    extends ConsumerState<CenterActivationCodesScreen> {
  _CodeState? _filter;

  Future<void> _create() async {
    final created = await showModalBottomSheet<List<AdminRecord>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _CreateCodeSheet(),
    );
    if (created == null) return;
    await waitForRouteExit();
    if (!mounted) return;
    ref.invalidate(centerActivationCodesProvider);
    ref.invalidate(centerDashboardProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CreatedCodesSheet(
        codes: [
          for (final r in created)
            if (CenterActivationCodesScreen.codeOf(r) case final c?) c,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(centerActivationCodesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('أكواد التفعيل')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('إنشاء أكواد'),
      ),
      body: AppBackground(
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              child: Row(
                children: [
                  for (final f in <_CodeState?>[null, ..._CodeState.values])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: AppSpacing.sm,
                      ),
                      child: ChoiceChip(
                        label: Text(f?.label ?? 'الكل'),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(centerActivationCodesProvider.future),
                child: async.when(
                  loading: () => const ShimmerList(count: 5, thumbnailSize: 44),
                  error: (e, _) => _Message(
                    icon: Icons.cloud_off_rounded,
                    text: failureOf(e).message,
                  ),
                  data: (all) {
                    final codes = _filter == null
                        ? all
                        : all.where((r) => _stateOf(r) == _filter).toList();
                    if (codes.isEmpty) {
                      return _Message(
                        icon: Icons.vpn_key_outlined,
                        text: all.isEmpty
                            ? 'لا توجد أكواد بعد — أنشئ أول كود'
                            : 'لا توجد أكواد بهذه الحالة',
                      );
                    }
                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        96,
                      ),
                      itemCount: codes.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) {
                        final r = codes[i];
                        final code =
                            CenterActivationCodesScreen.codeOf(r) ?? '—';
                        final state = _stateOf(r);
                        final subjects = _subjectsOf(r);
                        final months = r.count(['duration_months']);
                        final usedBy =
                            r.nestedName('student') ??
                            r.nestedName('used_by') ??
                            r.text(['student_name', 'used_by_name']);
                        return AdminRecordCard(
                          title: code,
                          leading: AdminAvatar(
                            name: '',
                            icon: switch (state) {
                              _CodeState.available => Icons.vpn_key_rounded,
                              _CodeState.used => Icons.how_to_reg_rounded,
                              _CodeState.expired => Icons.timer_off_rounded,
                            },
                          ),
                          lines: [
                            if (subjects.isNotEmpty) subjects,
                            [
                              state.label,
                              if (usedBy != null) 'استخدمه: $usedBy',
                              if (months != null) '$months شهر',
                              adminDate(r.date(['created_at'])),
                            ].join(' • '),
                          ],
                          trailing: IconButton(
                            tooltip: 'نسخ',
                            icon: Icon(
                              Icons.copy_rounded,
                              color: scheme.primary,
                            ),
                            onPressed: () => _copy(context, code),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
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
  const _CreatedCodesSheet({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final all = codes.join('\n');
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
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
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
                    label: const Text('نسخ الكل'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(text: 'أكواد التفعيل:\n$all'),
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

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Scrollable so pull-to-refresh works on the empty / error state.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 56, color: scheme.onSurfaceVariant),
        const SizedBox(height: AppSpacing.md),
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

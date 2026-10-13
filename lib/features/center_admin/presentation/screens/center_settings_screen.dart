import 'package:itaaleem/core/widgets/app_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itaaleem/core/content/content_policy.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/theme/dynamic_theme.dart';
import 'package:itaaleem/core/widgets/app_error_state.dart';
import 'package:itaaleem/core/widgets/app_shimmer.dart';
import 'package:itaaleem/core/widgets/server_watermark.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_models.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_inbox_screen.dart'
    show inboxTypeInfo;
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';
import 'package:itaaleem/features/center_admin/providers/center_admin_providers.dart';

/// `GET` / `PUT /center-admin/settings` (partial PUT), in the web panel's
/// sections — each saved on its own:
/// * بيانات السنتر — name, phone, email (logo and colour shown).
/// * المحتوى والتحميل — `allow_pdf_download`, `allow_video_download`.
/// * العلامة المائية — `watermark {...}` with a live preview.
/// * الأجهزة والأمان — `device_policy`, `max_devices`.
/// * الإشعارات — `notification_preferences {push, types}`.
/// * إعدادات أخرى — any other on/off setting the API returns.
/// A section whose fields the API doesn't send is not shown.
class CenterSettingsScreen extends ConsumerWidget {
  const CenterSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(centerSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات السنتر')),
      body: AppBackground(
        child: async.when(
          loading: () => const ShimmerList(count: 4),
          error: (e, _) => AppErrorState(
            message: failureOf(e).message,
            onRetry: () => ref.invalidate(centerSettingsProvider),
          ),
          data: (raw) {
            // Some servers nest the values under `settings`.
            final json = <String, dynamic>{
              ...raw,
              if (raw['settings'] is Map)
                ...Map<String, dynamic>.from(raw['settings'] as Map),
            };
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _InfoSection(settings: AdminRecord(json)),
                if (json.containsKey('allow_pdf_download') ||
                    json.containsKey('allow_video_download'))
                  _DownloadsSection(json: json),
                if (json['watermark'] is Map)
                  _WatermarkSection(
                    initial: Map<String, dynamic>.from(
                      json['watermark'] as Map,
                    ),
                  ),
                if (json.containsKey('device_policy') ||
                    json.containsKey('max_devices'))
                  _DevicesSection(json: json),
                if (json['notification_preferences'] is Map)
                  _NotificationsSection(
                    initial: Map<String, dynamic>.from(
                      json['notification_preferences'] as Map,
                    ),
                  ),
                if (_otherFlags(json).isNotEmpty)
                  _OtherSection(flags: _otherFlags(json)),
              ],
            );
          },
        ),
      ),
    );
  }

  static const _known = {
    'id',
    'name',
    'phone',
    'email',
    'logo',
    'logo_url',
    'primary_color',
    'color',
    'brand_color',
    'allow_pdf_download',
    'allow_video_download',
    'watermark',
    'device_policy',
    'max_devices',
    'notification_preferences',
    'settings',
    'is_active',
    'created_at',
    'updated_at',
  };

  /// Every other boolean setting the API returns.
  static Map<String, bool> _otherFlags(Map<String, dynamic> json) => {
    for (final e in json.entries)
      if (!_known.contains(e.key) && e.value is bool) e.key: e.value as bool,
  };
}

/// Saves one section (`PUT settings` with just [patch]) with a SnackBar,
/// then reloads the settings (and the dashboard counters).
Future<bool> _saveSection(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> patch,
) async {
  // Survives the calling widget being rebuilt/disposed.
  final toastContext = Navigator.of(context, rootNavigator: true).context;
  try {
    final message = await ref
        .read(centerAdminRepositoryProvider)
        .updateSettings(patch);
    if (toastContext.mounted) {
      showAppSnack(toastContext, message ?? 'تم حفظ الإعدادات');
    }
    ref.invalidate(centerSettingsProvider);
    ref.invalidate(centerAdminRecordProvider);
    return true;
  } catch (e) {
    if (toastContext.mounted) {
      showAppSnack(
        toastContext,
        failureOf(e).message,
        type: AppSnackType.error,
      );
    }
    return false;
  }
}

/// A titled card with its own "حفظ" button.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    required this.saving,
    required this.onSave,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: GlassCard(
        radius: AppRadius.xl,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...children,
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: saving ? null : onSave,
              icon: saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A [State] whose section has a "saving" flag.
mixin _Saving<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool saving = false;

  Future<void> save(Map<String, dynamic> patch) async {
    setState(() => saving = true);
    await _saveSection(context, ref, patch);
    if (mounted) setState(() => saving = false);
  }
}

// --- بيانات السنتر -----------------------------------------------------------

class _InfoSection extends ConsumerStatefulWidget {
  const _InfoSection({required this.settings});

  final AdminRecord settings;

  @override
  ConsumerState<_InfoSection> createState() => _InfoSectionState();
}

class _InfoSectionState extends ConsumerState<_InfoSection>
    with _Saving<_InfoSection> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: _s.title == '—' ? '' : _s.title,
  );
  late final _phone = TextEditingController(text: _s.phone ?? '');
  late final _email = TextEditingController(text: _s.email ?? '');

  AdminRecord get _s => widget.settings;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    save({
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final color = tryParseHexColor(
      _s.text(['primary_color', 'color', 'brand_color']),
    );
    return Form(
      key: _formKey,
      child: _Section(
        title: 'بيانات السنتر',
        icon: Icons.apartment_rounded,
        saving: saving,
        onSave: _save,
        children: [
          Center(
            child: AdminAvatar(
              name: _s.title,
              imageUrl: _s.image,
              radius: 40,
              icon: _s.image == null ? Icons.apartment_rounded : null,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              'اللوجو يتغيّر من لوحة الويب',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'اسم السنتر',
              prefixIcon: Icon(Icons.apartment_rounded),
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'هذا الحقل مطلوب' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم التواصل',
              prefixIcon: Icon(Icons.phone_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'البريد الإلكتروني',
              prefixIcon: Icon(Icons.email_rounded),
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final s = v?.trim() ?? '';
              if (s.isEmpty) return null;
              return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)
                  ? null
                  : 'البريد الإلكتروني غير صحيح';
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color ?? scheme.primary,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: scheme.outlineVariant),
              ),
            ),
            title: const Text('لون السنتر'),
            subtitle: Text(
              _s.text(['primary_color', 'color', 'brand_color']) ??
                  'اللون الافتراضي',
            ),
          ),
        ],
      ),
    );
  }
}

// --- المحتوى والتحميل -------------------------------------------------------

class _DownloadsSection extends ConsumerStatefulWidget {
  const _DownloadsSection({required this.json});

  final Map<String, dynamic> json;

  @override
  ConsumerState<_DownloadsSection> createState() => _DownloadsSectionState();
}

class _DownloadsSectionState extends ConsumerState<_DownloadsSection>
    with _Saving<_DownloadsSection> {
  late bool? _pdf = readFlag(widget.json['allow_pdf_download']);
  late bool? _video = readFlag(widget.json['allow_video_download']);

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'المحتوى والتحميل',
      icon: Icons.download_rounded,
      saving: saving,
      onSave: () => save({
        if (widget.json.containsKey('allow_pdf_download'))
          'allow_pdf_download': _pdf ?? true,
        if (widget.json.containsKey('allow_video_download'))
          'allow_video_download': _video ?? true,
      }),
      children: [
        if (widget.json.containsKey('allow_pdf_download'))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.picture_as_pdf_rounded),
            title: const Text('السماح بتحميل ملفات PDF'),
            subtitle: const Text('القراءة داخل التطبيق متاحة دائماً'),
            value: _pdf ?? true,
            onChanged: (v) => setState(() => _pdf = v),
          ),
        if (widget.json.containsKey('allow_video_download'))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.ondemand_video_rounded),
            title: const Text('السماح بتحميل الفيديو للمشاهدة بدون إنترنت'),
            value: _video ?? true,
            onChanged: (v) => setState(() => _video = v),
          ),
      ],
    );
  }
}

// --- العلامة المائية ---------------------------------------------------------

class _WatermarkSection extends ConsumerStatefulWidget {
  const _WatermarkSection({required this.initial});

  final Map<String, dynamic> initial;

  @override
  ConsumerState<_WatermarkSection> createState() => _WatermarkSectionState();
}

class _WatermarkSectionState extends ConsumerState<_WatermarkSection>
    with _Saving<_WatermarkSection> {
  static const _contentOptions = <(String, String)>[
    ('name', 'اسم الطالب'),
    ('phone', 'رقم الطالب'),
    ('student_id', 'كود الطالب'),
    ('center_name', 'اسم السنتر'),
    ('custom', 'نص مخصص'),
  ];
  static const _colors = <(String, String)>[
    ('white', 'أبيض'),
    ('black', 'أسود'),
    ('gray', 'رمادي'),
    ('center', 'لون السنتر'),
  ];

  late final Map<String, dynamic> _w = widget.initial;
  late bool _enabled = readFlag(_w['enabled']) ?? true;
  late final Set<String> _content = {
    if (_w['content'] is List)
      for (final c in _w['content'] as List) '$c'
    else ...['name', 'phone'],
  };
  late final _custom = TextEditingController(
    text: '${_w['custom_text'] ?? ''}',
  );
  late double _opacity = (num.tryParse('${_w['opacity']}')?.toDouble() ?? 0.25)
      .clamp(0.05, 0.6);
  late String _fontSize = switch ('${_w['font_size']}') {
    'small' || 'large' => '${_w['font_size']}',
    _ => 'medium',
  };
  late String _color = _colors.any((c) => c.$1 == '${_w['color']}')
      ? '${_w['color']}'
      : 'white';
  late String _position = switch ('${_w['position']}') {
    'corner' || 'moving' => '${_w['position']}',
    _ => 'center',
  };
  late double _interval =
      (num.tryParse('${_w['move_interval']}')?.toDouble() ?? 8).clamp(3, 60);
  late bool _onPdf = readFlag(_w['on_pdf']) ?? true;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _save() {
    if (_content.contains('custom') && _custom.text.trim().isEmpty) {
      showAppSnack(
        context,
        'اكتب النص المخصص أو ألغِ اختياره',
        type: AppSnackType.error,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    save({
      'watermark': {
        'enabled': _enabled,
        'content': [
          for (final (key, _) in _contentOptions)
            if (_content.contains(key)) key,
        ],
        'custom_text': _custom.text.trim(),
        'opacity': double.parse(_opacity.toStringAsFixed(2)),
        'font_size': _fontSize,
        'color': _color,
        'position': _position,
        'move_interval': _interval.round(),
        'on_pdf': _onPdf,
      },
    });
  }

  /// What a student would see, with sample values.
  String get _previewText => [
    for (final (key, _) in _contentOptions)
      if (_content.contains(key))
        switch (key) {
          'name' => 'أحمد محمد',
          'phone' => '01012345678',
          'student_id' => '#1234',
          'center_name' => 'السنتر',
          _ => _custom.text.trim(),
        },
  ].where((s) => s.isNotEmpty).join(' • ');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final preview = WatermarkConfig(
      enabled: _enabled,
      text: _previewText,
      opacity: _opacity,
      fontSize: WatermarkConfig.fontSizeOf(_fontSize),
      color: parseWatermarkColor(_color),
      centerColor: _color == 'center',
      position: switch (_position) {
        'corner' => WatermarkPosition.corner,
        'moving' => WatermarkPosition.moving,
        _ => WatermarkPosition.center,
      },
      moveInterval: Duration(seconds: _interval.round()),
      onPdf: _onPdf,
    );
    return _Section(
      title: 'العلامة المائية',
      icon: Icons.branding_watermark_rounded,
      saving: saving,
      onSave: _save,
      children: [
        // Preview: a black "video" with the watermark on it.
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Icon(
                      Icons.play_circle_outline_rounded,
                      size: 48,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  if (_enabled && _previewText.isNotEmpty)
                    ServerWatermark(
                      key: ValueKey('$_position${_interval.round()}'),
                      config: preview,
                      text: _previewText,
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('تفعيل العلامة المائية'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        Text('المحتوى', style: text.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (key, label) in _contentOptions)
              FilterChip(
                label: Text(label),
                selected: _content.contains(key),
                onSelected: (on) => setState(
                  () => on ? _content.add(key) : _content.remove(key),
                ),
              ),
          ],
        ),
        if (_content.contains('custom')) ...[
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _custom,
            maxLength: 40,
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'النص المخصص',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text('الشفافية: ${(_opacity * 100).round()}%', style: text.labelLarge),
        Slider(
          value: _opacity,
          min: 0.05,
          max: 0.6,
          divisions: 11,
          onChanged: (v) => setState(() => _opacity = v),
        ),
        Text('حجم الخط', style: text.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'small', label: Text('صغير')),
            ButtonSegment(value: 'medium', label: Text('متوسط')),
            ButtonSegment(value: 'large', label: Text('كبير')),
          ],
          selected: {_fontSize},
          onSelectionChanged: (s) => setState(() => _fontSize = s.first),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('اللون', style: text.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final (key, label) in _colors)
              ChoiceChip(
                avatar: CircleAvatar(
                  radius: 8,
                  backgroundColor: key == 'center'
                      ? scheme.primary
                      : parseWatermarkColor(key),
                ),
                label: Text(label),
                selected: _color == key,
                onSelected: (_) => setState(() => _color = key),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text('المكان', style: text.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'center', label: Text('ثابتة بالنص')),
            ButtonSegment(value: 'corner', label: Text('الأركان')),
            ButtonSegment(value: 'moving', label: Text('متحركة')),
          ],
          selected: {_position},
          onSelectionChanged: (s) => setState(() => _position = s.first),
        ),
        if (_position != 'center') ...[
          const SizedBox(height: AppSpacing.sm),
          Text('تتحرك كل ${_interval.round()} ثانية', style: text.labelLarge),
          Slider(
            value: _interval,
            min: 3,
            max: 60,
            divisions: 57,
            onChanged: (v) => setState(() => _interval = v),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('إظهارها على ملفات PDF'),
          value: _onPdf,
          onChanged: (v) => setState(() => _onPdf = v),
        ),
      ],
    );
  }
}

// --- الأجهزة والأمان ---------------------------------------------------------

class _DevicesSection extends ConsumerStatefulWidget {
  const _DevicesSection({required this.json});

  final Map<String, dynamic> json;

  @override
  ConsumerState<_DevicesSection> createState() => _DevicesSectionState();
}

class _DevicesSectionState extends ConsumerState<_DevicesSection>
    with _Saving<_DevicesSection> {
  /// The known `device_policy` values and what they mean.
  static const _policies = <String, (String, String)>{
    'block_new': (
      'منع الجهاز الجديد',
      'الطالب ما يقدرش يدخل من جهاز جديد لما يوصل للحد',
    ),
    'replace_oldest': (
      'استبدال أقدم جهاز',
      'الجهاز الجديد يدخل، وأقدم جهاز يخرج',
    ),
  };

  /// May be a value outside [_policies] — shown as-is, saved back unchanged.
  late String? _policy = switch (widget.json['device_policy']) {
    null => null,
    final v => '$v'.trim().isEmpty ? null : '$v'.trim(),
  };
  late int _max =
      num.tryParse('${widget.json['max_devices'] ?? ''}')?.toInt() ?? 1;

  bool get _hasPolicy => widget.json.containsKey('device_policy');
  bool get _hasMax => widget.json.containsKey('max_devices');

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final current = _policy;
    return _Section(
      title: 'الأجهزة والأمان',
      icon: Icons.devices_rounded,
      saving: saving,
      onSave: () => save({
        if (_hasPolicy && current != null) 'device_policy': current,
        if (_hasMax) 'max_devices': _max,
      }),
      children: [
        if (_hasPolicy) ...[
          DropdownButtonFormField<String>(
            initialValue: current,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'لما الطالب يوصل للحد الأقصى',
              prefixIcon: Icon(Icons.policy_rounded),
              border: OutlineInputBorder(),
            ),
            items: [
              for (final MapEntry(key: value, value: (label, _))
                  in _policies.entries)
                DropdownMenuItem(value: value, child: Text(label)),
              // An unknown server value: listed so the dropdown doesn't
              // crash, and kept unless the admin picks another one.
              if (current != null && !_policies.containsKey(current))
                DropdownMenuItem(value: current, child: Text(current)),
            ],
            onChanged: (v) => setState(() => _policy = v),
          ),
          if (_policies[current] case (_, final hint)) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              hint,
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
        if (_hasMax)
          Row(
            children: [
              Expanded(
                child: Text('أقصى عدد أجهزة للطالب', style: text.bodyLarge),
              ),
              IconButton.outlined(
                onPressed: _max > 1 ? () => setState(() => _max--) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  '$_max',
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.outlined(
                onPressed: _max < 20 ? () => setState(() => _max++) : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
      ],
    );
  }
}

// --- الإشعارات ---------------------------------------------------------------

class _NotificationsSection extends ConsumerStatefulWidget {
  const _NotificationsSection({required this.initial});

  final Map<String, dynamic> initial;

  @override
  ConsumerState<_NotificationsSection> createState() =>
      _NotificationsSectionState();
}

class _NotificationsSectionState extends ConsumerState<_NotificationsSection>
    with _Saving<_NotificationsSection> {
  static const _types = [
    'new_student',
    'code_redeemed',
    'subscription',
    'subscriptions_expiring',
    'review_pending',
    'new_message',
    'device_limit',
    'submission',
    'codes_low',
    'platform_announcement',
  ];

  late bool _push = readFlag(widget.initial['push']) ?? true;
  late final Map<String, bool> _enabled = {
    for (final t in _types) t: true,
    if (widget.initial['types'] is Map)
      for (final e in (widget.initial['types'] as Map).entries)
        '${e.key}': readFlag(e.value) ?? true,
  };

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'الإشعارات',
      icon: Icons.notifications_active_rounded,
      saving: saving,
      onSave: () => save({
        'notification_preferences': {'push': _push, 'types': _enabled},
      }),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('إشعارات على الموبايل (Push)'),
          value: _push,
          onChanged: (v) => setState(() => _push = v),
        ),
        const Divider(),
        for (final type in _enabled.keys)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(inboxTypeInfo(type).icon),
            title: Text(inboxTypeInfo(type).label),
            value: _enabled[type]!,
            onChanged: (v) => setState(() => _enabled[type] = v),
          ),
      ],
    );
  }
}

// --- إعدادات أخرى ------------------------------------------------------------

class _OtherSection extends ConsumerStatefulWidget {
  const _OtherSection({required this.flags});

  final Map<String, bool> flags;

  @override
  ConsumerState<_OtherSection> createState() => _OtherSectionState();
}

class _OtherSectionState extends ConsumerState<_OtherSection>
    with _Saving<_OtherSection> {
  late final Map<String, bool> _values = {...widget.flags};

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'إعدادات أخرى',
      icon: Icons.tune_rounded,
      saving: saving,
      onSave: () => save({..._values}),
      children: [
        for (final key in _values.keys)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(key.replaceAll('_', ' ')),
            value: _values[key]!,
            onChanged: (v) => setState(() => _values[key] = v),
          ),
      ],
    );
  }
}

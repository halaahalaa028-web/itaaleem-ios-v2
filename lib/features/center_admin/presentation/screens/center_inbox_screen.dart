import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_empty_state.dart';
import 'package:itaaleem/core/widgets/app_error_state.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_api.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_models.dart';
import 'package:itaaleem/features/center_admin/presentation/center_admin_routes.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';
import 'package:itaaleem/features/center_admin/providers/center_admin_providers.dart';

/// One item of `GET /center-admin/inbox`:
/// `{id (uuid), type, title, body, data:{...}, read_at, created_at}`.
class CenterInboxItem {
  CenterInboxItem(this.json);

  final Map<String, dynamic> json;

  String get id => '${json['id'] ?? ''}';
  String get type => '${json['type'] ?? ''}';
  String get title => '${json['title'] ?? ''}'.trim();
  String get body => '${json['body'] ?? ''}'.trim();
  Map<String, dynamic> get data => json['data'] is Map
      ? Map<String, dynamic>.from(json['data'] as Map)
      : const {};
  bool read = false;
  DateTime? get createdAt =>
      DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal();

  int? dataId(List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
      if (n != null) return n;
    }
    return null;
  }

  static CenterInboxItem fromJson(Map<String, dynamic> json) =>
      CenterInboxItem(json)..read = json['read_at'] != null;
}

/// Icon + label for each inbox `type`; the color comes from the theme.
({IconData icon, String label}) inboxTypeInfo(String type) => switch (type) {
  'new_student' => (icon: Icons.person_add_alt_1_rounded, label: 'طالب جديد'),
  'code_redeemed' || 'activation_code_redeemed' => (
    icon: Icons.vpn_key_rounded,
    label: 'تفعيل كود',
  ),
  'subscription' => (icon: Icons.card_membership_rounded, label: 'اشتراك'),
  'subscriptions_expiring' => (
    icon: Icons.timer_rounded,
    label: 'اشتراكات تنتهي قريباً',
  ),
  'review_pending' => (icon: Icons.rate_review_rounded, label: 'مراجعة'),
  'new_message' => (icon: Icons.chat_rounded, label: 'رسالة جديدة'),
  'device_limit' => (icon: Icons.phonelink_lock_rounded, label: 'حد الأجهزة'),
  'submission' => (icon: Icons.assignment_turned_in_rounded, label: 'تسليم'),
  'codes_low' => (
    icon: Icons.warning_amber_rounded,
    label: 'الأكواد قاربت تخلص',
  ),
  'platform_announcement' => (icon: Icons.campaign_rounded, label: 'إعلان'),
  _ => (icon: Icons.notifications_rounded, label: 'إشعار'),
};

Color _toneOf(ColorScheme s, String type) => switch (type) {
  'new_student' || 'subscription' => s.primary,
  'code_redeemed' || 'activation_code_redeemed' || 'submission' => s.tertiary,
  'subscriptions_expiring' || 'codes_low' || 'device_limit' => s.error,
  _ => s.secondary,
};

/// "الإشعارات" of the admin: newest first, unread highlighted, pull to
/// refresh, infinite scroll, "تعليم الكل كمقروء", unread-only filter. A tap
/// marks it read and opens the related screen when there is one.
class CenterInboxScreen extends ConsumerStatefulWidget {
  const CenterInboxScreen({super.key});

  @override
  ConsumerState<CenterInboxScreen> createState() => _CenterInboxScreenState();
}

class _CenterInboxScreenState extends ConsumerState<CenterInboxScreen> {
  static const _perPage = 20;

  final _items = <CenterInboxItem>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _unreadOnly = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = _page + 1;
      final body = await ref
          .read(centerAdminApiProvider)
          .get(
            'inbox',
            query: {
              'page': page,
              'per_page': _perPage,
              if (_unreadOnly) 'unread': 1,
            },
          );
      final list = extractAdminList(body);
      final paging = extractAdminPaging(body, page, list.length, _perPage);
      if (!mounted) return;
      final seen = {for (final i in _items) i.id};
      setState(() {
        _items.addAll(
          [
            for (final e in list)
              if (e is Map)
                CenterInboxItem.fromJson(Map<String, dynamic>.from(e)),
          ].where((i) => !seen.contains(i.id)),
        );
        _page = paging.page;
        _hasMore = paging.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_items.isEmpty) {
          _error = e;
        } else {
          AppToast.showError(context, failureOf(e).message);
        }
      });
    }
  }

  Future<void> _markAll() async {
    try {
      await ref.read(centerAdminRepositoryProvider).markAllInboxRead();
      if (!mounted) return;
      setState(() {
        for (final i in _items) {
          i.read = true;
        }
      });
      ref.invalidate(centerInboxUnreadProvider);
      AppToast.showSuccess(context, 'تم تعليم الكل كمقروء');
    } catch (e) {
      if (mounted) AppToast.showError(context, failureOf(e).message);
    }
  }

  Future<void> _open(CenterInboxItem item) async {
    if (!item.read) {
      setState(() => item.read = true);
      // Best effort — a failed mark doesn't block opening it.
      ref
          .read(centerAdminRepositoryProvider)
          .markInboxRead(item.id)
          .then((_) => ref.invalidate(centerInboxUnreadProvider))
          .catchError((Object _) {});
    }
    final target = _targetOf(item);
    if (target != null && mounted) await context.push(target);
  }

  /// The screen this notification is about, or `null` to stay here.
  String? _targetOf(CenterInboxItem item) {
    final studentId = item.dataId(['student_id', 'user_id']);
    return switch (item.type) {
      'new_student' || 'device_limit' =>
        studentId != null
            ? centerAdminStudentPath(studentId)
            : centerAdminStudentsPath,
      'code_redeemed' ||
      'activation_code_redeemed' ||
      'codes_low' => centerAdminActivationCodesPath,
      'subscription' ||
      'subscriptions_expiring' => centerAdminSubscriptionsPath,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasUnread = _items.any((i) => !i.read);

    Widget body;
    if (_error != null) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          AppErrorState(message: failureOf(_error!).message, onRetry: _reload),
        ],
      );
    } else if (_items.isEmpty && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_items.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          AppEmptyState(
            icon: Icons.notifications_none_rounded,
            title: _unreadOnly
                ? 'لا توجد إشعارات غير مقروءة'
                : 'لا توجد إشعارات',
          ),
        ],
      );
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
            _loadMore();
          }
          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: _items.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) {
            if (i >= _items.length) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _InboxTile(item: _items[i], onTap: () => _open(_items[i]));
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          IconButton(
            tooltip: 'تعليم الكل كمقروء',
            onPressed: hasUnread ? _markAll : null,
            icon: const Icon(Icons.done_all_rounded),
          ),
        ],
      ),
      body: AppBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('الكل'),
                    selected: !_unreadOnly,
                    onSelected: (_) {
                      if (!_unreadOnly) return;
                      _unreadOnly = false;
                      _reload();
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ChoiceChip(
                    label: const Text('غير المقروء'),
                    selected: _unreadOnly,
                    onSelected: (_) {
                      if (_unreadOnly) return;
                      _unreadOnly = true;
                      _reload();
                    },
                  ),
                  const Spacer(),
                  if (hasUnread)
                    TextButton(
                      onPressed: _markAll,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.primary,
                      ),
                      child: const Text('تعليم الكل كمقروء'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(centerInboxUnreadProvider);
                  await _reload();
                },
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.item, required this.onTap});

  final CenterInboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final info = inboxTypeInfo(item.type);
    final tone = _toneOf(scheme, item.type);
    final unread = !item.read;
    return Material(
      color: unread
          ? Color.alphaBlend(
              scheme.primaryContainer.withValues(alpha: 0.45),
              scheme.surface,
            )
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: tone.withValues(alpha: 0.14),
                child: Icon(info.icon, color: tone),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title.isEmpty ? info.label : item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall?.copyWith(
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (item.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${info.label} • ${adminAgo(item.createdAt)}',
                      style: text.labelSmall?.copyWith(color: tone),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

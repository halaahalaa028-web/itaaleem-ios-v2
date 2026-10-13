import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/providers/cache_for.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_models.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_repository.dart';

export 'package:itaaleem/features/center_admin/data/center_admin_repository.dart'
    show centerAdminRepositoryProvider;

/// `GET /center-admin/dashboard` — cached 2 minutes.
final centerDashboardProvider = FutureProvider.autoDispose<CenterDashboardData>(
  (ref) {
    return ref.cached(
      () => ref.read(centerAdminRepositoryProvider).getDashboard(),
      duration: const Duration(minutes: 2),
    );
  },
);

/// One object (`students/5`, `stats`, `settings`, `exams/3/results`…) —
/// cached 1 minute.
final centerAdminRecordProvider = FutureProvider.autoDispose
    .family<AdminRecord, String>((ref, path) {
      return ref.cached(
        () => ref.read(centerAdminRepositoryProvider).getOne(path),
        duration: const Duration(minutes: 1),
      );
    });

/// Pending subscription requests (newest first) and their total — the
/// dashboard badge / "طلبات جديدة". Cached 1 minute.
final centerPendingRequestsProvider =
    FutureProvider.autoDispose<({List<AdminRecord> items, int total})>((ref) {
      return ref.cached(
        () => ref.read(centerAdminRepositoryProvider).pendingRequests(),
        duration: const Duration(minutes: 1),
      );
    });

/// Every lecture of the center grouped by subject.
final centerLecturesBySubjectProvider =
    FutureProvider.autoDispose<
      List<({AdminRecord subject, List<AdminRecord> lectures})>
    >((ref) => ref.read(centerAdminRepositoryProvider).lecturesBySubject());

/// `GET activation-codes`.
final centerActivationCodesProvider =
    FutureProvider.autoDispose<List<AdminRecord>>(
      (ref) => ref.read(centerAdminRepositoryProvider).activationCodes(),
    );

/// All the center's subjects (for pickers) — cached 2 minutes.
final centerSubjectsListProvider =
    FutureProvider.autoDispose<List<AdminRecord>>(
      (ref) => ref.cached(
        () async =>
            (await ref
                    .read(centerAdminRepositoryProvider)
                    .getPage('subjects', filters: {'per_page': 100}))
                .items,
        duration: const Duration(minutes: 2),
      ),
    );

/// `GET courses` — cached 2 minutes. Empty when the server has none (or
/// lacks the route), so pickers simply hide.
final centerCoursesProvider = FutureProvider.autoDispose<List<AdminRecord>>(
  (ref) => ref.cached(() async {
    try {
      return await ref.read(centerAdminRepositoryProvider).courses();
    } catch (_) {
      return const <AdminRecord>[];
    }
  }, duration: const Duration(minutes: 2)),
);

/// `GET courses/{id}/subjects`.
final centerCourseSubjectsProvider = FutureProvider.autoDispose
    .family<List<AdminRecord>, int>(
      (ref, id) => ref.cached(
        () => ref.read(centerAdminRepositoryProvider).courseSubjects(id),
        duration: const Duration(minutes: 2),
      ),
    );

/// `GET inbox/unread-count` — the bell badge. 0 on failure.
final centerInboxUnreadProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    return await ref.read(centerAdminRepositoryProvider).inboxUnreadCount();
  } catch (_) {
    return 0;
  }
});

/// `GET settings` as raw JSON.
final centerSettingsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.read(centerAdminRepositoryProvider).settings(),
);

/// What an admin list shows: a section [path] plus its filters. A record,
/// so equal queries share one provider instance.
typedef AdminListQuery = ({String path, String search, String filters});

AdminListQuery adminQuery(
  String path, {
  String search = '',
  Map<String, Object?> filters = const {},
}) {
  final entries =
      filters.entries
          .where((e) => e.value != null && '${e.value}' != '')
          .map((e) => '${e.key}=${e.value}')
          .toList()
        ..sort();
  return (path: path, search: search, filters: entries.join('&'));
}

class AdminListState {
  const AdminListState({
    required this.items,
    required this.page,
    required this.hasMore,
    this.loadingMore = false,
  });

  final List<AdminRecord> items;
  final int page;
  final bool hasMore;
  final bool loadingMore;

  AdminListState copyWith({
    List<AdminRecord>? items,
    int? page,
    bool? hasMore,
    bool? loadingMore,
  }) => AdminListState(
    items: items ?? this.items,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// A paginated, searchable list for any section — cached 1 minute.
class AdminListController
    extends AutoDisposeFamilyAsyncNotifier<AdminListState, AdminListQuery> {
  Map<String, dynamic> get _filters => {
    for (final pair in arg.filters.split('&'))
      if (pair.contains('=')) pair.split('=').first: pair.split('=').last,
  };

  @override
  Future<AdminListState> build(AdminListQuery arg) {
    return ref.cached(() async {
      final page = await ref
          .read(centerAdminRepositoryProvider)
          .getPage(arg.path, search: arg.search, filters: _filters);
      return AdminListState(
        items: page.items,
        page: page.page,
        hasMore: page.hasMore,
      );
    }, duration: const Duration(minutes: 1));
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await ref
          .read(centerAdminRepositoryProvider)
          .getPage(
            arg.path,
            page: current.page + 1,
            search: arg.search,
            filters: _filters,
          );
      final seen = {for (final r in current.items) r.id};
      state = AsyncData(
        current.copyWith(
          items: [
            ...current.items,
            ...next.items.where((r) => !seen.contains(r.id)),
          ],
          page: next.page,
          hasMore: next.hasMore,
          loadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }
}

final adminListProvider = AsyncNotifierProvider.autoDispose
    .family<AdminListController, AdminListState, AdminListQuery>(
      AdminListController.new,
    );

/// `GET students/{id}/subscriptions` — all of a student's subscriptions.
final centerStudentSubscriptionsProvider = FutureProvider.autoDispose
    .family<List<AdminRecord>, int>(
      (ref, id) =>
          ref.watch(centerAdminRepositoryProvider).studentSubscriptions(id),
    );

/// After a create / update / delete: reloads every open list of [path]
/// (any search / filter) plus the dashboard counters.
void invalidateAdminSection(WidgetRef ref, String path) {
  ref.invalidate(adminListProvider);
  ref.invalidate(centerDashboardProvider);
  ref.invalidate(centerAdminRecordProvider);
  ref.invalidate(centerPendingRequestsProvider);
  ref.invalidate(centerLecturesBySubjectProvider);
  ref.invalidate(centerActivationCodesProvider);
  ref.invalidate(centerStudentSubscriptionsProvider);
  ref.invalidate(centerInboxUnreadProvider);
}

/// [invalidateAdminSection] from a captured container — safe after the
/// triggering widget is gone.
void invalidateAdminContainer(ProviderContainer c) {
  c.invalidate(adminListProvider);
  c.invalidate(centerDashboardProvider);
  c.invalidate(centerAdminRecordProvider);
  c.invalidate(centerPendingRequestsProvider);
  c.invalidate(centerLecturesBySubjectProvider);
  c.invalidate(centerActivationCodesProvider);
  c.invalidate(centerStudentSubscriptionsProvider);
  c.invalidate(centerInboxUnreadProvider);
}

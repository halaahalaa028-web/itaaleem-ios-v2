import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:itaaleem/core/widgets/app_empty_state.dart';
import 'package:itaaleem/core/widgets/app_shimmer.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// One item of `GET /certificates`. Fields are read defensively; the link
/// is signed and valid ~30 minutes, so the list is re-fetched before use.
class Certificate {
  const Certificate({required this.title, this.url, this.issuedAt});

  final String title;
  final String? url;
  final DateTime? issuedAt;

  static Certificate fromJson(Map<String, dynamic> j) {
    String? str(List<String> keys) {
      for (final k in keys) {
        final v = j[k];
        if (v is Map) {
          final n = v['name'] ?? v['title'];
          if (n != null && '$n'.trim().isNotEmpty) return '$n'.trim();
        } else if (v != null && '$v'.trim().isNotEmpty) {
          return '$v'.trim();
        }
      }
      return null;
    }

    return Certificate(
      title: str(['title', 'course_name', 'course', 'name']) ?? 'شهادة',
      url: str(['url', 'download_url', 'link', 'file_url', 'certificate_url']),
      issuedAt: DateTime.tryParse(
        str(['issued_at', 'created_at', 'date']) ?? '',
      )?.toLocal(),
    );
  }
}

/// `GET /certificates`. An empty list on any failure — the "شهاداتي" entry
/// simply stays hidden.
final certificatesProvider = FutureProvider.autoDispose<List<Certificate>>((
  ref,
) async {
  try {
    final res = await ref.read(dioClientProvider).get<dynamic>('/certificates');
    final body = res.data;
    final raw = body is List
        ? body
        : (body is Map
              ? (body['data'] is List
                    ? body['data']
                    : (body['data'] is Map ? body['data']['items'] : null) ??
                          body['certificates'])
              : null);
    return [
      if (raw is List)
        for (final e in raw)
          if (e is Map) Certificate.fromJson(Map<String, dynamic>.from(e)),
    ];
  } catch (_) {
    return const [];
  }
});

/// "شهاداتي": the list; a tap opens the certificate in the external
/// browser (to print or save as PDF).
Future<void> showCertificatesSheet(BuildContext context, WidgetRef ref) async {
  // Fresh links (they expire after ~30 minutes).
  ref.invalidate(certificatesProvider);
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _CertificatesSheet(),
  );
}

class _CertificatesSheet extends ConsumerWidget {
  const _CertificatesSheet();

  Future<void> _open(BuildContext context, Certificate c) async {
    final uri = Uri.tryParse(c.url ?? '');
    final ok =
        uri != null &&
        await launchUrlSafely(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      AppToast.showError(context, 'تعذر فتح الشهادة، حاول مرة أخرى');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final async = ref.watch(certificatesProvider);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              'شهاداتي',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Flexible(
            child: async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.base),
                child: AppShimmer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShimmerCard(),
                      SizedBox(height: AppSpacing.md),
                      ShimmerCard(),
                    ],
                  ),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(failureOf(e).message, textAlign: TextAlign.center),
              ),
              data: (items) => items.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.workspace_premium_outlined,
                      title: 'لا توجد شهادات بعد',
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final c = items[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            child: Icon(
                              Icons.workspace_premium_rounded,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(c.title),
                          subtitle: c.issuedAt == null
                              ? null
                              : Text(
                                  DateFormat(
                                    'd MMMM yyyy',
                                    'ar',
                                  ).format(c.issuedAt!),
                                ),
                          trailing: const Icon(Icons.open_in_new_rounded),
                          enabled: c.url != null,
                          onTap: () => _open(context, c),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

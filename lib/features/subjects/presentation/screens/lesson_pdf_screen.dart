import 'package:itaaleem/core/content/content_policy.dart';
import 'package:itaaleem/features/subjects/data/content_file_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/widgets/secure_screen.dart';
import 'package:itaaleem/features/subjects/presentation/utils/pdf_download.dart';
import 'package:itaaleem/features/subjects/presentation/widgets/lesson_pdf_view.dart';

/// Views a subject lesson's own PDF from `SubjectLesson.pdfUrl` — the
/// download/cache/viewer logic lives in [LessonPdfView], shared with the
/// split view in `LessonVideoScreen`.
///
/// Theme-colored top bar (back, title, "٣ / ٢٠", download). Tapping the
/// page toggles full-screen: the bar slides away and back. Back swipe (iOS)
/// and the system back button (Android) are left untouched.
class LessonPdfScreen extends ConsumerStatefulWidget {
  const LessonPdfScreen({
    super.key,
    required this.title,
    required this.pdfUrl,
    this.downloadable = false,
    this.fileRef,
  });

  final ContentFileRef? fileRef;

  final String title;
  final String? pdfUrl;

  /// The API's `is_downloadable`: the download button only shows when true.
  final bool downloadable;

  @override
  ConsumerState<LessonPdfScreen> createState() => _LessonPdfScreenState();
}

class _LessonPdfScreenState extends ConsumerState<LessonPdfScreen> {
  bool _fullScreen = false;
  final _page = ValueNotifier<(int, int)?>(null);

  @override
  void dispose() {
    _page.dispose();
    if (_fullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _toggleFullScreen() {
    setState(() => _fullScreen = !_fullScreen);
    SystemChrome.setEnabledSystemUIMode(
      _fullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.pdfUrl;
    final scheme = Theme.of(context).colorScheme;
    final canDownload =
        widget.downloadable &&
        ref.watch(contentPolicyProvider.select((p) => p.canDownloadPdf)) &&
        ((url != null && url.isNotEmpty) || widget.fileRef != null);

    return SecureScreen(
      child: Scaffold(
        backgroundColor: scheme.surfaceContainer,
        body: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _fullScreen ? 0 : 1,
                child: _fullScreen
                    ? const SizedBox(width: double.infinity)
                    : _PdfTopBar(
                        title: widget.title,
                        page: _page,
                        onDownload: canDownload
                            ? () => downloadPdf(
                                context,
                                ref,
                                url: url ?? '',
                                title: widget.title,
                                fileRef: widget.fileRef,
                              )
                            : null,
                      ),
              ),
            ),
            Expanded(
              child: LessonPdfView(
                pdfUrl: url,
                fileRef: widget.fileRef,
                onTap: _toggleFullScreen,
                onPageChanged: (page, count) => _page.value = (page, count),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfTopBar extends StatelessWidget {
  const _PdfTopBar({required this.title, required this.page, this.onDownload});

  final String title;
  final ValueNotifier<(int, int)?> page;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      elevation: 0,
      shadowColor: scheme.shadow,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: kToolbarHeight,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: scheme.outlineVariant, width: 0.5),
            ),
          ),
          padding: const EdgeInsetsDirectional.only(start: 4, end: 8),
          child: Row(
            children: [
              // RTL: the leading (right) edge — where back belongs.
              BackButton(color: scheme.onSurface),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ValueListenableBuilder<(int, int)?>(
                valueListenable: page,
                builder: (context, value, _) {
                  if (value == null) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsetsDirectional.only(start: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_arabicDigits(value.$1)} / ${_arabicDigits(value.$2)}',
                      textDirection: TextDirection.rtl,
                      style: text.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
              if (onDownload != null)
                IconButton(
                  tooltip: 'تحميل',
                  color: scheme.onSurface,
                  icon: const Icon(Icons.download_rounded),
                  onPressed: onDownload,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _arabicDigits(int n) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  return n.toString().split('').map((c) => digits[int.parse(c)]).join();
}

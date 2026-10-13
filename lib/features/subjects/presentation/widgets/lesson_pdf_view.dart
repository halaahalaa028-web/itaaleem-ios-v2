import 'package:itaaleem/features/subjects/data/content_file_access.dart';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:itaaleem/core/widgets/content_watermark.dart';
import 'package:itaaleem/core/widgets/server_watermark.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

/// Embeddable PDF body for a subject lesson's `pdfUrl` — no Scaffold, so it
/// works both as the body of [LessonPdfScreen] and next to the video player.
///
/// The file goes through the authenticated Dio client (the API needs the
/// bearer token), so it's fetched here with a visible percentage, cached on
/// disk (re-opening a large file is then instant), and shown from that file
/// with pdfrx. A failure shows a clear message with a retry.
class LessonPdfView extends ConsumerStatefulWidget {
  const LessonPdfView({
    super.key,
    required this.pdfUrl,
    this.fileRef,
    this.onPageChanged,
    this.onTap,
  });

  final String? pdfUrl;

  /// `(page, pageCount)`, 1-based — on load and on every page change.
  final void Function(int page, int pageCount)? onPageChanged;

  /// A single tap on the page (not a double-tap zoom) — the full-screen
  /// toggle in [LessonPdfScreen].
  final VoidCallback? onTap;

  /// For signed (expiring) URLs: the cache key and link refresh source.
  final ContentFileRef? fileRef;

  /// Drops [ref]'s cached copy — used when the API reports it locked.
  static Future<void> evictCache(ContentFileRef ref) async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/pdf_cache/${ref.cacheKey}.pdf');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  ConsumerState<LessonPdfView> createState() => _LessonPdfViewState();
}

class _LessonPdfViewState extends ConsumerState<LessonPdfView> {
  File? _file;
  double? _progress;
  bool _failed = false;
  String? _lockedMessage;
  CancelToken? _cancelToken;
  final _pdfController = PdfViewerController();
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  /// Keyed by the file's identity, not its URL: signed URLs change on every
  /// response, which would re-download (and duplicate) the same file.
  Future<File> _cacheFileFor(String url) async {
    final dir = await getTemporaryDirectory();
    final key = widget.fileRef?.cacheKey ?? '${url.hashCode.toUnsigned(32)}';
    return File('${dir.path}/pdf_cache/$key.pdf');
  }

  static bool _pruned = false;
  static const _maxAge = Duration(days: 7);
  static const _maxCacheBytes = 200 * 1024 * 1024;

  /// Keeps `pdf_cache` (shared with the courses PDF screens) from filling the
  /// device: drops files unused for a week, then the oldest ones until the
  /// folder is under [_maxCacheBytes]. Runs once per app session.
  static Future<void> _pruneCache() async {
    if (_pruned) return;
    _pruned = true;
    try {
      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/pdf_cache',
      );
      if (!await dir.exists()) return;
      final now = DateTime.now();
      final files = <(File, DateTime, int)>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (now.difference(stat.modified) > _maxAge) {
          await entity.delete();
        } else {
          files.add((entity, stat.modified, stat.size));
        }
      }
      var total = files.fold<int>(0, (sum, f) => sum + f.$3);
      files.sort((a, b) => a.$2.compareTo(b.$2));
      for (final f in files) {
        if (total <= _maxCacheBytes) break;
        await f.$1.delete();
        total -= f.$3;
      }
    } catch (_) {
      // Best-effort housekeeping.
    }
  }

  Future<void> _load() async {
    final url = widget.pdfUrl ?? '';
    final fileRef = widget.fileRef;
    if (url.isEmpty && fileRef == null) return;
    await _pruneCache();
    if (!mounted) return;
    setState(() {
      _failed = false;
      _lockedMessage = null;
      _progress = null;
    });
    try {
      final target = await _cacheFileFor(url);
      if (await target.exists()) {
        if (await _isValidPdf(target)) {
          // Refresh the timestamp so recently-read files outlive old ones.
          await target.setLastModified(DateTime.now());
          if (mounted) setState(() => _file = target);
          return;
        }
        await target.delete();
      }
      await target.parent.create(recursive: true);
      final partial = File('${target.path}.part');
      _cancelToken = CancelToken();
      void onProgress(int received, int total) {
        if (total <= 0 || !mounted) return;
        final next = received / total;
        // Repaint at ~1% steps instead of on every network chunk.
        if (_progress == null || next - _progress! >= 0.01) {
          setState(() => _progress = next);
        }
      }

      final dio = ref.read(dioClientProvider);
      if (fileRef != null) {
        // Refreshes an expired signed link (and retries once on a 403).
        await downloadContentFile(
          dio,
          fileRef,
          partial.path,
          cancelToken: _cancelToken,
          onReceiveProgress: onProgress,
        );
      } else {
        await dio.download(
          url,
          partial.path,
          cancelToken: _cancelToken,
          onReceiveProgress: onProgress,
        );
      }
      if (!await _isValidPdf(partial)) {
        await partial.delete();
        throw const FormatException('downloaded file is not a valid PDF');
      }
      await partial.rename(target.path);
      if (mounted) setState(() => _file = target);
    } on ContentLockedException catch (e) {
      // No access (anymore): never show a stale cached copy.
      if (fileRef != null) await LessonPdfView.evictCache(fileRef);
      if (mounted) setState(() => _lockedMessage = e.displayMessage);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// A real PDF starts with the `%PDF` magic bytes — only those are read.
  Future<bool> _isValidPdf(File file) async {
    try {
      if (await file.length() < 8) return false;
      final raf = await file.open();
      try {
        final head = await raf.read(4);
        return head.length == 4 &&
            head[0] == 0x25 &&
            head[1] == 0x50 &&
            head[2] == 0x44 &&
            head[3] == 0x46;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _onViewerFailed() async {
    // A corrupt/partial cached file — drop it so a retry re-downloads.
    final file = _file;
    if (file != null && await file.exists()) await file.delete();
    if (mounted) {
      setState(() {
        _file = null;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.pdfUrl;
    if ((url == null || url.isEmpty) && widget.fileRef == null) {
      return const _Message(text: 'لا يوجد ملف لهذا الدرس بعد');
    }
    final locked = _lockedMessage;
    if (locked != null) {
      return _Message(
        text: locked,
        action: Icon(
          Icons.lock_rounded,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }
    if (_failed) {
      return _Message(
        text: 'تعذر تحميل الملف. تأكد من الاتصال بالإنترنت وحاول مرة أخرى',
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('إعادة المحاولة'),
        ),
      );
    }
    final file = _file;
    if (file == null) {
      final progress = _progress;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 5,
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              progress == null
                  ? 'جاري تحميل الملف...'
                  : 'جاري تحميل الملف ${(progress * 100).round()}%',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      );
    }
    final student = ref.watch(authControllerProvider).valueOrNull;
    final viewer = PdfViewer.file(
      file.path,
      controller: _pdfController,
      params: PdfViewerParams(
        maxScale: 5,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        onDocumentLoadFinished: (documentRef, loadSucceeded) {
          if (!loadSucceeded) _onViewerFailed();
        },
        onViewerReady: (document, controller) {
          _pageCount = document.pages.length;
          widget.onPageChanged?.call(controller.pageNumber ?? 1, _pageCount);
        },
        onPageChanged: (page) {
          if (page != null && _pageCount > 0) {
            widget.onPageChanged?.call(page, _pageCount);
          }
        },
        onGeneralTap: (context, controller, details) {
          if (details.type != PdfViewerGeneralTapType.tap ||
              widget.onTap == null) {
            return false;
          }
          widget.onTap!();
          return false;
        },
        viewerOverlayBuilder: (context, size, handleLinkTap) => [
          PdfViewerScrollThumb(
            controller: _pdfController,
            orientation: ScrollbarOrientation.right,
          ),
        ],
      ),
    );
    if (student == null) return viewer;
    return Stack(
      fit: StackFit.expand,
      children: [
        viewer,
        Positioned.fill(
          child: ProtectedWatermark(
            lessonId: widget.fileRef?.kind == 'lesson'
                ? widget.fileRef!.id
                : null,
            isPdf: true,
            legacy: [
              ContentWatermark(
                studentName: student.fullName,
                studentPhone: student.mobile,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.base),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

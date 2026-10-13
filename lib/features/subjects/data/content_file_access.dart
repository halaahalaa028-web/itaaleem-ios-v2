import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/features/subscriptions/presentation/widgets/contact_center_access_sheet.dart'
    show lockedContentMessage;

/// Which protected file a URL points at — a lesson's own PDF or a subject
/// attachment. The signed `file_url` changes on every response and expires
/// after ~10 minutes, so this (not the URL) identifies the file: it's the
/// cache key, and it's what a fresh link is requested for.
class ContentFileRef {
  const ContentFileRef.lesson(
    this.id, {
    this.url,
    this.downloadUrl,
    this.expiresAt,
  }) : kind = 'lesson';

  const ContentFileRef.attachment(
    this.id, {
    this.url,
    this.downloadUrl,
    this.expiresAt,
  }) : kind = 'attachment';

  /// `lesson` or `attachment`.
  final String kind;
  final int id;

  /// The signed `file_url` from the last response (may be null/stale).
  final String? url;
  final String? downloadUrl;

  /// `url_expires_at` — null when the API didn't send it.
  final DateTime? expiresAt;

  /// Stable across responses, unlike the signed URL.
  String get cacheKey => '$kind-$id';

  /// Missing, already expired, or expiring within a minute.
  bool get needsRefresh {
    final u = url;
    if (u == null || u.isEmpty) return true;
    final e = expiresAt;
    if (e == null) return false;
    return e.isBefore(DateTime.now().add(const Duration(minutes: 1)));
  }

  ContentFileRef withLink(ContentFileLink link) => kind == 'lesson'
      ? ContentFileRef.lesson(
          id,
          url: link.url,
          downloadUrl: link.downloadUrl,
          expiresAt: link.expiresAt,
        )
      : ContentFileRef.attachment(
          id,
          url: link.url,
          downloadUrl: link.downloadUrl,
          expiresAt: link.expiresAt,
        );
}

class ContentFileLink {
  const ContentFileLink({required this.url, this.downloadUrl, this.expiresAt});

  final String url;
  final String? downloadUrl;
  final DateTime? expiresAt;
}

/// 403 `{locked: true}` — the student has no access to this file.
class ContentLockedException implements Exception {
  const ContentLockedException([this.message = lockedFileMessage]);

  final String message;

  /// What to show the student: on iOS never the server's subscription
  /// wording, only "contact the center".
  String get displayMessage =>
      PlatformUtils.hideSubscriptions ? lockedContentMessage : message;

  static const lockedFileMessage = 'هذا المحتوى متاح للمشتركين فقط';

  @override
  String toString() => message;
}

/// 403 `{download_disabled: true}` — the center turned PDF downloads off.
class ContentDownloadDisabledException implements Exception {
  const ContentDownloadDisabledException([this.message = defaultMessage]);

  final String message;

  static const defaultMessage = 'التحميل غير مسموح من قبل السنتر';

  @override
  String toString() => message;
}

/// 403 for an expired / tampered signed link.
class ContentLinkExpiredException implements Exception {
  const ContentLinkExpiredException();
}

DateTime? parseExpiry(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

/// `GET /lessons/{id}/file-link` or `GET /attachments/{id}/link`.
Future<ContentFileLink> fetchFreshLink(Dio dio, ContentFileRef ref) async {
  try {
    final res = await dio.get<dynamic>(
      ref.kind == 'lesson'
          ? ApiEndpoints.lessonFileLink(ref.id)
          : ApiEndpoints.attachmentLink(ref.id),
    );
    final body = res.data;
    final data = body is Map && body['data'] is Map ? body['data'] : body;
    final url = data is Map ? data['url']?.toString() : null;
    if (url == null || url.isEmpty) throw const ContentLockedException();
    return ContentFileLink(
      url: url,
      downloadUrl: data['download_url']?.toString(),
      expiresAt: parseExpiry(data['expires_at']),
    );
  } on DioException catch (e) {
    final mapped = classifyContentError(e);
    // The link endpoint itself refusing means no access, not an old link.
    if (mapped is ContentLinkExpiredException) {
      throw const ContentLockedException();
    }
    throw mapped ?? e;
  }
}

/// A valid URL for [ref]: the one it carries, or a fresh one when it's
/// missing or about to expire. [download] picks `download_url`.
Future<String> resolveContentUrl(
  Dio dio,
  ContentFileRef ref, {
  bool download = false,
}) async {
  var current = ref;
  if (current.needsRefresh) {
    current = current.withLink(await fetchFreshLink(dio, current));
  }
  final url = download ? (current.downloadUrl ?? current.url) : current.url;
  return url!;
}

/// Maps the API's file 403s to [ContentLockedException] /
/// [ContentLinkExpiredException]; `null` for anything else.
Exception? classifyContentError(DioException e) {
  if (e.response?.statusCode != 403) return null;
  var data = e.response?.data;
  // Downloads ask for bytes, so the JSON error body arrives as bytes.
  if (data is List<int>) {
    try {
      data = utf8.decode(data, allowMalformed: true);
    } catch (_) {}
  }
  if (data is String) {
    try {
      data = jsonDecode(data);
    } catch (_) {}
  }
  final text = data?.toString() ?? '';
  if (kDebugMode) debugPrint('[content-file] 403: $text');
  if (data is Map) {
    if (data['download_disabled'] == true) {
      return ContentDownloadDisabledException(
        data['message']?.toString() ??
            ContentDownloadDisabledException.defaultMessage,
      );
    }
    if (data['locked'] == true) {
      return ContentLockedException(
        data['message']?.toString() ?? ContentLockedException.lockedFileMessage,
      );
    }
    if ((data['message']?.toString() ?? '').contains('صلاحية')) {
      return const ContentLinkExpiredException();
    }
  }
  if (text.contains('"download_disabled":true')) {
    return const ContentDownloadDisabledException();
  }
  if (text.contains('"locked":true') || text.contains('"locked": true')) {
    return const ContentLockedException();
  }
  // A signed-URL 403 that isn't "locked" means the link expired/was tampered.
  return const ContentLinkExpiredException();
}

/// Downloads [ref] to [savePath]: resolves a valid URL first, and on an
/// expired-link 403 fetches a fresh one and retries exactly once. Throws
/// [ContentLockedException] when the student has no access.
Future<void> downloadContentFile(
  Dio dio,
  ContentFileRef ref,
  String savePath, {
  bool download = false,
  CancelToken? cancelToken,
  ProgressCallback? onReceiveProgress,
}) async {
  Future<void> attempt(ContentFileRef r) async {
    final url = await resolveContentUrl(dio, r, download: download);
    try {
      await dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );
    } on DioException catch (e) {
      throw classifyContentError(e) ?? e;
    }
  }

  try {
    await attempt(ref);
  } on ContentLinkExpiredException {
    await attempt(ref.withLink(await fetchFreshLink(dio, ref)));
  }
}

/// Whether this student may still open lesson [lessonId] — checked before
/// playing an offline download while online. `false` when the API says it's
/// locked (403, `is_locked: true` or `is_accessible: false`); `null` when it
/// couldn't tell (network error etc.), in which case callers keep the
/// current offline behavior.
Future<bool?> checkLessonAccess(Dio dio, int lessonId) async {
  try {
    final res = await dio.get<dynamic>(ApiEndpoints.lectureDetails(lessonId));
    final body = res.data;
    final data = body is Map && body['data'] is Map ? body['data'] : body;
    if (data is! Map) return null;
    if (data['is_locked'] == true || data['is_accessible'] == false) {
      return false;
    }
    return true;
  } on DioException catch (e) {
    if (e.response?.statusCode == 403) return false;
    return null;
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/providers/cache_for.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';

/// The center's content rules as the student app reads them — every field
/// is optional on the wire and defaults to the app's previous behavior, so
/// an older server (no new fields) changes nothing.
class ContentPolicy {
  const ContentPolicy({
    this.canDownloadPdf = true,
    this.canDownloadVideo = true,
    this.watermark,
  });

  /// `can_download_pdf` — `false` hides every PDF download/save/share.
  final bool canDownloadPdf;

  /// `can_download_video` — `false` hides offline video download.
  final bool canDownloadVideo;

  /// `center.watermark` — `null` keeps the built-in watermark.
  final WatermarkConfig? watermark;

  static ContentPolicy fromCenterJson(Map<String, dynamic>? center) {
    if (center == null) return const ContentPolicy();
    return ContentPolicy(
      canDownloadPdf: readFlag(center['can_download_pdf']) ?? true,
      canDownloadVideo: readFlag(center['can_download_video']) ?? true,
      watermark: WatermarkConfig.tryParse(center['watermark']),
    );
  }
}

/// `true`/`false`, `1`/`0`, `"1"`/`"true"` — `null` when absent/unknown.
bool? readFlag(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final s = value.toLowerCase().trim();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return null;
}

/// The profile's center rules (`/v1/profile` → `center`).
final contentPolicyProvider = Provider<ContentPolicy>((ref) {
  final center = ref.watch(
    authControllerProvider.select((s) => s.valueOrNull?.centerJson),
  );
  return ContentPolicy.fromCenterJson(center);
});

enum WatermarkPosition { center, corner, moving }

/// The server's watermark object:
/// `{enabled, text, opacity, font_size, color, position, move_interval,
/// on_pdf}` (in `lesson.watermark` and `center.watermark`).
class WatermarkConfig {
  const WatermarkConfig({
    required this.enabled,
    required this.text,
    required this.opacity,
    required this.fontSize,
    required this.color,
    required this.position,
    required this.moveInterval,
    required this.onPdf,
    this.onVideo,
    this.centerColor = false,
    bool onPdfSent = false,
  }) : _onPdfSent = onPdfSent;

  final bool _onPdfSent;

  /// `on_video` — `null` on an older server that doesn't send it.
  final bool? onVideo;

  /// `enabled` now means "shown in at least one place"; each surface has
  /// its own flag. A missing `on_video` falls back to `enabled`.
  bool get showOnVideo => onVideo ?? enabled;

  /// `on_pdf: false` → no PDF watermark. Missing → `enabled`.
  bool get showOnPdf => _onPdfSent ? onPdf : enabled && onPdf;

  final bool enabled;

  /// `color: "center"` — the center's brand (the app's primary) color.
  final bool centerColor;

  /// Empty → the app builds "name • phone" from the logged-in student.
  final String text;
  final double opacity;
  final double fontSize;

  /// `null` → white (the built-in watermark's color).
  final Color? color;
  final WatermarkPosition position;
  final Duration moveInterval;
  final bool onPdf;

  /// `null` for anything that isn't a watermark object (absent, `null`,
  /// a string…) — the caller then keeps the built-in behavior.
  static WatermarkConfig? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final opacity = num.tryParse('${raw['opacity'] ?? ''}')?.toDouble();
    final interval = num.tryParse('${raw['move_interval'] ?? ''}')?.toInt();
    return WatermarkConfig(
      enabled: readFlag(raw['enabled']) ?? true,
      text: '${raw['text'] ?? ''}'.trim(),
      opacity: (opacity ?? 0.25).clamp(0.02, 1.0),
      fontSize: fontSizeOf(raw['font_size']),
      color: parseWatermarkColor(raw['color']?.toString()),
      position: switch ('${raw['position'] ?? ''}'.toLowerCase()) {
        'corner' => WatermarkPosition.corner,
        'moving' => WatermarkPosition.moving,
        _ => WatermarkPosition.center,
      },
      moveInterval: Duration(seconds: (interval ?? 8).clamp(2, 120)),
      onPdf: readFlag(raw['on_pdf']) ?? true,
      onVideo: readFlag(raw['on_video']),
      onPdfSent: readFlag(raw['on_pdf']) != null,
      centerColor: '${raw['color'] ?? ''}'.toLowerCase() == 'center',
    );
  }

  /// small=12, medium=16, large=22 (or a raw number).
  static double fontSizeOf(Object? raw) {
    final n = num.tryParse('${raw ?? ''}');
    if (n != null) return n.toDouble().clamp(8, 40);
    return switch ('$raw'.toLowerCase()) {
      'small' => 12,
      'large' => 22,
      _ => 16,
    };
  }
}

/// `#RRGGBB` / `#AARRGGBB`, or a named `white|black|gray`. `null` otherwise
/// (`center` is resolved by the caller to the app's primary color).
Color? parseWatermarkColor(String? raw) {
  if (raw == null) return null;
  final s = raw.trim().toLowerCase();
  switch (s) {
    case 'white':
      return Colors.white;
    case 'black':
      return Colors.black;
    case 'gray':
    case 'grey':
      return Colors.grey;
  }
  final hex = s.replaceFirst('#', '');
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  if (hex.length == 6) return Color(0xFF000000 | value);
  if (hex.length == 8) return Color(value);
  return null;
}

/// `lesson.watermark` from `GET /lessons/{id}` — `null` when the lesson has
/// none, or the call fails (the caller then falls back to the center's, then
/// to the built-in watermark). Cached 5 minutes, failures included.
///
/// Never awaited by the player: [effectiveWatermarkProvider] reads it with
/// `valueOrNull`, so the video starts with the profile/built-in watermark
/// and switches when (if) this arrives.
final lessonWatermarkProvider = FutureProvider.autoDispose
    .family<WatermarkConfig?, int>((ref, lessonId) {
      return ref.cached(() async {
        try {
          final res = await ref
              .read(dioClientProvider)
              .get<dynamic>('/lessons/$lessonId');
          final body = res.data;
          final data = body is Map && body['data'] is Map
              ? body['data'] as Map
              : body;
          if (data is! Map) return null;
          final lesson = data['lesson'] is Map ? data['lesson'] as Map : data;
          return WatermarkConfig.tryParse(lesson['watermark']);
        } catch (e) {
          // Any failure (429, 403, offline, odd JSON) resolves to `null` —
          // a *successful* value, so it's cached like a hit and never
          // re-requested in a loop; the profile/built-in watermark is used.
          if (kDebugMode) {
            debugPrint(
              '[lessonWatermark] $lessonId failed: '
              '${e is DioException ? e.response?.statusCode : e}',
            );
          }
          return null;
        }
      }, duration: const Duration(minutes: 5));
    });

/// The watermark to apply for [lessonId]: the lesson's, else the center's,
/// else `null` (= the built-in one, unchanged).
final effectiveWatermarkProvider = Provider.autoDispose
    .family<WatermarkConfig?, int?>((ref, lessonId) {
      final center = ref.watch(contentPolicyProvider).watermark;
      if (lessonId == null || lessonId <= 0) return center;
      final lesson = ref.watch(lessonWatermarkProvider(lessonId)).valueOrNull;
      return lesson ?? center;
    });

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Global safety nets: an error never crashes the app or shows a red/grey
/// screen to the user. Errors are logged in debug builds only.
class AppErrorHandling {
  AppErrorHandling._();

  /// Call once before `runApp`.
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (kDebugMode) {
        // Keeps the usual debug console dump.
        (previous ?? FlutterError.presentError)(details);
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      log(error, stack);
      return true; // handled — don't crash
    };
    // Debug keeps Flutter's default red screen (useful while developing).
    if (!kDebugMode) {
      ErrorWidget.builder = (details) => const _BrokenPart();
    }
  }

  /// For `runZonedGuarded`, and anywhere else an error is swallowed.
  static void log(Object error, StackTrace? stack) {
    if (kDebugMode) debugPrint('>>> Uncaught: $error\n$stack');
  }
}

/// What a widget that failed to build shows in release: a short message and
/// "إعادة المحاولة" (rebuilds the app's widgets).
class _BrokenPart extends StatelessWidget {
  const _BrokenPart();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ColoredBox(
        color: scheme.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: scheme.onSurfaceVariant,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  'حدث خطأ في عرض هذا الجزء',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    color: scheme.onSurface,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => WidgetsBinding.instance.reassembleApplication(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'إعادة المحاولة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: scheme.onPrimary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

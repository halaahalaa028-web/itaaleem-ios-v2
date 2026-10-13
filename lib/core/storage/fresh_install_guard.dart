import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wipes secure storage on the first launch after an install.
///
/// The iOS Keychain survives uninstalling the app, and an Android restore
/// could bring back secure entries — either would sign the old account
/// back in. SharedPreferences is wiped on uninstall on both platforms (and
/// excluded from Android backup), so a missing marker means a fresh install.
class FreshInstallGuard {
  FreshInstallGuard._();

  /// Kept across logout (see the wiper's device keys).
  static const markerKey = 'install_first_run_done';

  static Future<void> run() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(markerKey) ?? false) return;
      // An update from a version without the marker already has prefs —
      // don't sign those users out.
      if (prefs.getKeys().isNotEmpty) {
        await prefs.setBool(markerKey, true);
        return;
      }
      await const FlutterSecureStorage(
        aOptions: AndroidOptions(resetOnError: true),
      ).deleteAll();
      await prefs.setBool(markerKey, true);
      if (kDebugMode)
        debugPrint('[FreshInstallGuard] first run: secure storage cleared');
    } catch (e) {
      if (kDebugMode) debugPrint('[FreshInstallGuard] failed: $e');
    }
  }
}

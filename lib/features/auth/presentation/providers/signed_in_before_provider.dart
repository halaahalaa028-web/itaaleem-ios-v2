import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _signedInBeforeKey = 'has_signed_in_before';

/// Whether any account has ever signed in on this install. Decides where an
/// unauthenticated student lands: the very first open goes to "إنشاء حساب",
/// a student who signed in before (and logged out) goes to "تسجيل الدخول".
///
/// A device-level flag (like the theme / device id) — kept across logout.
class SignedInBeforeController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_signedInBeforeKey) ?? false;
  }

  Future<void> mark() async {
    if (state.valueOrNull == true) return;
    state = const AsyncData(true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_signedInBeforeKey, true);
  }
}

final signedInBeforeProvider =
    AsyncNotifierProvider<SignedInBeforeController, bool>(
      SignedInBeforeController.new,
    );

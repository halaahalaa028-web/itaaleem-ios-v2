import 'package:itaaleem/features/auth/presentation/widgets/logout_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';

/// Shown when `/profile` says `must_change_password: true` (the center gave
/// the student a temporary password). No way back or around it: no back
/// button, `PopScope(canPop: false)`, and the router redirects every other
/// path here until the password changes. "تسجيل الخروج" is the only exit.
///
/// `POST /profile/password {current_password, password,
/// password_confirmation}` → the profile is re-fetched; once
/// `must_change_password` is false the router sends the student home.
class ForceChangePasswordScreen extends ConsumerStatefulWidget {
  const ForceChangePasswordScreen({super.key});

  @override
  ConsumerState<ForceChangePasswordScreen> createState() =>
      _ForceChangePasswordScreenState();
}

class _ForceChangePasswordScreenState
    extends ConsumerState<ForceChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(dioClientProvider)
          .post<dynamic>(
            '/profile/password',
            data: {
              'current_password': _current.text,
              'password': _password.text,
              'password_confirmation': _confirm.text,
            },
          );
      await ref.read(authControllerProvider.notifier).refreshProfile();
      if (!mounted) return;
      AppToast.showSuccess(context, 'تم تغيير كلمة السر');
      // The router leaves this screen by itself once the refreshed profile
      // has `must_change_password: false`.
    } catch (e) {
      // 422: the server's Arabic message as-is.
      if (mounted) setState(() => _error = failureOf(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    InputDecoration field(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        onPressed: () => setState(() => _obscure = !_obscure),
        icon: Icon(
          _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        ),
      ),
    );
    String? minSix(String? v) =>
        (v ?? '').length < 6 ? 'كلمة السر 6 حروف على الأقل' : null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('تغيير كلمة السر'),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Icon(Icons.lock_reset_rounded, size: 56, color: scheme.primary),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'لازم تغيّر كلمة السر المؤقتة اللي السنتر بعتهالك قبل ما تكمل',
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _current,
                  obscureText: _obscure,
                  decoration: field(
                    'كلمة السر الحالية (المؤقتة)',
                    Icons.key_rounded,
                  ),
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'اكتب كلمة السر الحالية' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: field('كلمة السر الجديدة', Icons.lock_rounded),
                  validator: minSix,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _confirm,
                  obscureText: _obscure,
                  decoration: field(
                    'تأكيد كلمة السر الجديدة',
                    Icons.lock_outline_rounded,
                  ),
                  validator: (v) =>
                      minSix(v) ??
                      (v != _password.text ? 'كلمتا السر غير متطابقتين' : null),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: scheme.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Text('حفظ كلمة السر'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => confirmAndLogout(context, ref),
                  icon: Icon(Icons.logout_rounded, color: scheme.error),
                  label: Text(
                    'تسجيل الخروج',
                    style: TextStyle(color: scheme.error),
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

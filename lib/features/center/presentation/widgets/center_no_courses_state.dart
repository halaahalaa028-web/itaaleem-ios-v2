import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_empty_state.dart';
import 'package:itaaleem/features/center/domain/entities/center_model.dart';

/// Shown when a (usually brand-new) center has no courses yet — in the
/// join flow's course picker and on home in place of the subjects.
class CenterNoCoursesState extends StatelessWidget {
  const CenterNoCoursesState({
    super.key,
    this.center,
    this.showBack = false,
    this.extraAction,
  });

  /// Passed to the contact screen when the student hasn't joined yet (so it
  /// can't look up "my center" on its own).
  final CenterModel? center;
  final bool showBack;
  final Widget? extraAction;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.school_outlined,
      title: 'السنتر لسه ما أضافش كورسات',
      subtitle: 'تابع مع إدارة السنتر، وأول ما يضيفوا محتوى هيظهرلك هنا',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?extraAction,
          if (extraAction != null) const SizedBox(height: AppSpacing.sm),
          FilledButton.tonalIcon(
            onPressed: () =>
                context.push<void>(contactCenterPath, extra: center),
            icon: const Icon(Icons.support_agent_rounded),
            label: const Text('تواصل مع السنتر'),
          ),
          if (showBack) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('رجوع'),
            ),
          ],
        ],
      ),
    );
  }
}

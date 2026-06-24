import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shown on the few screens that post a JournalEntry (Sales, Purchases,
/// Payroll, Fixed Assets depreciation, Approvals) when the signed-in
/// user holds `readOnlyAuditor` on the active business — see
/// `isReadOnlyProvider`. The screen's own Save/Pay/Approve button should
/// also be disabled; this banner is what explains why.
class ReadOnlyBanner extends StatelessWidget {
  const ReadOnlyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined, size: 16, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              "Read-only access — you can view this, but can't post or change anything here.",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppSidebarItem {
  const AppSidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
}

class AppSidebarGroup {
  const AppSidebarGroup({this.title, required this.items});

  /// Null for the first, unlabeled group (e.g. Dashboard) — Linear/
  /// Notion-style sidebars usually leave the top-level items ungrouped.
  final String? title;
  final List<AppSidebarItem> items;
}

/// A grouped, labeled sidebar — replaces the bare Material
/// `NavigationRail` with the section-header pattern Linear/Notion use,
/// so 20+ nav destinations (this app has that many across three
/// business-type verticals) read as organized groups instead of one
/// long undifferentiated list. See PHASES.md Section 19/20 ("Design
/// System", "Desktop UX") — built now in the post-Phase-9 UI pass.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.header,
    required this.groups,
    required this.footer,
  });

  final Widget header;
  final List<AppSidebarGroup> groups;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;

    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: Theme.of(context).navigationRailTheme.backgroundColor,
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: Column(
        children: [
          header,
          Divider(color: borderColor, height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                for (final group in groups) ..._buildGroup(context, group),
              ],
            ),
          ),
          Divider(color: borderColor, height: 1),
          footer,
        ],
      ),
    );
  }

  List<Widget> _buildGroup(BuildContext context, AppSidebarGroup group) {
    final widgets = <Widget>[];
    if (group.title != null) {
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
        child: Text(
          group.title!.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
              ),
        ),
      ));
    }
    for (final item in group.items) {
      widgets.add(_SidebarTile(item: item));
    }
    return widgets;
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({required this.item});

  final AppSidebarItem item;

  @override
  Widget build(BuildContext context) {
    final selectedColor = AppColors.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
      child: Material(
        color: item.selected ? selectedColor.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: item.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(item.icon, size: 19, color: item.selected ? selectedColor : Colors.grey.shade600),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    item.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: item.selected ? selectedColor : null,
                          fontWeight: item.selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                    overflow: TextOverflow.ellipsis,
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

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const kTafseelChips = <String>[
  'Local kharcha',
  'Diesel',
  'Oil + filter',
  'Peshgi',
  'Driver salary',
  'Conductor salary',
  'Commission',
  'Adda card',
  'Mistri / mazdori',
  'Tyre',
  'Repair',
];

class TafseelChips extends StatelessWidget {
  const TafseelChips({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final chip in kTafseelChips)
          ActionChip(
            label: Text(chip, style: const TextStyle(fontSize: 13)),
            onPressed: () => onSelected(chip),
            visualDensity: VisualDensity.comfortable,
          ),
      ],
    );
  }
}

class DateRangeFilterBar extends StatelessWidget {
  const DateRangeFilterBar({
    super.key,
    required this.from,
    required this.to,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? from;
  final DateTime? to;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasRange = from != null && to != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(
                hasRange
                    ? '${_fmt(from!)} → ${_fmt(to!)}'
                    : 'Date filter',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (hasRange) ...[
            const SizedBox(width: 8),
            IconButton(onPressed: onClear, icon: const Icon(Icons.clear), tooltip: 'Clear'),
          ],
        ],
      ),
    );
  }
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

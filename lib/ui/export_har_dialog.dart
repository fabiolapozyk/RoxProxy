import 'package:flutter/material.dart';

import '../providers/har_export_provider.dart';

/// Asks whether a HAR export should include all captured calls or only those
/// currently matching the filter (issue #10).
///
/// Returns null when the user cancels.
Future<HarExportScope?> showHarExportDialog(
  BuildContext context, {
  required int total,
  required int filtered,
  required bool filterActive,
}) {
  return showDialog<HarExportScope>(
    context: context,
    builder: (context) {
      var scope = filterActive ? HarExportScope.filtered : HarExportScope.all;
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Export HAR'),
            content: SizedBox(
              width: 420,
              child: RadioGroup<HarExportScope>(
                groupValue: scope,
                onChanged: (value) {
                  if (value != null) setState(() => scope = value);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ScopeTile(
                      value: HarExportScope.all,
                      title: 'All calls',
                      subtitle: '$total calls',
                    ),
                    const SizedBox(height: 4),
                    _ScopeTile(
                      value: HarExportScope.filtered,
                      title: 'Filtered calls only',
                      subtitle: filterActive
                          ? '$filtered of $total (filter active)'
                          : 'No active filter: same as all calls',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: total == 0
                    ? null
                    : () => Navigator.of(context).pop(scope),
                child: const Text('Export…'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _ScopeTile extends StatelessWidget {
  final HarExportScope value;
  final String title;
  final String subtitle;

  const _ScopeTile({
    required this.value,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<HarExportScope>(
      value: value,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
    );
  }
}

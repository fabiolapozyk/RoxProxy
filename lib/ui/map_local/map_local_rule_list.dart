import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/map_local_rule.dart';
import '../../providers/map_local_provider.dart';

/// Reorderable rule list — list position defines matching priority.
class MapLocalRuleList extends ConsumerWidget {
  final ValueChanged<MapLocalRule> onEdit;

  const MapLocalRuleList({super.key, required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(mapLocalProvider);
    final notifier = ref.read(mapLocalProvider.notifier);

    if (rules.isEmpty) {
      return const Center(
        child: Text(
          'No Map Local rules.\nAdd a rule to start serving local files.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }

    return ReorderableListView.builder(
      itemCount: rules.length,
      onReorder: notifier.reorder,
      buildDefaultDragHandles: false,
      itemBuilder: (context, i) {
        final rule = rules[i];
        return _RuleTile(
          key: ValueKey(rule.id),
          rule: rule,
          priority: i + 1,
          onEdit: () => onEdit(rule),
          onDuplicate: () => notifier.duplicateRule(rule.id),
          onDelete: () => notifier.removeRule(rule.id),
          onToggle: () => notifier.toggleRule(rule.id),
        );
      },
    );
  }
}

class _RuleTile extends StatelessWidget {
  final MapLocalRule rule;
  final int priority;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _RuleTile({
    super.key,
    required this.rule,
    required this.priority,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withAlpha(120);
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4, top: 2, bottom: 2),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: priority - 1,
            child: const Icon(Icons.drag_indicator,
                size: 18, color: Colors.grey),
          ),
          Checkbox(
            value: rule.isEnabled,
            onChanged: (_) => onToggle(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        rule.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: rule.isEnabled
                              ? null
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withAlpha(100),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '#$priority',
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
                Text(
                  '${rule.httpMethod}  ${rule.hostPattern} → ${rule.pathPattern}  ·  ${rule.statusCode}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Icon(
                      rule.filePath.isEmpty
                          ? Icons.insert_drive_file_outlined
                          : Icons.folder_outlined,
                      size: 12,
                      color: rule.filePath.isEmpty
                          ? Theme.of(context).colorScheme.error.withAlpha(150)
                          : muted,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        rule.filePath.isEmpty
                            ? 'No file selected'
                            : rule.filePath,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            onPressed: onEdit,
            tooltip: 'Edit',
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          IconButton(
            icon: const Icon(Icons.content_copy_outlined, size: 15),
            onPressed: onDuplicate,
            tooltip: 'Duplicate',
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            onPressed: onDelete,
            tooltip: 'Delete',
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }
}

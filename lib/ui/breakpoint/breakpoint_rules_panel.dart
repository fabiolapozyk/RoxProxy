import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/breakpoint_rule.dart';
import '../../providers/breakpoint_rules_provider.dart';
import '../../providers/settings_provider.dart';
import 'breakpoint_rule_edit.dart';

/// Manager delle regole breakpoint mostrato nella sidebar di Settings.
/// Contiene il toggle globale della funzionalità, la toolbar Add e la lista
/// con toggle/edit/delete/duplicate.
class BreakpointRulesManager extends ConsumerWidget {
  const BreakpointRulesManager({super.key});

  Future<void> _addRule(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<BreakpointRule>(
      context: context,
      builder: (_) => const BreakpointRuleEditDialog(),
    );
    if (created != null) {
      ref.read(breakpointRulesProvider.notifier).addRule(created);
    }
  }

  Future<void> _editRule(
    BuildContext context,
    WidgetRef ref,
    BreakpointRule rule,
  ) async {
    final updated = await showDialog<BreakpointRule>(
      context: context,
      builder: (_) => BreakpointRuleEditDialog(initial: rule),
    );
    if (updated != null) {
      ref.read(breakpointRulesProvider.notifier).updateRule(updated);
    }
  }

  void _snack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(breakpointRulesProvider);
    final breakpointsEnabled = ref.watch(
      settingsProvider.select((s) => s.breakpointEnabled),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            'Requests matching a rule are suspended for inspection. '
            'Breakpoints are active only when at least one rule is enabled: '
            'with no rules nothing is intercepted. Add a rule with target '
            '"Response" (or "Request + Response") to also suspend responses. '
            'Changes apply when the proxy is restarted.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Text('Breakpoints enabled', style: TextStyle(fontSize: 13)),
              const Spacer(),
              Switch(
                value: breakpointsEnabled,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).setBreakpointEnabled(v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _addRule(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add rule', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${rules.length} rule(s)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),
        Expanded(
          child: rules.isEmpty
              ? Center(
                  child: Text(
                    'No breakpoint rules.\nAdd a rule to start intercepting '
                    'requests.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                )
              : ListView.builder(
                  itemCount: rules.length,
                  itemExtent: 48,
                  itemBuilder: (context, index) {
                    final rule = rules[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        rule.isEnabled
                            ? Icons.pause_circle
                            : Icons.pause_circle_outline,
                        size: 20,
                        color: rule.isEnabled
                            ? const Color(0xFF34C759)
                            : Colors.grey,
                      ),
                      title: Text(
                        rule.displayName,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${rule.httpMethod} · ${rule.hostPattern}'
                        ' · ${rule.pathPattern} · ${rule.target.name}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          final notifier = ref.read(
                            breakpointRulesProvider.notifier,
                          );
                          switch (action) {
                            case 'toggle':
                              notifier.toggleRule(rule.id);
                            case 'edit':
                              _editRule(context, ref, rule);
                            case 'duplicate':
                              notifier.duplicateRule(rule.id);
                              _snack(context, 'Rule duplicated');
                            case 'delete':
                              notifier.removeRule(rule.id);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text('Enable/Disable'),
                          ),
                          PopupMenuItem(value: 'edit', child: Text('Edit…')),
                          PopupMenuItem(
                            value: 'duplicate',
                            child: Text('Duplicate'),
                          ),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

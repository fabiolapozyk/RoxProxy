import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/map_local_rule.dart';
import '../../providers/map_local_provider.dart';
import 'map_local_rule_edit.dart';
import 'map_local_rule_list.dart';

/// Full Map Local panel shown in a dialog from the main toolbar.
class MapLocalPanel extends ConsumerWidget {
  const MapLocalPanel({super.key});

  Future<void> _addRule(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<MapLocalRule>(
      context: context,
      builder: (_) => const MapLocalRuleEditDialog(),
    );
    if (created != null) {
      ref.read(mapLocalProvider.notifier).addRule(created);
    }
  }

  Future<void> _editRule(
      BuildContext context, WidgetRef ref, MapLocalRule rule) async {
    final updated = await showDialog<MapLocalRule>(
      context: context,
      builder: (_) => MapLocalRuleEditDialog(initial: rule),
    );
    if (updated != null) {
      ref.read(mapLocalProvider.notifier).updateRule(updated);
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final rules = ref.read(mapLocalProvider);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Map Local rules',
      fileName: 'map_local_rules.json',
      type: FileType.any,
    );
    if (path == null) return;
    if (!context.mounted) return;
    final file = File(path);
    try {
      file.writeAsStringSync(JsonEncoder.withIndent('  ').convert(
        rules.map((r) => r.toJson()).toList(),
      ));
      _snack(context, 'Exported ${rules.length} rule(s) to $path');
    } catch (e) {
      _snack(context, 'Export failed: $e', error: true);
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import Map Local rules',
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    if (!context.mounted) return;
    try {
      final decoded = jsonDecode(File(path).readAsStringSync());
      if (decoded is! List) {
        _snack(context, 'Import failed: file must contain a JSON array',
            error: true);
        return;
      }
      final rules = decoded
          .map((e) => MapLocalRule.fromJson(e as Map<String, dynamic>))
          .toList();
      ref.read(mapLocalProvider.notifier).setRules(rules);
      _snack(context, 'Imported ${rules.length} rule(s)');
    } catch (e) {
      _snack(context, 'Import failed: $e', error: true);
    }
  }

  void _snack(BuildContext context, String message, {bool error = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        backgroundColor:
            error ? Theme.of(context).colorScheme.error : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(mapLocalProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          ruleCount: rules.length,
          onAdd: () => _addRule(context, ref),
          onImport: () => _import(context, ref),
          onExport: () => _export(context, ref),
          onClose: () => Navigator.of(context).pop(),
        ),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            'Requests matching a rule are answered with the local file '
            'instead of reaching the server. Rules are evaluated top-down; '
            'the first match wins. Changes apply when the proxy is restarted.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),
        Expanded(
          child: MapLocalRuleList(
            onEdit: (rule) => _editRule(context, ref, rule),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final int ruleCount;
  final VoidCallback onAdd;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onClose;

  const _Header({
    required this.ruleCount,
    required this.onAdd,
    required this.onImport,
    required this.onExport,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Text(
            'Map Local',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Text(
            '$ruleCount rule${ruleCount == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.file_upload_outlined, size: 16),
            label: const Text('Export'),
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text('Import'),
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add rule'),
            style: ElevatedButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

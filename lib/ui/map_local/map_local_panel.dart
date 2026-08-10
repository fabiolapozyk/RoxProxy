import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/map_local_rule.dart';
import '../../providers/map_local_provider.dart';
import 'map_local_rule_edit.dart';
import 'map_local_rule_list.dart';

/// Map Local rule manager shown inside the Settings sidebar.
/// Contains the Add / Import / Export toolbar and the reorderable rule list.
class MapLocalRuleManager extends ConsumerWidget {
  const MapLocalRuleManager({super.key});

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
    BuildContext context,
    WidgetRef ref,
    MapLocalRule rule,
  ) async {
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
      file.writeAsStringSync(
        JsonEncoder.withIndent(
          '  ',
        ).convert(rules.map((r) => r.toJson()).toList()),
      );
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
        _snack(
          context,
          'Import failed: file must contain a JSON array',
          error: true,
        );
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
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            'Requests matching a rule are answered with the local file '
            'instead of reaching the server. Rules are evaluated top-down; '
            'the first match wins. Changes apply when the proxy is restarted.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          child: Row(
            children: [
              const Spacer(),
              TextButton.icon(
                onPressed: () => _export(context, ref),
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('Export'),
                style: TextButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => _import(context, ref),
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('Import'),
                style: TextButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                onPressed: () => _addRule(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add rule'),
                style: ElevatedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ),
        ),
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

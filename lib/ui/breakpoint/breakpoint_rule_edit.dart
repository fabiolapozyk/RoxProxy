import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/breakpoint_rule.dart';

/// Editor di una regola breakpoint (host/path/metodo/target/abilitazione).
class BreakpointRuleEditDialog extends ConsumerStatefulWidget {
  final BreakpointRule? initial;

  const BreakpointRuleEditDialog({super.key, this.initial});

  @override
  ConsumerState<BreakpointRuleEditDialog> createState() =>
      _BreakpointRuleEditDialogState();
}

class _BreakpointRuleEditDialogState
    extends ConsumerState<BreakpointRuleEditDialog> {
  static const _methods = [
    'ANY',
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _pathController;
  late String _method;
  late BreakpointTarget _target;
  late bool _isEnabled;

  @override
  void initState() {
    super.initState();
    final rule = widget.initial;
    _nameController = TextEditingController(text: rule?.name ?? '');
    _hostController = TextEditingController(text: rule?.hostPattern ?? '*');
    _pathController = TextEditingController(text: rule?.pathPattern ?? '**');
    _method = rule?.httpMethod ?? 'ANY';
    _target = rule?.target ?? BreakpointTarget.request;
    _isEnabled = rule?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _save() {
    final rule = BreakpointRule(
      id: widget.initial?.id,
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      hostPattern: _hostController.text.trim().isEmpty
          ? '*'
          : _hostController.text.trim(),
      pathPattern: _pathController.text.trim().isEmpty
          ? '**'
          : _pathController.text.trim(),
      httpMethod: _method,
      target: _target,
      isEnabled: _isEnabled,
    );
    Navigator.of(context).pop(rule);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Add breakpoint rule' : 'Edit breakpoint rule',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name (optional)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Host pattern',
                  helperText: 'es. api.example.com, *.example.com, *',
                  isDense: true,
                ),
                textAlign: TextAlign.left,
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: 'Path pattern',
                  helperText: 'es. /api/**, **, *.json (* non attraversa /)',
                  isDense: true,
                ),
                textAlign: TextAlign.left,
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _method,
                      isExpanded: true,
                      items: _methods
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(m, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _method = v ?? _method),
                      decoration: const InputDecoration(
                        labelText: 'Method',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<BreakpointTarget>(
                      initialValue: _target,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: BreakpointTarget.request,
                          child: Text(
                            'Request',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: BreakpointTarget.response,
                          child: Text(
                            'Response',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: BreakpointTarget.both,
                          child: Text(
                            'Request + Response',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _target = v ?? _target),
                      decoration: const InputDecoration(
                        labelText: 'Target',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled', style: TextStyle(fontSize: 13)),
                value: _isEnabled,
                onChanged: (v) => setState(() => _isEnabled = v),
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
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

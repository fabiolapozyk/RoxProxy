import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/map_local_rule.dart';

/// Create / edit dialog for a Map Local rule.
class MapLocalRuleEditDialog extends StatefulWidget {
  final MapLocalRule? initial;

  const MapLocalRuleEditDialog({super.key, this.initial});

  @override
  State<MapLocalRuleEditDialog> createState() => _MapLocalRuleEditDialogState();
}

class _MapLocalRuleEditDialogState extends State<MapLocalRuleEditDialog> {
  static const _httpMethods = [
    'ANY',
    'GET',
    'POST',
    'PUT',
    'DELETE',
    'PATCH',
    'HEAD',
    'OPTIONS',
  ];

  static const _contentTypes = [
    null, // Auto-detect from file extension
    'application/json',
    'text/plain; charset=utf-8',
    'text/html; charset=utf-8',
    'text/css; charset=utf-8',
    'application/javascript',
    'application/xml',
    'image/png',
    'image/jpeg',
    'image/svg+xml',
    'application/pdf',
    'application/octet-stream',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _pathController;
  late final TextEditingController _filePathController;
  late final TextEditingController _statusCodeController;
  late final TextEditingController _notesController;

  late String _httpMethod;
  String? _contentType;
  late bool _isEnabled;
  late bool _isCaseSensitive;
  late bool _useRegex;
  late final List<({TextEditingController key, TextEditingController value})>
      _customHeaderControllers;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _nameController = TextEditingController(text: r?.name ?? '');
    _hostController = TextEditingController(text: r?.hostPattern ?? '*');
    _pathController = TextEditingController(text: r?.pathPattern ?? '**');
    _filePathController = TextEditingController(text: r?.filePath ?? '');
    _statusCodeController =
        TextEditingController(text: (r?.statusCode ?? 200).toString());
    _notesController = TextEditingController(text: r?.notes ?? '');
    _httpMethod = r?.httpMethod ?? 'ANY';
    _contentType = r?.contentType;
    _isEnabled = r?.isEnabled ?? true;
    _isCaseSensitive = r?.isCaseSensitive ?? true;
    _useRegex = r?.useRegex ?? false;
    _customHeaderControllers = [
      for (final entry in (r?.customHeaders ?? {}).entries)
        (key: TextEditingController(text: entry.key),
            value: TextEditingController(text: entry.value)),
    ];
    if (_customHeaderControllers.isEmpty) {
      _customHeaderControllers.add(
        (key: TextEditingController(), value: TextEditingController()),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _pathController.dispose();
    _filePathController.dispose();
    _statusCodeController.dispose();
    _notesController.dispose();
    for (final c in _customHeaderControllers) {
      c.key.dispose();
      c.value.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select response file',
      allowMultiple: false,
      type: FileType.any,
    );
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.single.path;
      if (path != null) {
        setState(() => _filePathController.text = path);
      }
    }
  }

  void _save() {
    final statusCode = int.tryParse(_statusCodeController.text.trim()) ?? 200;
    final headers = <String, String>{};
    for (final c in _customHeaderControllers) {
      final key = c.key.text.trim();
      if (key.isNotEmpty) headers[key] = c.value.text;
    }

    final updated = (widget.initial ?? MapLocalRule()).copyWith(
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      hostPattern: _hostController.text.trim().isEmpty
          ? '*'
          : _hostController.text.trim(),
      pathPattern: _pathController.text.trim().isEmpty
          ? '**'
          : _pathController.text.trim(),
      httpMethod: _httpMethod,
      filePath: _filePathController.text.trim(),
      statusCode: statusCode,
      contentType: _contentType,
      customHeaders: headers,
      isEnabled: _isEnabled,
      isCaseSensitive: _isCaseSensitive,
      useRegex: _useRegex,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit rule' : 'New rule',
          style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 520,
        height: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Enabled',
                    style: TextStyle(fontSize: 13)),
                value: _isEnabled,
                onChanged: (v) => setState(() => _isEnabled = v),
              ),
              _field(
                label: 'Name (optional)',
                controller: _nameController,
                hint: 'e.g. Mock users API',
              ),
              _field(
                label: 'Host pattern',
                controller: _hostController,
                hint: 'api.example.com, *.example.com, *',
              ),
              _field(
                label: 'Path pattern',
                controller: _pathController,
                hint: '/api/users, /api/*, **.json, /api/v1/**',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: _httpMethod,
                      isExpanded: true,
                      decoration: _decoration(label: 'HTTP method'),
                      items: [
                        for (final m in _httpMethods)
                          DropdownMenuItem(value: m, child: Text(m)),
                      ],
                      onChanged: (v) =>
                          setState(() => _httpMethod = v ?? 'ANY'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _contentType,
                      isExpanded: true,
                      decoration: _decoration(label: 'Content-Type'),
                      items: [
                        for (final t in _contentTypes)
                          DropdownMenuItem(
                            value: t,
                            child: Text(
                              t ?? 'Auto-detect',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _contentType = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _filePathController,
                      style: const TextStyle(fontSize: 13),
                      decoration: _decoration(label: 'Local response file'),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Browse'),
                    style: OutlinedButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _statusCodeController,
                      style: const TextStyle(fontSize: 13),
                      decoration: _decoration(label: 'Status code'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Use regex',
                          style: TextStyle(fontSize: 13)),
                      value: _useRegex,
                      onChanged: (v) => setState(() => _useRegex = v),
                    ),
                  ),
                  Expanded(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Case-sensitive path',
                          style: TextStyle(fontSize: 13)),
                      value: _isCaseSensitive,
                      onChanged: (v) => setState(() => _isCaseSensitive = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Custom headers',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 4),
              for (var i = 0; i < _customHeaderControllers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _customHeaderControllers[i].key,
                          style: const TextStyle(fontSize: 12),
                          decoration: _decoration(hintText: 'Header name'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _customHeaderControllers[i].value,
                          style: const TextStyle(fontSize: 12),
                          decoration: _decoration(hintText: 'Value'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            size: 16),
                        onPressed: _customHeaderControllers.length == 1
                            ? null
                            : () => setState(() {
                                  _customHeaderControllers[i].key.dispose();
                                  _customHeaderControllers[i].value.dispose();
                                  _customHeaderControllers.removeAt(i);
                                }),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 24, minHeight: 24),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _customHeaderControllers
                      .add((key: TextEditingController(),
                          value: TextEditingController()))),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add header',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ),
              _field(
                label: 'Notes (optional)',
                controller: _notesController,
                hint: 'Description of the rule',
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
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 13),
        decoration: _decoration(label: label, hintText: hint),
      ),
    );
  }

  InputDecoration _decoration({String? label, String? hintText}) =>
      InputDecoration(
        labelText: label,
        hintText: hintText,
        labelStyle: const TextStyle(fontSize: 12),
        hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      );
}

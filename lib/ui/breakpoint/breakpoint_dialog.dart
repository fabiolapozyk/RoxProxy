import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/breakpoint_request.dart';
import '../../models/captured_exchange.dart';
import '../../providers/breakpoint_provider.dart';

/// Dialog mostrato automaticamente a ogni richiesta sospesa (RF7.1).
/// Permette di modificare metodo/URL/header/body e decidere Proceed/Cancel
/// (RF4/RF3.2), con countdown del timeout (RF7.2).
class BreakpointDialog extends ConsumerStatefulWidget {
  final BreakpointRequest request;

  const BreakpointDialog({super.key, required this.request});

  @override
  ConsumerState<BreakpointDialog> createState() => _BreakpointDialogState();
}

class _BreakpointDialogState extends ConsumerState<BreakpointDialog> {
  static const _methods = [
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
  ];

  late String _method;
  late TextEditingController _urlController;
  late TextEditingController _bodyController;
  final List<TextEditingController> _nameControllers = [];
  final List<TextEditingController> _valueControllers = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    final request = widget.request;
    _method = request.method;
    _urlController = TextEditingController(text: request.url);
    _bodyController = TextEditingController(text: request.body ?? '');
    for (final header in request.headers) {
      _nameControllers.add(TextEditingController(text: header.name));
      _valueControllers.add(TextEditingController(text: header.value));
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _bodyController.dispose();
    for (final c in _nameControllers) {
      c.dispose();
    }
    for (final c in _valueControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addHeader() {
    setState(() {
      _nameControllers.add(TextEditingController());
      _valueControllers.add(TextEditingController());
    });
  }

  void _removeHeader(int index) {
    setState(() {
      _nameControllers.removeAt(index).dispose();
      _valueControllers.removeAt(index).dispose();
    });
  }

  Future<void> _proceed() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    final headers = <HttpHeader>[];
    for (var i = 0; i < _nameControllers.length; i++) {
      final name = _nameControllers[i].text.trim();
      final value = _valueControllers[i].text.trim();
      if (name.isEmpty && value.isEmpty) continue;
      headers.add(HttpHeader(name, value));
    }

    // Il body viene inviato solo se l'originale esisteva oppure l'utente ha
    // digitato del testo: evita di azzerare accidentalmente body assenti.
    final bodyText = _bodyController.text;
    final hasBody = widget.request.body != null || bodyText.isNotEmpty;
    final body = hasBody ? bodyText : null;

    await ref
        .read(breakpointProvider.notifier)
        .proceed(
          method: _method,
          url: _urlController.text.trim(),
          headers: headers,
          body: body,
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cancel() async {
    if (_isSending) return;
    setState(() => _isSending = true);
    await ref.read(breakpointProvider.notifier).cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(breakpointProvider);

    return AlertDialog(
      title: Text(
        'Breakpoint — ${widget.request.method} ${widget.request.host}',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Countdown del timeout (RF7.2)
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value:
                          state.remainingSeconds /
                          BreakpointNotifier.timeoutSeconds,
                      minHeight: 4,
                      backgroundColor: Theme.of(context).dividerColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Auto-proceed in ${state.remainingSeconds}s',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 110,
                      maxWidth: 150,
                    ),
                    child: DropdownButtonFormField<String>(
                      initialValue: _method,
                      isExpanded: true,
                      items: _methods
                          .map(
                            (m) => DropdownMenuItem(value: m, child: Text(m)),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _method = value ?? _method),
                      decoration: const InputDecoration(
                        labelText: 'Method',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'URL',
                        isDense: true,
                      ),
                      textAlign: TextAlign.left,
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Headers',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _nameControllers.length; i++)
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _nameControllers[i],
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          isDense: true,
                        ),
                        textAlign: TextAlign.left,
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _valueControllers[i],
                        decoration: const InputDecoration(
                          labelText: 'Value',
                          isDense: true,
                        ),
                        textAlign: TextAlign.left,
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18),
                      onPressed: () => _removeHeader(i),
                    ),
                  ],
                ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Header'),
                onPressed: _addHeader,
              ),
              const SizedBox(height: 16),
              const Text('Body', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  child: TextField(
                    controller: _bodyController,
                    maxLines: null,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                      hintText: 'Body testuale (solo testo in v1)',
                    ),
                    textAlign: TextAlign.left,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
              if (state.hasQueued) ...[
                const SizedBox(height: 8),
                Text(
                  '${state.queue.length} richiesta(e) in coda',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : _cancel,
          child: const Text(
            'Cancel (400)',
            style: TextStyle(color: Color(0xFFFF3B30)),
          ),
        ),
        ElevatedButton(
          onPressed: _isSending ? null : _proceed,
          child: const Text('Proceed'),
        ),
      ],
    );
  }
}

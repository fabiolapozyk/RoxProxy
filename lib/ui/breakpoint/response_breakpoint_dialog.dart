import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/captured_exchange.dart';
import '../../models/response_breakpoint.dart';
import '../../providers/breakpoint_provider.dart';

/// Dialog per una risposta sospesa a un breakpoint: permette di modificare
/// status, header e body prima dell'inoltro al client, oppure Cancellare.
class ResponseBreakpointDialog extends ConsumerStatefulWidget {
  final ResponseBreakpoint response;

  const ResponseBreakpointDialog({super.key, required this.response});

  @override
  ConsumerState<ResponseBreakpointDialog> createState() =>
      _ResponseBreakpointDialogState();
}

class _ResponseBreakpointDialogState
    extends ConsumerState<ResponseBreakpointDialog> {
  late TextEditingController _statusController;
  late TextEditingController _bodyController;
  final List<TextEditingController> _nameControllers = [];
  final List<TextEditingController> _valueControllers = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    final response = widget.response;
    _statusController = TextEditingController(
      text: response.statusCode.toString(),
    );
    _bodyController = TextEditingController(text: response.body ?? '');
    for (final header in response.headers) {
      _nameControllers.add(TextEditingController(text: header.name));
      _valueControllers.add(TextEditingController(text: header.value));
    }
  }

  @override
  void dispose() {
    _statusController.dispose();
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

    final status = int.tryParse(_statusController.text.trim());
    // Status valido solo se diverso dall'originale e nel range HTTP.
    final modifiedStatus =
        (status != null &&
            status != widget.response.statusCode &&
            status >= 100 &&
            status <= 599)
        ? status
        : null;

    final headers = <HttpHeader>[];
    for (var i = 0; i < _nameControllers.length; i++) {
      final name = _nameControllers[i].text.trim();
      final value = _valueControllers[i].text.trim();
      if (name.isEmpty && value.isEmpty) continue;
      headers.add(HttpHeader(name, value));
    }

    final bodyText = _bodyController.text;
    final hasBody = widget.response.body != null || bodyText.isNotEmpty;
    final body = hasBody ? bodyText : null;

    await ref
        .read(breakpointProvider.notifier)
        .proceedResponse(status: modifiedStatus, headers: headers, body: body);
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
    final response = widget.response;

    // La risposta è stata risolta dal core (timeout o decisione altrove):
    // il dialog non può più operare e si chiude da solo.
    if (state.active?.id != response.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.input, size: 18, color: Color(0xFFFF3B30)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Response breakpoint — ${response.method} ${response.host}',
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      minWidth: 90,
                      maxWidth: 110,
                    ),
                    child: TextField(
                      controller: _statusController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      response.url,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
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
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(12),
                      hintText: widget.response.body == null
                          ? '(Body non presente o non testuale nella response)'
                          : 'Body testuale (solo testo in v1)',
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
            'Cancel',
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

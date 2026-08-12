import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/response_breakpoint.dart';
import '../../providers/breakpoint_provider.dart';

/// Dialog per una risposta sospesa a un breakpoint: sola ispezione
/// (status/header/body), con Proceed/Cancel e countdown del timeout.
class ResponseBreakpointDialog extends ConsumerStatefulWidget {
  final ResponseBreakpoint response;

  const ResponseBreakpointDialog({super.key, required this.response});

  @override
  ConsumerState<ResponseBreakpointDialog> createState() =>
      _ResponseBreakpointDialogState();
}

class _ResponseBreakpointDialogState
    extends ConsumerState<ResponseBreakpointDialog> {
  bool _isSending = false;

  Future<void> _proceed() async {
    if (_isSending) return;
    setState(() => _isSending = true);
    await ref.read(breakpointProvider.notifier).proceedResponse();
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

    final statusColor = response.statusCode >= 400
        ? const Color(0xFFFF3B30)
        : response.statusCode >= 300
        ? const Color(0xFFFF9500)
        : const Color(0xFF34C759);

    return AlertDialog(
      title: Text(
        'Response breakpoint — ${response.method} ${response.host}',
        style: const TextStyle(fontSize: 16),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${response.statusCode} ${response.statusMessage ?? ''}'
                          .trim(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
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
              if (response.headers.isEmpty)
                Text(
                  'No headers',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                )
              else
                for (final header in response.headers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${header.name}: ${header.value}',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              const SizedBox(height: 16),
              const Text('Body', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: Text(
                    response.body?.isEmpty ?? true
                        ? '(body vuoto o non testuale)'
                        : response.body!,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Menlo',
                      color: Colors.grey.shade800,
                    ),
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

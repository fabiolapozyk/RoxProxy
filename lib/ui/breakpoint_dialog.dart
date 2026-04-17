import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/captured_exchange.dart';
import '../models/breakpoint.dart';

class BreakpointDialog extends ConsumerStatefulWidget {
  final CapturedExchange exchange;
  final Breakpoint breakpoint;
  final bool isRequest;

  const BreakpointDialog({
    super.key,
    required this.exchange,
    required this.breakpoint,
    required this.isRequest,
  });

  @override
  ConsumerState<BreakpointDialog> createState() => _BreakpointDialogState();
}

class _BreakpointDialogState extends ConsumerState<BreakpointDialog> {
  late String _statusCode;
  late Map<String, String> _headers;
  late String _body;
  bool _showHeaders = true;
  bool _showBody = true;

  @override
  void initState() {
    super.initState();
    print('DEBUG: BreakpointDialog.initState called');
    print('DEBUG: Exchange URL: ${widget.exchange.url}');
    print('DEBUG: Is Request: ${widget.isRequest}');
    
    _statusCode = widget.exchange.statusCode?.toString() ?? '200';
    _headers = _extractHeaders();
    _body = widget.exchange.cachedResponseBody != null
        ? String.fromCharCodes(widget.exchange.cachedResponseBody!)
        : (widget.exchange.cachedRequestBody != null
            ? String.fromCharCodes(widget.exchange.cachedRequestBody!)
            : '');
    
    print('DEBUG: BreakpointDialog initialized successfully');
  }

  Map<String, dynamic> _getModifications() {
    return {
      'statusCode': _statusCode,
      'headers': _headers,
      'body': _body,
    };
  }

  Map<String, String> _extractHeaders() {
    final headers = <String, String>{};
    if (widget.isRequest) {
      for (final header in widget.exchange.requestHeaders) {
        headers[header.name] = header.value;
      }
    } else {
      if (widget.exchange.responseHeaders != null) {
        for (final header in widget.exchange.responseHeaders!) {
          headers[header.name] = header.value;
        }
      }
    }
    return headers;
  }

  @override
  Widget build(BuildContext context) {
    print('DEBUG: BreakpointDialog.build called');
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.isRequest ? Icons.call_made : Icons.call_received,
            color: widget.isRequest ? Colors.blue : Colors.green,
          ),
          const SizedBox(width: 8),
          Text(
            widget.isRequest ? 'Request Breakpoint' : 'Response Breakpoint',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.exchange.url,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            Text(
              widget.exchange.method,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const Divider(height: 16),
            Row(
              children: [
                FilterChip(
                  label: const Text('Headers', style: TextStyle(fontSize: 11)),
                  selected: _showHeaders,
                  onSelected: (selected) => setState(() => _showHeaders = selected),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                FilterChip(
                  label: const Text('Body', style: TextStyle(fontSize: 11)),
                  selected: _showBody,
                  onSelected: (selected) => setState(() => _showBody = selected),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_showHeaders) ...[
              const Text('Headers:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.all(8),
                child: _buildHeadersEditor(),
              ),
              const SizedBox(height: 8),
            ],
            if (_showBody) ...[
              const Text('Body:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.all(8),
                child: TextField(
                  maxLines: 10,
                  minLines: 5,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  controller: TextEditingController(text: _body),
                  onChanged: (value) => _body = value,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (widget.isRequest)
              Row(
                children: [
                  const Text('Status Code:', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                      controller: TextEditingController(text: _statusCode),
                      onChanged: (value) => _statusCode = value,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Cancel', style: TextStyle(fontSize: 13)),
          onPressed: () => Navigator.of(context).pop({
            'shouldContinue': false,
          }),
        ),
        ElevatedButton(
          child: const Text('Continue', style: TextStyle(fontSize: 13)),
          onPressed: () => Navigator.of(context).pop({
            'shouldContinue': true,
            'modifications': _getModifications(),
          }),
        ),
      ],
    );
  }

  Widget _buildHeadersEditor() {
    final headerEntries = _headers.entries.toList();
    return Column(
      children: headerEntries.map((entry) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                ),
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                controller: TextEditingController(text: entry.key),
                onChanged: (value) {
                  final oldValue = _headers.remove(entry.key);
                  _headers[value] = oldValue ?? '';
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                ),
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                controller: TextEditingController(text: entry.value),
                onChanged: (value) => _headers[entry.key] = value,
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }
}
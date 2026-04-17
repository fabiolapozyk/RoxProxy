import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/breakpoint_request.dart';
import '../models/breakpoint_response.dart';
import '../services/breakpoint_service.dart';

class BreakpointDialog extends ConsumerStatefulWidget {
  final BreakpointRequest request;
  final BreakpointService breakpointService;
  
  const BreakpointDialog({
    super.key,
    required this.request,
    required this.breakpointService,
  });
  
  @override
  ConsumerState<BreakpointDialog> createState() => _BreakpointDialogState();
}

class _BreakpointDialogState extends ConsumerState<BreakpointDialog> {
  late TextEditingController _methodController;
  late TextEditingController _urlController;
  late TextEditingController _bodyController;
  late Map<String, TextEditingController> _headerControllers;
  String? _newHeaderKey;
  String? _newHeaderValue;
  
  @override
  void initState() {
    super.initState();
    _methodController = TextEditingController(text: widget.request.method);
    _urlController = TextEditingController(text: widget.request.url);
    _bodyController = TextEditingController(text: widget.request.body ?? '');
    
    _headerControllers = {};
    widget.request.headers.forEach((key, value) {
      _headerControllers[key] = TextEditingController(text: value);
    });
  }
  
  @override
  void dispose() {
    _methodController.dispose();
    _urlController.dispose();
    _bodyController.dispose();
    _headerControllers.values.forEach((controller) => controller.dispose());
    super.dispose();
  }
  
  void _addHeader() {
    if (_newHeaderKey != null && _newHeaderKey!.isNotEmpty) {
      setState(() {
        _headerControllers[_newHeaderKey!] = TextEditingController(text: _newHeaderValue ?? '');
        _newHeaderKey = null;
        _newHeaderValue = null;
      });
    }
  }
  
  void _removeHeader(String key) {
    setState(() {
      _headerControllers[key]?.dispose();
      _headerControllers.remove(key);
    });
  }
  
  Future<void> _sendProceedResponse() async {
    final modifiedHeaders = <String, String>{};
    _headerControllers.forEach((key, controller) {
      modifiedHeaders[key] = controller.text;
    });
    
    final response = BreakpointResponse(
      breakpointId: widget.request.id,
      action: 'proceed',
      modifiedMethod: _methodController.text,
      modifiedUrl: _urlController.text,
      modifiedHeaders: modifiedHeaders,
      modifiedBody: _bodyController.text.isEmpty ? null : _bodyController.text,
      timestamp: DateTime.now(),
    );
    
    try {
      await widget.breakpointService.sendBreakpointResponse(response);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send response: $e')),
        );
      }
    }
  }
  
  Future<void> _sendCancelResponse() async {
    final response = BreakpointResponse(
      breakpointId: widget.request.id,
      action: 'cancel',
      timestamp: DateTime.now(),
    );
    
    try {
      await widget.breakpointService.sendBreakpointResponse(response);
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send cancel: $e')),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Breakpoint: ${widget.request.isRequest ? 'Request' : 'Response'}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMethodField(),
            const SizedBox(height: 12),
            _buildUrlField(),
            const SizedBox(height: 12),
            _buildHeadersSection(),
            const SizedBox(height: 12),
            _buildBodyField(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sendCancelResponse,
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _sendProceedResponse,
          child: const Text('Proceed'),
        ),
      ],
    );
  }
  
  Widget _buildMethodField() {
    return TextField(
      controller: _methodController,
      decoration: const InputDecoration(
        labelText: 'Method',
        border: OutlineInputBorder(),
      ),
    );
  }
  
  Widget _buildUrlField() {
    return TextField(
      controller: _urlController,
      decoration: const InputDecoration(
        labelText: 'URL',
        border: OutlineInputBorder(),
      ),
    );
  }
  
  Widget _buildHeadersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Headers', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._headerControllers.entries.map((entry) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(entry.key, style: const TextStyle(fontFamily: 'monospace')),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: entry.value,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20),
                onPressed: () => _removeHeader(entry.key),
              ),
            ],
          ),
        )).toList(),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Header name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => _newHeaderKey = value,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Header value',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => _newHeaderValue = value,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              onPressed: _addHeader,
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildBodyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Body', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: TextField(
            controller: _bodyController,
            maxLines: null,
            expands: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Request/Response body',
            ),
          ),
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'dart:typed_data';

import '../models/captured_exchange.dart';
import '../providers/proxy_channel_provider.dart';

class BreakpointDialog extends ConsumerStatefulWidget {
  final CapturedExchange exchange;
  final bool isRequest;

  const BreakpointDialog({
    super.key,
    required this.exchange,
    required this.isRequest,
  });

  @override
  ConsumerState<BreakpointDialog> createState() => _BreakpointDialogState();
}

class _BreakpointDialogState extends ConsumerState<BreakpointDialog> {
  late String _method;
  late String _url;
  late List<HttpHeader> _headers;
  Uint8List? _body;
  String? _bodyText;
  bool _isBinary = false;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      setState(() {
        _method = widget.exchange.method;
        _url = widget.exchange.url;
        _headers = List.from(widget.isRequest
            ? widget.exchange.requestHeaders
            : widget.exchange.responseHeaders ?? []);
        _isLoading = true;
      });

      // Fetch body if available
      final bodyRef = widget.isRequest
          ? widget.exchange.requestBodyRef
          : widget.exchange.responseBodyRef;

      if (bodyRef != null) {
        final bodyData = await ref
            .read(proxyChannelProvider)
            .fetchBody(bodyRef);
        
        if (bodyData != null) {
          setState(() {
            _body = bodyData;
            _bodyText = _tryDecodeAsText(bodyData);
            _isBinary = _bodyText == null;
          });
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load data: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String? _tryDecodeAsText(Uint8List data) {
    try {
      // Check if content appears to be text
      final contentType = _headers.firstWhere(
        (h) => h.name.toLowerCase() == 'content-type',
        orElse: () => const HttpHeader('content-type', 'application/octet-stream'),
      ).value;

      if (contentType.contains('text/') ||
          contentType.contains('json') ||
          contentType.contains('xml') ||
          contentType.contains('javascript')) {
        return String.fromCharCodes(data);
      }
      
      // Try to decode as UTF-8
      return String.fromCharCodes(data);
    } catch (e) {
      return null;
    }
  }

  void _addHeader() {
    setState(() {
      _headers.add(const HttpHeader('', ''));
    });
  }

  void _removeHeader(int index) {
    setState(() {
      _headers.removeAt(index);
    });
  }

  void _updateHeader(int index, String name, String value) {
    setState(() {
      _headers[index] = HttpHeader(name, value);
    });
  }

  Future<void> _resumeExchange() async {
    try {
      final modifications = {
        'method': _method,
        'url': _url,
        'headers': _headers.map((h) => {'name': h.name, 'value': h.value}).toList(),
        if (_body != null) 'body': _body!,
      };

      // Try to call native layer - this will work once native implementation is ready
      try {
        await ref.read(proxyChannelProvider).resumeExchange(
          widget.exchange.id,
          modifications: modifications,
        );
        
        await ref.read(proxyChannelProvider).logBreakpointEvent(
          exchangeId: widget.exchange.id,
          action: 'resume',
          modifications: 'Modified: ${_headers.length} headers, ${_body != null ? '${_body!.length} bytes body' : 'no body'}',
        );
      } catch (e) {
        // Native layer not implemented yet - this is expected during development
        debugPrint('Native resume not available: ${e.toString()}');
        debugPrint('Modifications would be: ${jsonEncode(modifications)}');
      }

      if (!mounted) return;
      Navigator.of(context).pop('resumed');
    } catch (e) {
      setState(() {
        _error = 'Failed to resume: ${e.toString()}';
      });
    }
  }

  Future<void> _cancelExchange() async {
    try {
      // Try to call native layer - this will work once native implementation is ready
      try {
        await ref.read(proxyChannelProvider).cancelExchange(widget.exchange.id);
        
        await ref.read(proxyChannelProvider).logBreakpointEvent(
          exchangeId: widget.exchange.id,
          action: 'cancel',
        );
      } catch (e) {
        // Native layer not implemented yet - this is expected during development
        debugPrint('Native cancel not available: ${e.toString()}');
        debugPrint('Exchange would be cancelled: ${widget.exchange.id}');
      }

      if (!mounted) return;
      Navigator.of(context).pop('cancelled');
    } catch (e) {
      setState(() {
        _error = 'Failed to cancel: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isRequest ? 'Intercepted Request' : 'Intercepted Response',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            '⚠️ Native implementation pending - changes won\'t be applied',
            style: TextStyle(fontSize: 11, color: Colors.orange, fontStyle: FontStyle.italic),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 500,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                : Column(
                    children: [
                      Expanded(
                        child: DefaultTabController(
                          length: 3,
                          child: Column(
                            children: [
                              TabBar(
                                labelStyle: const TextStyle(fontSize: 12),
                                tabs: const [
                                  Tab(text: 'General'),
                                  Tab(text: 'Headers'),
                                  Tab(text: 'Body'),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _buildGeneralTab(),
                                    _buildHeadersTab(),
                                    _buildBodyTab(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('ignored'),
          child: const Text('Ignore'),
        ),
        TextButton(
          onPressed: _cancelExchange,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _resumeExchange,
          child: const Text('Resume'),
        ),
      ],
    );
  }

  Widget _buildGeneralTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 100,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Method',
                    isDense: true,
                  ),
                  controller: TextEditingController(text: _method),
                  onChanged: (value) => _method = value,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    isDense: true,
                  ),
                  controller: TextEditingController(text: _url),
                  onChanged: (value) => _url = value,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Exchange ID: ${widget.exchange.id}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Text(
            'Scheme: ${widget.exchange.scheme}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Text(
            'Host: ${widget.exchange.host}:${widget.exchange.port}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text('Headers', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: _addHeader,
                tooltip: 'Add Header',
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _headers.length,
            itemBuilder: (context, index) {
              final header = _headers[index];
              return ListTile(
                dense: true,
                title: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          isDense: true,
                        ),
                        controller: TextEditingController(text: header.name),
                        onChanged: (value) => _updateHeader(index, value, header.value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Value',
                          isDense: true,
                        ),
                        controller: TextEditingController(text: header.value),
                        onChanged: (value) => _updateHeader(index, header.name, value),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => _removeHeader(index),
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBodyTab() {
    if (_body == null) {
      return const Center(
        child: Text('No body available', style: TextStyle(color: Colors.grey)),
      );
    }

    if (_isBinary) {
      return _buildBinaryBody();
    } else {
      return _buildTextBody();
    }
  }

  Widget _buildTextBody() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            maxLines: null,
            expands: true,
            decoration: const InputDecoration(
              labelText: 'Body (Text)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            controller: TextEditingController(text: _bodyText),
            onChanged: (value) {
              _bodyText = value;
              _body = Uint8List.fromList(value.codeUnits);
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Size: ${_body?.length ?? 0} bytes',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildBinaryBody() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Binary Data Preview',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                _body != null
                    ? _body!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')
                    : 'No data',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Size: ${_body?.length ?? 0} bytes',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              // TODO: Implement binary editor
            },
            child: const Text('Edit as Binary'),
          ),
        ],
      ),
    );
  }
}

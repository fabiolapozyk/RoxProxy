import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/replay_request.dart';
import '../models/captured_exchange.dart';

class QueryParam {
  final String name;
  final String value;

  QueryParam(this.name, this.value);
}

class ReplayDialog extends ConsumerStatefulWidget {
  final ReplayRequest initialRequest;

  const ReplayDialog({super.key, required this.initialRequest});

  @override
  ConsumerState<ReplayDialog> createState() => _ReplayDialogState();
}

class _ReplayDialogState extends ConsumerState<ReplayDialog> {
  late ReplayRequest _request;
  bool _isSending = false;
  String? _error;
  late TextEditingController _urlController;
  late TextEditingController _bodyController;
  final Map<int, TextEditingController> _nameControllers = {};
  final Map<int, TextEditingController> _valueControllers = {};
  final Map<int, TextEditingController> _queryParamNameControllers = {};
  final Map<int, TextEditingController> _queryParamValueControllers = {};
  final List<QueryParam> _queryParams = [];

  @override
  void initState() {
    super.initState();
    _request = widget.initialRequest;

    // Strip query parameters from URL for display
    final uri = Uri.parse(_request.url);
    final baseUrl = uri.origin + uri.path;
    _urlController = TextEditingController(text: baseUrl);
    _urlController.addListener(() {
      _updateUrl(_urlController.text);
    });

    _bodyController = TextEditingController(text: _request.body ?? '');
    _bodyController.addListener(() {
      _updateBody(_bodyController.text);
    });

    // Parse existing query parameters from URL
    _parseQueryParameters();

    // Initialize controllers for existing headers
    for (var i = 0; i < _request.headers.length; i++) {
      _nameControllers[i] = TextEditingController(
        text: _request.headers[i].name,
      );
      _valueControllers[i] = TextEditingController(
        text: _request.headers[i].value,
      );

      // Add listeners to update headers when text changes
      final index = i;
      _nameControllers[i]!.addListener(() {
        _updateHeader(
          index,
          _nameControllers[index]!.text,
          _request.headers[index].value,
        );
      });
      _valueControllers[i]!.addListener(() {
        _updateHeader(
          index,
          _request.headers[index].name,
          _valueControllers[index]!.text,
        );
      });
    }
  }

  @override
  void dispose() {
    // Remove listeners and clean up controllers
    _urlController.removeListener(() {});
    _urlController.dispose();
    _bodyController.removeListener(() {});
    _bodyController.dispose();
    for (var controller in _nameControllers.values) {
      controller.removeListener(() {});
      controller.dispose();
    }
    for (var controller in _valueControllers.values) {
      controller.removeListener(() {});
      controller.dispose();
    }
    for (var controller in _queryParamNameControllers.values) {
      controller.removeListener(() {});
      controller.dispose();
    }
    for (var controller in _queryParamValueControllers.values) {
      controller.removeListener(() {});
      controller.dispose();
    }
    super.dispose();
  }

  void _updateUrl(String value) {
    // Handle manual URL modifications that might include query parameters
    final uri = Uri.parse(value);
    final baseUrl = uri.origin + uri.path;

    // If URL contains query parameters, parse and add them to query params list
    if (uri.query.isNotEmpty) {
      final newParams = uri.queryParameters;

      // Add new parameters that don't already exist
      newParams.forEach((name, value) {
        if (!_queryParams.any((param) => param.name == name)) {
          setState(() {
            _queryParams.add(QueryParam(name, value));
            final index = _queryParams.length - 1;
            _queryParamNameControllers[index] = TextEditingController(
              text: name,
            );
            _queryParamValueControllers[index] = TextEditingController(
              text: value,
            );

            // Add listeners for new parameters
            final paramIndex = index;
            _queryParamNameControllers[index]!.addListener(() {
              _updateQueryParam(
                paramIndex,
                _queryParamNameControllers[paramIndex]!.text,
                _queryParams[paramIndex].value,
              );
            });
            _queryParamValueControllers[index]!.addListener(() {
              _updateQueryParam(
                paramIndex,
                _queryParams[paramIndex].name,
                _queryParamValueControllers[paramIndex]!.text,
              );
            });
          });
        }
      });
    }

    // Update the base URL without query parameters
    setState(() => _request.url = baseUrl);
  }

  void _updateMethod(String? value) {
    if (value != null) {
      setState(() {
        _request.method = value;
        // Clear body for GET/HEAD methods
        if (value == 'GET' || value == 'HEAD') {
          _request.body = null;
          _bodyController.text = '';
        }
      });
    }
  }

  void _parseQueryParameters() {
    try {
      debugPrint('_parseQueryParameters called');
      final uri = Uri.parse(_request.url);
      uri.queryParameters.forEach((name, value) {
        debugPrint('Found query param: $name=$value');
        _queryParams.add(QueryParam(name, value));
        final index = _queryParams.length - 1;
        _queryParamNameControllers[index] = TextEditingController(text: name);
        _queryParamValueControllers[index] = TextEditingController(text: value);

        // Add listeners for existing parameters
        final paramIndex = index; // Capture index for closure
        _queryParamNameControllers[index]!.addListener(() {
          debugPrint(
            'Existing name controller $paramIndex changed: ${_queryParamNameControllers[paramIndex]!.text}',
          );
          _updateQueryParam(
            paramIndex,
            _queryParamNameControllers[paramIndex]!.text,
            _queryParams[paramIndex].value,
          );
        });
        _queryParamValueControllers[index]!.addListener(() {
          debugPrint(
            'Existing value controller $paramIndex changed: ${_queryParamValueControllers[paramIndex]!.text}',
          );
          _updateQueryParam(
            paramIndex,
            _queryParams[paramIndex].name,
            _queryParamValueControllers[paramIndex]!.text,
          );
        });
      });
    } catch (e) {
      debugPrint('Error parsing query parameters: ${e.toString()}');
      // Invalid URL, ignore
    }
  }

  void _updateQueryParam(int index, String name, String value) {
    debugPrint('Updating query param $index: $name=$value');
    if (index < _queryParams.length) {
      _queryParams[index] = QueryParam(name, value);
      // Force rebuild to update the "Current URL" display
      setState(() {});
    }
  }

  void _addQueryParam() {
    setState(() {
      _queryParams.add(QueryParam('', ''));
      final index = _queryParams.length - 1;
      _queryParamNameControllers[index] = TextEditingController();
      _queryParamValueControllers[index] = TextEditingController();

      // Add listeners
      _queryParamNameControllers[index]!.addListener(() {
        debugPrint(
          'Name controller $index changed: ${_queryParamNameControllers[index]!.text}',
        );
        _updateQueryParam(
          index,
          _queryParamNameControllers[index]!.text,
          _queryParams[index].value,
        );
      });
      _queryParamValueControllers[index]!.addListener(() {
        debugPrint(
          'Value controller $index changed: ${_queryParamValueControllers[index]!.text}',
        );
        _updateQueryParam(
          index,
          _queryParams[index].name,
          _queryParamValueControllers[index]!.text,
        );
      });
    });
  }

  void _removeQueryParam(int index) {
    setState(() {
      _queryParams.removeAt(index);
      _queryParamNameControllers.remove(index)?.dispose();
      _queryParamValueControllers.remove(index)?.dispose();
      // Reindex controllers
      for (var i = index; i < _queryParams.length; i++) {
        _queryParamNameControllers[i] = _queryParamNameControllers.remove(
          i + 1,
        )!;
        _queryParamValueControllers[i] = _queryParamValueControllers.remove(
          i + 1,
        )!;
      }
    });
  }

  String _buildUrlWithQueryParams() {
    try {
      // Parse the base URL (without query parameters)
      final baseUri = Uri.parse(_request.url);

      // Build query parameters map from the dedicated fields
      final queryParamsMap = <String, String>{};
      for (var param in _queryParams) {
        if (param.name.isNotEmpty) {
          queryParamsMap[param.name] = param.value;
        }
      }

      // Combine base URL with query parameters
      final newUri = baseUri.replace(queryParameters: queryParamsMap);
      return newUri.toString();
    } catch (e) {
      return _request.url;
    }
  }

  void _updateHeader(int index, String name, String value) {
    _request.headers[index] = HttpHeader(name, value);
  }

  void _addHeader() {
    setState(() {
      _request.headers.add(HttpHeader('', ''));
      final index = _request.headers.length - 1;
      _nameControllers[index] = TextEditingController();
      _valueControllers[index] = TextEditingController();
      // Add listeners to update headers when text changes
      _nameControllers[index]!.addListener(() {
        _updateHeader(
          index,
          _nameControllers[index]!.text,
          _request.headers[index].value,
        );
      });
      _valueControllers[index]!.addListener(() {
        _updateHeader(
          index,
          _request.headers[index].name,
          _valueControllers[index]!.text,
        );
      });
    });
  }

  void _removeHeader(int index) {
    setState(() {
      _request.headers.removeAt(index);
      _nameControllers.remove(index)?.dispose();
      _valueControllers.remove(index)?.dispose();
      // Reindex controllers
      for (var i = index; i < _request.headers.length; i++) {
        _nameControllers[i] = _nameControllers.remove(i + 1)!;
        _valueControllers[i] = _valueControllers.remove(i + 1)!;
      }
    });
  }

  void _updateBody(String value) {
    setState(() => _request.body = value);
  }

  Future<void> _sendRequest() async {
    // Debug: Log initial state
    debugPrint('=== SEND REQUEST DEBUG ===');
    debugPrint('Method: ${_request.method}');
    debugPrint('Original URL: ${_request.url}');

    // Update headers from controllers before validation
    for (var i = 0; i < _request.headers.length; i++) {
      final name = _nameControllers[i]?.text.trim() ?? '';
      final value = _valueControllers[i]?.text.trim() ?? '';
      _request.headers[i] = HttpHeader(name, value);
    }

    // Validate headers
    for (var header in _request.headers) {
      if (header.name.isEmpty || header.value.isEmpty) {
        setState(() {
          _error = 'Header name and value cannot be empty';
        });
        return;
      }
    }

    // Build final URL with query parameters for GET/HEAD methods
    if (_request.method == 'GET' || _request.method == 'HEAD') {
      debugPrint('Preparing GET/HEAD request');
      // Remove Content-Length header for GET/HEAD requests as they should not have it
      _request.headers.removeWhere(
        (header) => header.name.toLowerCase() == 'content-length',
      );

      final builtUrl = _buildUrlWithQueryParams();
      debugPrint(
        'Query params: ${_queryParams.map((p) => '${p.name}=${p.value}').join(', ')}',
      );
      debugPrint('Built URL: $builtUrl');
      _request.url = builtUrl;
    } else {
      debugPrint('Body: ${_request.body ?? 'null'}');
    }

    // Debug: Log all query param controllers
    debugPrint('Query param controllers state:');
    _queryParamNameControllers.forEach((index, controller) {
      debugPrint('  Param $index name: ${controller.text}');
    });
    _queryParamValueControllers.forEach((index, controller) {
      debugPrint('  Param $index value: ${controller.text}');
    });

    // Debug: Log final headers
    debugPrint('Final headers after cleanup:');
    for (var header in _request.headers) {
      debugPrint('  ${header.name}: ${header.value}');
    }

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      // TODO: Implement actual sending logic via ProxyService
      await Future.delayed(const Duration(seconds: 1));
      debugPrint('Request sent successfully');
      if (mounted) {
        Navigator.of(context).pop(_request);
      }
    } catch (e) {
      debugPrint('Request failed: ${e.toString()}');
      if (mounted) {
        setState(() {
          _isSending = false;
          _error = 'Failed to send request: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Replay Request'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                  ),
                ),
              if (_isSending)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    height: 20,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 100,
                      maxWidth: 120,
                    ),
                    child: DropdownButtonFormField<String>(
                      initialValue: _request.method,
                      items:
                          const [
                                'GET',
                                'POST',
                                'PUT',
                                'PATCH',
                                'DELETE',
                                'HEAD',
                                'OPTIONS',
                              ]
                              .map(
                                (method) => DropdownMenuItem(
                                  value: method,
                                  child: Text(method),
                                ),
                              )
                              .toList(),
                      onChanged: _updateMethod,
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
              ..._request.headers.asMap().entries.map((entry) {
                final index = entry.key;
                final header = entry.value;
                return Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _nameControllers[index],
                        onChanged: (value) =>
                            _updateHeader(index, value, header.value),
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          isDense: true,
                        ),
                        textAlign: TextAlign.left,
                        textDirection: TextDirection.ltr,
                        cursorColor: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _valueControllers[index],
                        onChanged: (value) =>
                            _updateHeader(index, header.name, value),
                        decoration: const InputDecoration(
                          labelText: 'Value',
                          isDense: true,
                        ),
                        textAlign: TextAlign.left,
                        textDirection: TextDirection.ltr,
                        cursorColor: Colors.blue,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18),
                      onPressed: () => _removeHeader(index),
                    ),
                  ],
                );
              }),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Header'),
                onPressed: _addHeader,
              ),
              const SizedBox(height: 16),

              // Query Parameters section for GET/HEAD methods
              if (_request.method == 'GET' || _request.method == 'HEAD') ...[
                const Text(
                  'Query Parameters',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ..._queryParams.asMap().entries.map((entry) {
                  final index = entry.key;
                  return Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _queryParamNameControllers[index],
                          onChanged: (name) => _updateQueryParam(
                            index,
                            name,
                            _queryParams[index].value,
                          ),
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
                          controller: _queryParamValueControllers[index],
                          onChanged: (value) => _updateQueryParam(
                            index,
                            _queryParams[index].name,
                            value,
                          ),
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
                        onPressed: () => _removeQueryParam(index),
                      ),
                    ],
                  );
                }),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Parameter'),
                  onPressed: _addQueryParam,
                ),
                const SizedBox(height: 8),
                Text(
                  'Current URL: ${_buildUrlWithQueryParams()}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],

              // Body section for other methods
              if (_request.method != 'GET' && _request.method != 'HEAD') ...[
                const SizedBox(height: 16),
                const Text(
                  'Body',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 200,
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
                        labelText: 'Body',
                      ),
                      textAlign: TextAlign.left,
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSending ? null : _sendRequest,
          child: _isSending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send'),
        ),
      ],
    );
  }
}

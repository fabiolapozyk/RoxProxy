import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/captured_exchange.dart';
import '../../providers/proxy_channel_provider.dart';
import '../../utils/body_renderer.dart';

enum BodySide { request, response }

const int _kInlineRenderBytesLimit = 32 * 1024;

RenderMode _renderBodyInBackground((Uint8List, String?) args) =>
    BodyRenderer.render(data: args.$1, contentType: args.$2);

class BodyTab extends ConsumerStatefulWidget {
  final CapturedExchange exchange;
  final BodySide side;

  const BodyTab.request({super.key, required this.exchange})
    : side = BodySide.request;

  const BodyTab.response({super.key, required this.exchange})
    : side = BodySide.response;

  @override
  ConsumerState<BodyTab> createState() => _BodyTabState();
}

class _BodyTabState extends ConsumerState<BodyTab> {
  bool _loading = false;
  String? _error;
  String _searchQuery = '';
  bool _showSearchBar = false;
  RenderMode? _mode;
  bool _rendering = false;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<_BodySearchBarState> _searchBarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchIfNeeded();
    _setupKeyboardShortcuts();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupKeyboardShortcuts() {
    // This will be handled by the RawKeyboardListener in the build method
  }

  void _toggleSearch() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (!_showSearchBar) {
        // Reset search state when closing search bar
        _searchQuery = '';
      }
    });

    // Handle focus after the state change
    if (_showSearchBar) {
      // Schedule focus for after the next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusSearchField();
      });
    }
  }

  void _focusSearchField() {
    // Focus the search field using the global key
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchBarKey.currentState?.focus();
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final isMetaPressed =
          HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;
      if (isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyF) {
        _toggleSearch();
        return KeyEventResult.handled;
      } else if (_showSearchBar &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _toggleSearch();
        return KeyEventResult.handled;
      }
      // Removed Enter key handling to disable automatic scrolling
    }
    return KeyEventResult.ignored;
  }

  @override
  void didUpdateWidget(BodyTab old) {
    super.didUpdateWidget(old);
    final exchangeChanged = old.exchange.id != widget.exchange.id;
    final oldBytes = widget.side == BodySide.request
        ? old.exchange.cachedRequestBody
        : old.exchange.cachedResponseBody;
    final bytesChanged = !identical(oldBytes, _cachedBytes);

    if (exchangeChanged) {
      setState(() {
        _error = null;
        // Reset search state when exchange changes
        _showSearchBar = false;
        _searchQuery = '';
        _mode = null;
        _rendering = false;
      });
    } else if (bytesChanged) {
      setState(() {
        _mode = null;
        _rendering = false;
      });
    } else {
      return;
    }
    _fetchIfNeeded();
  }

  String? get _ref => widget.side == BodySide.request
      ? widget.exchange.requestBodyRef
      : widget.exchange.responseBodyRef;

  Uint8List? get _cachedBytes => widget.side == BodySide.request
      ? widget.exchange.cachedRequestBody
      : widget.exchange.cachedResponseBody;

  void _cacheBytes(Uint8List data) {
    if (widget.side == BodySide.request) {
      widget.exchange.setCachedRequestBody(data);
    } else {
      widget.exchange.setCachedResponseBody(data);
    }
  }

  String? get _contentType {
    final headers = widget.side == BodySide.request
        ? widget.exchange.requestHeaders
        : widget.exchange.responseHeaders;
    try {
      final contentTypeHeader = headers?.firstWhere(
        (h) => h.name.toLowerCase() == 'content-type',
      );
      return contentTypeHeader?.value.split(';').first.trim();
    } catch (_) {
      return null;
    }
  }

  String? get _contentEncoding {
    final headers = widget.side == BodySide.response
        ? widget.exchange.responseHeaders
        : null;
    try {
      final encodingHeader = headers?.firstWhere(
        (h) => h.name.toLowerCase() == 'content-encoding',
      );
      return encodingHeader?.value;
    } catch (_) {
      return null;
    }
  }

  bool get _isTextualBody => _mode is RenderText || _mode is RenderJson;

  static String _extensionForContentType(String? contentType) {
    final ct = contentType?.toLowerCase() ?? '';
    if (ct.contains('json') || ct.contains('javascript')) return 'json';
    if (ct.contains('html')) return 'html';
    if (ct.contains('xml')) return 'xml';
    return 'txt';
  }

  /// Writes the (already decompressed) body to a temp file and opens it in an
  /// external editor: VS Code if installed, otherwise the system default.
  Future<void> _openInEditor() async {
    final bytes = _cachedBytes;
    if (bytes == null) return;
    try {
      final ext = _extensionForContentType(_contentType);
      final file = File(
        '${Directory.systemTemp.path}/roxproxy_${widget.exchange.id}_'
        '${widget.side.name}.$ext',
      );
      await file.writeAsBytes(bytes, flush: true);
      final vscode = File('/Applications/Visual Studio Code.app');
      final args = vscode.existsSync()
          ? ['-a', 'Visual Studio Code', file.path]
          : [file.path];
      await Process.run('open', args);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open in editor: ${e.toString()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _fetchIfNeeded() async {
    if (_cachedBytes == null && _ref != null) {
      setState(() {
        _loading = true;
        _error = null;
      });

      try {
        final channel = ref.read(proxyChannelProvider);
        Uint8List? bytes = await channel.fetchBody(_ref!);
        if (bytes == null) {
          setState(() => _loading = false);
        } else {
          // Decompress if needed
          final encoding = _contentEncoding;
          if (encoding != null &&
              (encoding.contains('gzip') ||
                  encoding.contains('deflate') ||
                  encoding.contains('br'))) {
            final decompressed = await channel.decompressBody(bytes, encoding);
            if (decompressed != null) {
              bytes = decompressed;
            } else {
              // Se la decompressione fallisce, mostra un messaggio di errore
              if (encoding.contains('br')) {
                setState(() {
                  _loading = false;
                  _error =
                      'Brotli compression is not supported. Response cannot be displayed.';
                });
                return;
              }
            }
          }
          _cacheBytes(bytes);
          if (mounted) setState(() => _loading = false);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = e.toString();
          });
        }
      }
    }
    _startRender();
  }

  Future<void> _startRender() async {
    final bytes = _cachedBytes;
    if (bytes == null || _mode != null || _rendering) return;
    setState(() => _rendering = true);
    try {
      final contentType = _contentType;
      final RenderMode mode;
      if (bytes.length <= _kInlineRenderBytesLimit) {
        mode = BodyRenderer.render(data: bytes, contentType: contentType);
      } else {
        mode = await compute(_renderBodyInBackground, (bytes, contentType));
      }
      if (!mounted) return;
      if (identical(bytes, _cachedBytes)) {
        setState(() {
          _mode = mode;
          _rendering = false;
        });
      } else {
        setState(() => _rendering = false);
        _startRender();
      }
    } catch (_) {
      if (mounted) setState(() => _rendering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ref == null) {
      return const Center(
        child: Text('No body', style: TextStyle(color: Colors.grey)),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    final bytes = _cachedBytes;
    if (bytes == null) {
      return const Center(
        child: Text('No body', style: TextStyle(color: Colors.grey)),
      );
    }
    if (_mode == null) {
      if (!_rendering) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _startRender());
      }
      return const Center(child: CircularProgressIndicator());
    }
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          if (_isTextualBody || _showSearchBar)
            Row(
              children: [
                if (_isTextualBody)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    tooltip: 'Open in editor',
                    onPressed: _openInEditor,
                  ),
                if (_showSearchBar)
                  Expanded(
                    child: BodySearchBar(
                      key: _searchBarKey,
                      text: _searchQuery,
                      onChanged: (query) {
                        setState(() => _searchQuery = query);
                      },
                      onClose: _toggleSearch,
                    ),
                  ),
              ],
            ),
          Expanded(
            child: BodyContent(
              mode: _mode!,
              searchQuery: _showSearchBar ? _searchQuery : '',
              scrollController: _scrollController,
            ),
          ),
        ],
      ),
    );
  }
}

class BodyContent extends StatelessWidget {
  final RenderMode mode;
  final String searchQuery;
  final ScrollController? scrollController;

  const BodyContent({
    super.key,
    required this.mode,
    this.searchQuery = '',
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      RenderEmpty() => const Center(
        child: Text('Empty body', style: TextStyle(color: Colors.grey)),
      ),
      RenderImage(:final bytes) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Image.memory(bytes),
        ),
      ),
      RenderJson(:final lines) => _JsonLineList(
        lines,
        searchQuery: searchQuery,
        scrollController: scrollController,
      ),
      RenderText(:final text) => _MonospaceText(
        text,
        searchQuery: searchQuery,
        scrollController: scrollController,
      ),
      RenderHex(:final text) => _MonospaceText(
        text,
        isHex: true,
        searchQuery: searchQuery,
        scrollController: scrollController,
      ),
    };
  }
}

class BodySearchBar extends StatefulWidget {
  final String text;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const BodySearchBar({
    super.key,
    required this.text,
    required this.onChanged,
    required this.onClose,
  });

  @override
  State<BodySearchBar> createState() => _BodySearchBarState();
}

class _BodySearchBarState extends State<BodySearchBar> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(BodySearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.text = widget.text;
      _controller.selection = TextSelection.collapsed(
        offset: widget.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void focus() {
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          hintText: 'Search in body…',
          hintStyle: const TextStyle(fontSize: 13),
          prefixIcon: const Icon(Icons.search, size: 16),
          suffixIcon: widget.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 14),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    widget.onChanged('');
                    _controller.clear();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: widget.onChanged,
        autofocus: true,
      ),
    );
  }
}

class _MonospaceText extends StatelessWidget {
  final String text;
  final bool isHex;
  final String searchQuery;
  final ScrollController? scrollController;

  const _MonospaceText(
    this.text, {
    this.isHex = false,
    this.searchQuery = '',
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (searchQuery.isEmpty) {
      return SelectionArea(
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(12),
          child: Text(
            text,
            style: TextStyle(
              fontSize: isHex ? 11 : 12,
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
        ),
      );
    }

    return SelectionArea(
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(12),
        child: _buildHighlightedText(text, searchQuery, isHex),
      ),
    );
  }

  Widget _buildHighlightedText(String text, String query, bool isHex) {
    final matches = <TextSpan>[];
    final pattern = RegExp(query, caseSensitive: false);
    int lastEnd = 0;

    for (final match in pattern.allMatches(text)) {
      // Add text before match
      if (match.start > lastEnd) {
        matches.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: TextStyle(
              fontSize: isHex ? 11 : 12,
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
        );
      }

      // Add highlighted match - all matches get the same highlighting
      matches.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            fontSize: isHex ? 11 : 12,
            fontFamily: 'monospace',
            height: 1.5,
            backgroundColor: Colors.yellow[300],
            color: Colors.black,
          ),
        ),
      );

      lastEnd = match.end;
    }

    // Add remaining text after last match
    if (lastEnd < text.length) {
      matches.add(
        TextSpan(
          text: text.substring(lastEnd),
          style: TextStyle(
            fontSize: isHex ? 11 : 12,
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
      );
    }

    return Text.rich(TextSpan(children: matches));
  }
}

class _JsonLineList extends StatelessWidget {
  final List<JsonLine> lines;
  final String searchQuery;
  final ScrollController? scrollController;
  const _JsonLineList(
    this.lines, {
    this.searchQuery = '',
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final search = searchQuery.isEmpty
        ? null
        : RegExp(searchQuery, caseSensitive: false);
    return SelectionArea(
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          return Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.5,
              ),
              children: _spansForLine(lines[index], isDark, search),
            ),
          );
        },
      ),
    );
  }

  static List<TextSpan> _spansForLine(
    JsonLine line,
    bool isDark,
    RegExp? search,
  ) {
    final spans = <TextSpan>[];
    for (final segment in line.segments) {
      final baseStyle = TextStyle(color: _colorFor(segment.kind, isDark));
      if (search == null) {
        spans.add(TextSpan(text: segment.text, style: baseStyle));
        continue;
      }
      final matches = search.allMatches(segment.text);
      if (matches.isEmpty) {
        spans.add(TextSpan(text: segment.text, style: baseStyle));
        continue;
      }
      int lastEnd = 0;
      for (final match in matches) {
        if (match.start > lastEnd) {
          spans.add(
            TextSpan(
              text: segment.text.substring(lastEnd, match.start),
              style: baseStyle,
            ),
          );
        }
        spans.add(
          TextSpan(
            text: segment.text.substring(match.start, match.end),
            style: TextStyle(
              backgroundColor: Colors.yellow[300],
              color: Colors.black,
            ),
          ),
        );
        lastEnd = match.end;
      }
      if (lastEnd < segment.text.length) {
        spans.add(
          TextSpan(text: segment.text.substring(lastEnd), style: baseStyle),
        );
      }
    }
    return spans;
  }

  static Color _colorFor(JsonTokenKind kind, bool isDark) {
    // VS Code–inspired palette, dark and light variants
    return switch (kind) {
      JsonTokenKind.key =>
        isDark ? const Color(0xFF9CDCFE) : const Color(0xFF0451A5),
      JsonTokenKind.string =>
        isDark ? const Color(0xFFCE9178) : const Color(0xFFA31515),
      JsonTokenKind.number =>
        isDark ? const Color(0xFFB5CEA8) : const Color(0xFF098658),
      JsonTokenKind.boolNull =>
        isDark ? const Color(0xFF569CD6) : const Color(0xFF0000FF),
      JsonTokenKind.punctuation ||
      JsonTokenKind.whitespace ||
      JsonTokenKind.other =>
        isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E),
    };
  }
}

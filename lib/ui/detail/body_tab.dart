import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/captured_exchange.dart';
import '../../providers/proxy_channel_provider.dart';
import '../../utils/body_renderer.dart';

enum BodySide { request, response }

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
    if (old.exchange.id != widget.exchange.id) {
      setState(() {
        _error = null;
        // Reset search state when exchange changes
        _showSearchBar = false;
        _searchQuery = '';
      });
      _fetchIfNeeded();
    }
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

  Future<void> _fetchIfNeeded() async {
    if (_cachedBytes != null) return;
    final ref = _ref;
    if (ref == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final channel = this.ref.read(proxyChannelProvider);
      Uint8List? bytes = await channel.fetchBody(ref);
      if (bytes == null) {
        setState(() => _loading = false);
        return;
      }
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
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
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          if (_showSearchBar)
            BodySearchBar(
              key: _searchBarKey,
              text: _searchQuery,
              onChanged: (query) {
                setState(() => _searchQuery = query);
              },
              onClose: _toggleSearch,
            ),
          Expanded(
            child: BodyContent(
              bytes: bytes,
              contentType: _contentType,
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
  final Uint8List bytes;
  final String? contentType;
  final String searchQuery;
  final ScrollController? scrollController;

  const BodyContent({
    super.key,
    required this.bytes,
    this.contentType,
    this.searchQuery = '',
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final mode = BodyRenderer.render(data: bytes, contentType: contentType);

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
      RenderJson(:final text) => _JsonHighlightedText(
        text,
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

class _JsonHighlightedText extends StatelessWidget {
  final String json;
  final String searchQuery;
  final ScrollController? scrollController;
  const _JsonHighlightedText(
    this.json, {
    this.searchQuery = '',
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (searchQuery.isEmpty) {
      return SelectionArea(
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(12),
          child: SelectableText.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.5,
              ),
              children: _buildSpans(json, isDark),
            ),
          ),
        ),
      );
    }

    return SelectionArea(
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(12),
        child: SelectableText.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.5,
            ),
            children: _buildSpansWithSearch(json, isDark, searchQuery),
          ),
        ),
      ),
    );
  }

  static List<TextSpan> _buildSpans(String source, bool isDark) {
    // VS Code–inspired palette, dark and light variants
    final keyColor = isDark ? const Color(0xFF9CDCFE) : const Color(0xFF0451A5);
    final stringColor = isDark
        ? const Color(0xFFCE9178)
        : const Color(0xFFA31515);
    final numberColor = isDark
        ? const Color(0xFFB5CEA8)
        : const Color(0xFF098658);
    final boolNullColor = isDark
        ? const Color(0xFF569CD6)
        : const Color(0xFF0000FF);
    final defaultColor = isDark
        ? const Color(0xFFD4D4D4)
        : const Color(0xFF1E1E1E);

    final re = RegExp(
      r'("(?:[^"\\]|\\.)*")' // group 1 – string
      r'|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)' // group 2 – number
      r'|(true|false|null)' // group 3 – keyword
      r'|([{}\[\],:])' // group 4 – punctuation
      r'|(\s+)' // group 5 – whitespace
      r'|(.)', // group 6 – fallback
      dotAll: true,
    );

    final spans = <TextSpan>[];
    for (final m in re.allMatches(source)) {
      if (m.group(1) != null) {
        // Determine key vs string value: look ahead for ':'
        var i = m.end;
        while (i < source.length && (source[i] == ' ' || source[i] == '\t')) {
          i++;
        }
        final isKey = i < source.length && source[i] == ':';
        spans.add(
          TextSpan(
            text: m.group(1),
            style: TextStyle(color: isKey ? keyColor : stringColor),
          ),
        );
      } else if (m.group(2) != null) {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: TextStyle(color: numberColor),
          ),
        );
      } else if (m.group(3) != null) {
        spans.add(
          TextSpan(
            text: m.group(3),
            style: TextStyle(color: boolNullColor),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: m.group(0),
            style: TextStyle(color: defaultColor),
          ),
        );
      }
    }
    return spans;
  }

  static List<TextSpan> _buildSpansWithSearch(
    String source,
    bool isDark,
    String query,
  ) {
    // VS Code–inspired palette, dark and light variants
    final keyColor = isDark ? const Color(0xFF9CDCFE) : const Color(0xFF0451A5);
    final stringColor = isDark
        ? const Color(0xFFCE9178)
        : const Color(0xFFA31515);
    final numberColor = isDark
        ? const Color(0xFFB5CEA8)
        : const Color(0xFF098658);
    final boolNullColor = isDark
        ? const Color(0xFF569CD6)
        : const Color(0xFF0000FF);
    final defaultColor = isDark
        ? const Color(0xFFD4D4D4)
        : const Color(0xFF1E1E1E);
    final searchColor = Colors.yellow[300];

    final re = RegExp(
      r'("(?:[^"\\]|\\.)*")' // group 1 – string
      r'|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)' // group 2 – number
      r'|(true|false|null)' // group 3 – keyword
      r'|([{}\[\],:])' // group 4 – punctuation
      r'|(\s+)' // group 5 – whitespace
      r'|(.)', // group 6 – fallback
      dotAll: true,
    );

    final searchPattern = RegExp(query, caseSensitive: false);
    final spans = <TextSpan>[];

    for (final m in re.allMatches(source)) {
      final text = m.group(0)!;
      final start = m.start;
      final end = m.end;

      // Check if this span contains search matches
      final searchMatches = searchPattern.allMatches(text);

      if (searchMatches.isEmpty) {
        // No search matches in this span, apply normal styling
        if (m.group(1) != null) {
          // Determine key vs string value: look ahead for ':'
          var i = end;
          while (i < source.length && (source[i] == ' ' || source[i] == '\t')) {
            i++;
          }
          final isKey = i < source.length && source[i] == ':';
          spans.add(
            TextSpan(
              text: text,
              style: TextStyle(color: isKey ? keyColor : stringColor),
            ),
          );
        } else if (m.group(2) != null) {
          spans.add(
            TextSpan(
              text: text,
              style: TextStyle(color: numberColor),
            ),
          );
        } else if (m.group(3) != null) {
          spans.add(
            TextSpan(
              text: text,
              style: TextStyle(color: boolNullColor),
            ),
          );
        } else {
          spans.add(
            TextSpan(
              text: text,
              style: TextStyle(color: defaultColor),
            ),
          );
        }
      } else {
        // This span contains search matches, need to split it
        int lastEnd = 0;
        for (final searchMatch in searchMatches) {
          // Add text before match
          if (searchMatch.start > lastEnd) {
            final beforeText = text.substring(lastEnd, searchMatch.start);
            TextStyle? style;
            if (m.group(1) != null) {
              // Determine key vs string value for the before part
              var i = start + searchMatch.start;
              while (i < source.length &&
                  (source[i] == ' ' || source[i] == '\t')) {
                i++;
              }
              final isKey = i < source.length && source[i] == ':';
              style = TextStyle(color: isKey ? keyColor : stringColor);
            } else if (m.group(2) != null) {
              style = TextStyle(color: numberColor);
            } else if (m.group(3) != null) {
              style = TextStyle(color: boolNullColor);
            } else {
              style = TextStyle(color: defaultColor);
            }
            spans.add(TextSpan(text: beforeText, style: style));
          }

          // Add highlighted match
          final matchText = text.substring(searchMatch.start, searchMatch.end);
          spans.add(
            TextSpan(
              text: matchText,
              style: TextStyle(
                backgroundColor: searchColor,
                color: Colors.black,
              ),
            ),
          );

          lastEnd = searchMatch.end;
        }

        // Add remaining text after last match
        if (lastEnd < text.length) {
          final afterText = text.substring(lastEnd);
          TextStyle? style;
          if (m.group(1) != null) {
            // Determine key vs string value for the after part
            var i = start + lastEnd;
            while (i < source.length &&
                (source[i] == ' ' || source[i] == '\t')) {
              i++;
            }
            final isKey = i < source.length && source[i] == ':';
            style = TextStyle(color: isKey ? keyColor : stringColor);
          } else if (m.group(2) != null) {
            style = TextStyle(color: numberColor);
          } else if (m.group(3) != null) {
            style = TextStyle(color: boolNullColor);
          } else {
            style = TextStyle(color: defaultColor);
          }
          spans.add(TextSpan(text: afterText, style: style));
        }
      }
    }
    return spans;
  }
}

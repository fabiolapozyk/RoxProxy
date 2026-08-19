import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/captured_exchange.dart';
import '../../providers/proxy_channel_provider.dart';
import '../../utils/body_renderer.dart';
import 'body_search.dart';

enum BodySide { request, response }

const int _kInlineRenderBytesLimit = 32 * 1024;
const int _kJsonNonLazyMaxLines = 2000;

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
  bool _selectAll = false;
  List<String> _lineTexts = const [];
  List<BodyMatch> _matches = const [];
  int _currentMatch = -1;
  BodySearchLayout? _layout;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<_BodySearchBarState> _searchBarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchIfNeeded();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (!_showSearchBar) {
        // Reset search state when closing search bar
        _resetSearchState();
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

  bool get _isEditingText {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext != null &&
        focusContext.findAncestorWidgetOfExactType<TextField>() != null;
  }

  bool get _isLargeJson {
    final mode = _mode;
    return mode is RenderJson && mode.lines.length > _kJsonNonLazyMaxLines;
  }

  void _deselectAll() {
    if (_selectAll) setState(() => _selectAll = false);
  }

  void _resetSearchState() {
    _searchQuery = '';
    _matches = const [];
    _currentMatch = -1;
  }

  TextStyle _bodyTextStyle(bool isHex) => TextStyle(
    fontSize: isHex ? 11 : 12,
    fontFamily: 'monospace',
    height: 1.5,
  );

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _matches = findMatches(_lineTexts, query);
      _currentMatch = -1;
    });
  }

  void _handleSearchNext() {
    if (_matches.isEmpty) return;
    _jumpTo((_currentMatch + 1) % _matches.length);
  }

  void _handleSearchPrev() {
    if (_matches.isEmpty) return;
    final prev = _currentMatch < 0
        ? _matches.length - 1
        : (_currentMatch - 1 + _matches.length) % _matches.length;
    _jumpTo(prev);
  }

  void _jumpTo(int index) {
    setState(() => _currentMatch = index);
    final controller = _scrollController;
    final layout = _layout;
    if (!controller.hasClients || layout == null) return;
    final maxExtent = controller.position.maxScrollExtent;
    final target = (layout.offsetForMatch(_matches[index]) - 32).clamp(
      0.0,
      maxExtent,
    );
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _ensureLayoutFor(double width) {
    final mode = _mode;
    if (mode is! RenderText && mode is! RenderJson && mode is! RenderHex) {
      _layout = null;
      return;
    }
    final targetWidth = width - 24; // padding orizzontale (EdgeInsets.all(12))
    final existing = _layout;
    if (existing != null && existing.maxWidth == targetWidth) return;
    _layout = BodySearchLayout(
      lines: _lineTexts,
      maxWidth: targetWidth,
      style: _bodyTextStyle(mode is RenderHex),
      textScaler: MediaQuery.textScalerOf(context),
      perLineParagraphs: _isLargeJson,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final isMetaPressed =
          HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;
      if (isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyA) {
        if (!_isEditingText && _isLargeJson) {
          setState(() => _selectAll = true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      } else if (isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyC) {
        if (!_isEditingText && _selectAll && _isLargeJson) {
          Clipboard.setData(ClipboardData(text: (_mode! as RenderJson).text));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      } else if (isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyF) {
        _toggleSearch();
        return KeyEventResult.handled;
      } else if (_showSearchBar &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _toggleSearch();
        return KeyEventResult.handled;
      }
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
        _resetSearchState();
        _mode = null;
        _rendering = false;
        _selectAll = false;
        _lineTexts = const [];
        _layout = null;
      });
    } else if (bytesChanged) {
      setState(() {
        _mode = null;
        _rendering = false;
        _selectAll = false;
        _resetSearchState();
        _lineTexts = const [];
        _layout = null;
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
          _lineTexts = switch (mode) {
            RenderText(:final text) => splitLines(text),
            RenderHex(:final text) => splitLines(text),
            RenderJson(:final lines) => [
              for (final l in lines) l.segments.map((s) => s.text).join(),
            ],
            _ => const <String>[],
          };
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
                      onChanged: _onSearchChanged,
                      onClose: _toggleSearch,
                      matchCount: _matches.length,
                      currentMatch: _currentMatch,
                      onNext: _handleSearchNext,
                      onPrev: _handleSearchPrev,
                    ),
                  ),
              ],
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _ensureLayoutFor(constraints.maxWidth);
                return BodyContent(
                  mode: _mode!,
                  matches: _matches,
                  currentMatchIndex: _matches.isEmpty || _currentMatch < 0
                      ? null
                      : _currentMatch,
                  layout: _isLargeJson ? _layout : null,
                  scrollController: _scrollController,
                  selectAll: _selectAll,
                  onDeselect: _deselectAll,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class BodyContent extends StatelessWidget {
  final RenderMode mode;
  final List<BodyMatch> matches;
  final int? currentMatchIndex;
  final BodySearchLayout? layout;
  final ScrollController? scrollController;
  final bool selectAll;
  final VoidCallback? onDeselect;

  const BodyContent({
    super.key,
    required this.mode,
    this.matches = const [],
    this.currentMatchIndex,
    this.layout,
    this.scrollController,
    this.selectAll = false,
    this.onDeselect,
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
        matches: matches,
        currentMatch: currentMatchIndex,
        layout: layout,
        scrollController: scrollController,
        selectAll: selectAll,
        onDeselect: onDeselect,
      ),
      RenderText(:final text) => _MonospaceText(
        splitLines(text),
        isHex: false,
        matches: matches,
        currentMatch: currentMatchIndex,
        scrollController: scrollController,
      ),
      RenderHex(:final text) => _MonospaceText(
        splitLines(text),
        isHex: true,
        matches: matches,
        currentMatch: currentMatchIndex,
        scrollController: scrollController,
      ),
    };
  }
}

class BodySearchBar extends StatefulWidget {
  final String text;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final int matchCount;
  final int currentMatch;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  const BodySearchBar({
    super.key,
    required this.text,
    required this.onChanged,
    required this.onClose,
    required this.matchCount,
    required this.currentMatch,
    required this.onNext,
    required this.onPrev,
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
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Search in body…',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 16),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: widget.onChanged,
              onSubmitted: (_) {
                widget.onNext();
                // Dopo il submit il framework può staccare il focus: lo
                // ri-assegno così Enter ripetuto continua a ciclare.
                _focusNode.requestFocus();
              },
              autofocus: true,
            ),
          ),
          if (widget.text.isNotEmpty) ...[
            Text(
              widget.matchCount == 0
                  ? '0/0'
                  : '${widget.currentMatch < 0 ? 0 : widget.currentMatch + 1}/${widget.matchCount}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Previous match',
              onPressed: widget.onPrev,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Next match (Enter)',
              onPressed: widget.onNext,
            ),
            IconButton(
              icon: const Icon(Icons.clear, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () {
                widget.onChanged('');
                _controller.clear();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _MonospaceText extends StatelessWidget {
  final List<String> lines;
  final bool isHex;
  final List<BodyMatch> matches;
  final int? currentMatch;
  final ScrollController? scrollController;

  const _MonospaceText(
    this.lines, {
    this.isHex = false,
    this.matches = const [],
    this.currentMatch,
    this.scrollController,
  });

  TextStyle _baseStyle() => TextStyle(
    fontSize: isHex ? 11 : 12,
    fontFamily: 'monospace',
    height: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return SelectionArea(
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(12),
          child: Text(lines.join('\n'), style: _baseStyle()),
        ),
      );
    }

    return SelectionArea(
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(12),
        child: Text.rich(TextSpan(children: _buildHighlightedText())),
      ),
    );
  }

  List<TextSpan> _buildHighlightedText() {
    final base = _baseStyle();
    final highlight = TextStyle(
      fontSize: isHex ? 11 : 12,
      fontFamily: 'monospace',
      height: 1.5,
      backgroundColor: Colors.orange[400],
      color: Colors.black,
    );
    final other = TextStyle(
      fontSize: isHex ? 11 : 12,
      fontFamily: 'monospace',
      height: 1.5,
      backgroundColor: Colors.yellow[300],
      color: Colors.black,
    );
    final spans = <TextSpan>[];
    var matchIdx = 0;
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(TextSpan(text: '\n', style: base));
      final line = lines[i];
      var cursor = 0;
      while (matchIdx < matches.length && matches[matchIdx].line == i) {
        final m = matches[matchIdx];
        if (m.start > cursor) {
          spans.add(
            TextSpan(text: line.substring(cursor, m.start), style: base),
          );
        }
        spans.add(
          TextSpan(
            text: line.substring(m.start, m.end),
            style: matchIdx == currentMatch ? highlight : other,
          ),
        );
        cursor = m.end;
        matchIdx++;
      }
      if (cursor < line.length) {
        spans.add(TextSpan(text: line.substring(cursor), style: base));
      }
    }
    return spans;
  }
}

class _JsonLineList extends StatelessWidget {
  final List<JsonLine> lines;
  final List<BodyMatch> matches;
  final int? currentMatch;
  final BodySearchLayout? layout;
  final ScrollController? scrollController;
  final bool selectAll;
  final VoidCallback? onDeselect;
  const _JsonLineList(
    this.lines, {
    this.matches = const [],
    this.currentMatch,
    this.layout,
    this.scrollController,
    this.selectAll = false,
    this.onDeselect,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (lines.length > _kJsonNonLazyMaxLines) {
      return Listener(
        onPointerDown: (_) => onDeselect?.call(),
        child: SelectionArea(
          onSelectionChanged: (content) {
            if (content != null) onDeselect?.call();
          },
          child: Builder(
            builder: (context) {
              final selectionColor =
                  DefaultSelectionStyle.of(context).selectionColor ??
                  Theme.of(context).colorScheme.primary;
              final l = layout;
              Widget buildItem(BuildContext context, int index) {
                return Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      height: 1.5,
                      backgroundColor: selectAll ? selectionColor : null,
                    ),
                    children: _spansForLine(
                      lines[index],
                      index,
                      isDark,
                      matches,
                      currentMatch,
                    ),
                  ),
                );
              }

              if (l != null) {
                // Estensioni esatte per ogni item + max scroll extent esatto:
                // con il solo ListView.builder la stima dell'estensione media
                // fa fermare la ricerca "troppo prima" su body grandi.
                return ListView.custom(
                  controller: scrollController,
                  padding: const EdgeInsets.all(12),
                  itemExtentBuilder: (index, dimensions) => l.lineHeight(index),
                  childrenDelegate: _ExactExtentDelegate(
                    builder: buildItem,
                    childCount: lines.length,
                    totalExtent: () => l.totalHeight,
                  ),
                );
              }
              return ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: lines.length,
                itemBuilder: buildItem,
              );
            },
          ),
        ),
      );
    }
    return SelectionArea(
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(12),
        child: _wholeDocumentText(isDark),
      ),
    );
  }

  Widget _wholeDocumentText(bool isDark) {
    final spans = <TextSpan>[];
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      spans.addAll(_spansForLine(lines[i], i, isDark, matches, currentMatch));
    }
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          height: 1.5,
        ),
        children: spans,
      ),
    );
  }

  static List<TextSpan> _spansForLine(
    JsonLine line,
    int lineIndex,
    bool isDark,
    List<BodyMatch> matches,
    int? currentMatch,
  ) {
    TextStyle styleFor(JsonSegment s) =>
        TextStyle(color: _colorFor(s.kind, isDark));
    final lineMatches = matches.where((m) => m.line == lineIndex).toList();
    if (lineMatches.isEmpty) {
      return [
        for (final s in line.segments)
          TextSpan(text: s.text, style: styleFor(s)),
      ];
    }

    final highlight = TextStyle(
      backgroundColor: Colors.orange[400],
      color: Colors.black,
    );
    final other = TextStyle(
      backgroundColor: Colors.yellow[300],
      color: Colors.black,
    );

    final spans = <TextSpan>[];
    var segStart = 0;
    for (final seg in line.segments) {
      final segText = seg.text;
      final segEnd = segStart + segText.length;
      var cursor = 0;
      for (final m in lineMatches) {
        if (m.end <= segStart) continue;
        if (m.start >= segEnd) break;
        final ms = (m.start < segStart ? segStart : m.start) - segStart;
        final me = (m.end > segEnd ? segEnd : m.end) - segStart;
        if (ms > cursor) {
          spans.add(
            TextSpan(text: segText.substring(cursor, ms), style: styleFor(seg)),
          );
        }
        spans.add(
          TextSpan(
            text: segText.substring(ms, me),
            style: m.index == currentMatch ? highlight : other,
          ),
        );
        cursor = me;
      }
      if (cursor < segText.length) {
        spans.add(
          TextSpan(text: segText.substring(cursor), style: styleFor(seg)),
        );
      }
      segStart = segEnd;
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

/// Delegate per la ListView lazy del JSON con max scroll extent esatto.
///
/// `SliverChildBuilderDelegate` di default non fornisce una stima (torna null):
/// la viewport estrapola dall'estensione media degli item costruiti, che su
/// body grandi con altezze variabili sottostima il massimo e fa fermare
/// l'animateTo della ricerca troppo prima.
class _ExactExtentDelegate extends SliverChildBuilderDelegate {
  final double Function() totalExtent;

  _ExactExtentDelegate({
    required NullableIndexedWidgetBuilder builder,
    required int childCount,
    required this.totalExtent,
  }) : super(builder, childCount: childCount);

  @override
  double? estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) {
    return totalExtent();
  }
}

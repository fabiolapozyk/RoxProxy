import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/breakpoint_rule.dart';
import '../../models/captured_exchange.dart';
import '../../models/replay_request.dart';
import '../../providers/breakpoint_provider.dart';
import '../../providers/exchange_provider.dart';
import '../../providers/proxy_channel_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/data_formatting.dart';
import '../components/https_indicator.dart';
import '../components/method_badge.dart';
import '../components/status_indicator.dart';
import '../replay_dialog.dart';

// MARK: - Column widths

class _ColWidths {
  final double method;
  final double status;
  final double host;
  final double duration;
  final double size;

  const _ColWidths({
    this.method = 70,
    this.status = 48,
    this.host = 160,
    this.duration = 64,
    this.size = 64,
  });

  _ColWidths copyWith({
    double? method,
    double? status,
    double? host,
    double? duration,
    double? size,
  }) =>
      _ColWidths(
        method: method ?? this.method,
        status: status ?? this.status,
        host: host ?? this.host,
        duration: duration ?? this.duration,
        size: size ?? this.size,
      );
}

// MARK: - Root view

class RequestListView extends ConsumerStatefulWidget {
  const RequestListView({super.key});

  @override
  ConsumerState<RequestListView> createState() => _RequestListViewState();
}

class _RequestListViewState extends ConsumerState<RequestListView> {
  _ColWidths _widths = const _ColWidths();

  @override
  Widget build(BuildContext context) {
    final exchanges = ref.watch(filteredExchangesProvider);
    final selectedId = ref.watch(selectedExchangeIdProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showHeaders = constraints.maxWidth > 400;
        return Column(
          children: [
            if (showHeaders)
              _ColumnHeader(
                widths: _widths,
                onResize: (updated) => setState(() => _widths = updated),
              ),
            if (showHeaders) const Divider(height: 1),
            Expanded(
              child: exchanges.isEmpty
                  ? Center(
                      child: Text(
                        'No requests captured',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: constraints.maxWidth < 600 ? 12 : 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: exchanges.length,
                      itemExtent: 28,
                      itemBuilder: (context, index) {
                        final exchange = exchanges[index];
                        final isSelected = exchange.id == selectedId;
                        return _ExchangeRow(
                          exchange: exchange,
                          isSelected: isSelected,
                          widths: _widths,
                          onTap: () => ref
                              .read(selectedExchangeIdProvider.notifier)
                              .state = exchange.id,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// MARK: - Column header

class _ColumnHeader extends StatelessWidget {
  final _ColWidths widths;
  final ValueChanged<_ColWidths> onResize;

  const _ColumnHeader({required this.widths, required this.onResize});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const SizedBox(width: 20), // HTTPS icon — fixed, no handle
          const SizedBox(width: 8),
          // Method — handle on right edge
          SizedBox(width: widths.method, child: const _HeaderLabel('Method')),
          _ResizeHandle(
            onDelta: (dx) => onResize(
              widths.copyWith(method: (widths.method + dx).clamp(40.0, 200.0)),
            ),
          ),
          // Status — handle on right edge
          SizedBox(width: widths.status, child: const _HeaderLabel('Status')),
          _ResizeHandle(
            onDelta: (dx) => onResize(
              widths.copyWith(status: (widths.status + dx).clamp(36.0, 120.0)),
            ),
          ),
          // Host — handle on right edge
          SizedBox(width: widths.host, child: const _HeaderLabel('Host')),
          _ResizeHandle(
            onDelta: (dx) => onResize(
              widths.copyWith(host: (widths.host + dx).clamp(60.0, 300.0)),
            ),
          ),
          // Path (Expanded) — absorbs all leftover space
          const Expanded(child: _HeaderLabel('Path')),
          // Duration — handle on LEFT edge (drag right = shrinks, drag left = grows)
          _ResizeHandle(
            onDelta: (dx) => onResize(
              widths.copyWith(
                  duration: (widths.duration - dx).clamp(48.0, 150.0)),
            ),
          ),
          SizedBox(width: widths.duration, child: const _HeaderLabel('Duration')),
          // Size — handle on LEFT edge
          _ResizeHandle(
            onDelta: (dx) => onResize(
              widths.copyWith(size: (widths.size - dx).clamp(40.0, 150.0)),
            ),
          ),
          SizedBox(width: widths.size, child: const _HeaderLabel('Size')),
        ],
      ),
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  final String label;
  const _HeaderLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

// MARK: - Resize handle

class _ResizeHandle extends StatefulWidget {
  final ValueChanged<double> onDelta;
  const _ResizeHandle({required this.onDelta});

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onDelta(d.delta.dx),
        child: SizedBox(
          width: 8,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 1,
              height: double.infinity,
              color: _hovering
                  ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

// MARK: - Exchange row

class _ExchangeRow extends ConsumerWidget {
  final CapturedExchange exchange;
  final bool isSelected;
  final VoidCallback onTap;
  final _ColWidths widths;

  const _ExchangeRow({
    required this.exchange,
    required this.isSelected,
    required this.onTap,
    required this.widths,
  });

  bool get _canCopyCurl => !exchange.isHTTPS || exchange.isMITMDecrypted;

  bool get _canCopyUrl => true; // URL can always be copied

  bool get _canAddDomain => exchange.isHTTPS && !exchange.isMITMDecrypted;

  bool get _canReplay => exchange.state == ExchangeState.completed && 
                         !(exchange.isHTTPS && !exchange.isMITMDecrypted && exchange.method == 'CONNECT');

  bool get _canAddBreakpoint => exchange.isHTTPS || exchange.scheme == 'http';

  Future<void> _copyAsCurl(BuildContext context, WidgetRef ref) async {
    var bodyBytes = exchange.cachedRequestBody;
    if (bodyBytes == null && exchange.requestBodyRef != null) {
      bodyBytes = await ref
          .read(proxyChannelProvider)
          .fetchBody(exchange.requestBodyRef!);
      if (bodyBytes != null) exchange.setCachedRequestBody(bodyBytes);
    }
    final curl =
        DataFormatting.buildCurlCommand(exchange, bodyBytes: bodyBytes);
    await Clipboard.setData(ClipboardData(text: curl));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('cURL copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _copyUrl(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: exchange.url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showContextMenu(
      BuildContext context, WidgetRef ref, Offset globalPosition) async {
    if (!_canCopyCurl && !_canAddDomain) return;

    final settings = ref.read(settingsProvider);
    final alreadyIntercepted =
        settings.domainRules.any((r) => r.domain == exchange.host);

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (_canCopyCurl)
          const PopupMenuItem<String>(
            value: 'curl',
            child: Text('Copy as cURL', style: TextStyle(fontSize: 13)),
          ),
        if (_canCopyUrl)
          const PopupMenuItem<String>(
            value: 'url',
            child: Text('Copy URL', style: TextStyle(fontSize: 13)),
          ),
        if (_canAddDomain && !alreadyIntercepted)
          PopupMenuItem<String>(
            value: 'add_domain',
            child: Text(
              'Intercept HTTPS for ${exchange.host}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        if (_canAddDomain && alreadyIntercepted)
          PopupMenuItem<String>(
            enabled: false,
            value: 'add_domain_disabled',
            child: Text(
              '${exchange.host} already intercepted',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ),
        if (_canReplay)
          const PopupMenuItem<String>(
            value: 'replay',
            child: Text('Edit and Replay', style: TextStyle(fontSize: 13)),
          ),
        if (_canAddBreakpoint)
          const PopupMenuItem<String>(
            value: 'add_breakpoint',
            child: Text('Add Breakpoint for this URL', style: TextStyle(fontSize: 13)),
          ),
      ],
    );

    if (!context.mounted) return;
    if (result == 'curl') {
      await _copyAsCurl(context, ref);
    } else if (result == 'url') {
      await _copyUrl(context);
    } else if (result == 'add_domain') {
      ref.read(settingsProvider.notifier).addDomain(exchange.host);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('HTTPS interception enabled for ${exchange.host}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (result == 'replay') {
      await _showReplayDialog(context, ref);
    } else if (result == 'add_breakpoint') {
      _addBreakpointRule(context, ref);
    }
  }

  void _addBreakpointRule(BuildContext context, WidgetRef ref) {
    // Create a breakpoint rule from the exchange URL
    final rule = BreakpointRule.fromExchangeUrl(exchange.url);
    
    // Add the rule
    ref.read(breakpointProvider.notifier).addRule(rule);
    
    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Breakpoint added for ${rule.urlPattern}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showReplayDialog(BuildContext context, WidgetRef ref) async {
    debugPrint('=== SHOW REPLAY DIALOG ===');
    debugPrint('Exchange method: ${exchange.method}');
    debugPrint('Exchange URL: ${exchange.url}');
    debugPrint('Has cached body: ${exchange.cachedRequestBody != null}');
    debugPrint('Has body ref: ${exchange.requestBodyRef != null}');
    
    // Fetch body if not cached
    if (exchange.cachedRequestBody == null && exchange.requestBodyRef != null) {
      debugPrint('Fetching body from storage...');
      final channel = ref.read(proxyChannelProvider);
      final bodyBytes = await channel.fetchBody(exchange.requestBodyRef!);
      if (bodyBytes != null) {
        exchange.setCachedRequestBody(bodyBytes);
        debugPrint('Body fetched and cached: ${String.fromCharCodes(bodyBytes)}');
      } else {
        debugPrint('Body fetch returned null');
      }
    }
    
    final replayRequest = ReplayRequest.fromExchange(exchange);
    
    final result = await showDialog<ReplayRequest>(
      context: context,
      builder: (context) => ReplayDialog(initialRequest: replayRequest),
    );
    
    if (result != null) {
      try {
        final channel = ref.read(proxyChannelProvider);
        final exchangeId = await channel.replayRequest(result.toMap());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request replayed: $exchangeId'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80.0, left: 10.0, right: 10.0),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to replay: ${e.toString()}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80.0, left: 10.0, right: 10.0),
          ),
        );
      }
    } else {
      debugPrint('Replay dialog cancelled');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (_canCopyCurl || _canCopyUrl || _canAddDomain || _canAddBreakpoint)
          ? (d) => _showContextMenu(context, ref, d.globalPosition)
          : null,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: HttpsIndicator(
                isHTTPS: exchange.isHTTPS,
                isMITMDecrypted: exchange.isMITMDecrypted,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: widths.method, child: MethodBadge(exchange.method)),
            const SizedBox(width: 8),
            SizedBox(
              width: widths.status,
              child: StatusIndicator(
                statusCode: exchange.statusCode,
                state: exchange.state,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: widths.host,
              child: Text(
                exchange.host,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: exchange.url,
                waitDuration: const Duration(milliseconds: 500),
                child: Text(
                  exchange.path,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: widths.duration,
              child: Text(
                DataFormatting.formatDuration(exchange.duration),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: widths.size,
              child: Text(
                exchange.responseSize != null
                    ? DataFormatting.formatSize(exchange.responseSize!)
                    : '—',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

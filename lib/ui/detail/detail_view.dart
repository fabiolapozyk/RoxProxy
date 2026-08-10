import 'package:flutter/material.dart';

import '../../models/captured_exchange.dart';
import '../../utils/data_formatting.dart';
import '../components/method_badge.dart';
import '../components/status_indicator.dart';
import 'body_tab.dart';
import 'headers_tab.dart';

class DetailView extends StatefulWidget {
  final CapturedExchange exchange;

  const DetailView({super.key, required this.exchange});

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exchange;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SummaryBar(exchange: e, isCompact: isCompact),
            const Divider(height: 1),
            TabBar(
              controller: _tabController,
              labelStyle: TextStyle(
                fontSize: isCompact ? 11 : 12,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(text: 'Request'),
                Tab(text: 'Response'),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _RequestPane(exchange: e),
                  _ResponsePane(exchange: e),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// MARK: - Summary Bar

class _SummaryBar extends StatelessWidget {
  final CapturedExchange exchange;
  final bool isCompact;
  const _SummaryBar({required this.exchange, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: MethodBadge(exchange.method),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              exchange.url,
              style: TextStyle(fontSize: isCompact ? 11 : 12),
              softWrap: true,
            ),
          ),
          const SizedBox(width: 8),
          StatusIndicator(
            statusCode: exchange.statusCode,
            state: exchange.state,
          ),
          if (exchange.duration != null) ...[
            const SizedBox(width: 8),
            Text(
              DataFormatting.formatDuration(exchange.duration),
              style: TextStyle(
                fontSize: isCompact ? 10 : 11,
                color: Colors.grey,
              ),
            ),
          ],
          if (exchange.responseSize != null) ...[
            const SizedBox(width: 8),
            Text(
              DataFormatting.formatSize(exchange.responseSize!),
              style: TextStyle(
                fontSize: isCompact ? 10 : 11,
                color: Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// MARK: - Request Pane

class _RequestPane extends StatefulWidget {
  final CapturedExchange exchange;
  const _RequestPane({required this.exchange});

  @override
  State<_RequestPane> createState() => _RequestPaneState();
}

class _RequestPaneState extends State<_RequestPane>
    with AutomaticKeepAliveClientMixin {
  int _tab = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _SubTabBar(
          tabs: const ['Headers', 'Body'],
          selected: _tab,
          onTap: (i) => setState(() => _tab = i),
        ),
        const Divider(height: 1),
        Expanded(
          child: _tab == 0
              ? HeadersTab(headers: widget.exchange.requestHeaders)
              : BodyTab.request(exchange: widget.exchange),
        ),
      ],
    );
  }
}

// MARK: - Response Pane

class _ResponsePane extends StatefulWidget {
  final CapturedExchange exchange;
  const _ResponsePane({required this.exchange});

  @override
  State<_ResponsePane> createState() => _ResponsePaneState();
}

class _ResponsePaneState extends State<_ResponsePane>
    with AutomaticKeepAliveClientMixin {
  int _tab = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hasError = widget.exchange.state == ExchangeState.failed;
    return Column(
      children: [
        _SubTabBar(
          tabs: const ['Headers', 'Body'],
          selected: _tab,
          onTap: (i) => setState(() => _tab = i),
        ),
        const Divider(height: 1),
        if (hasError)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              widget.exchange.errorMessage ?? 'Request failed',
              style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 12),
            ),
          ),
        Expanded(
          child: _tab == 0
              ? HeadersTab(headers: widget.exchange.responseHeaders ?? [])
              : BodyTab.response(exchange: widget.exchange),
        ),
      ],
    );
  }
}

// MARK: - Sub-tab bar

class _SubTabBar extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onTap;

  const _SubTabBar({
    required this.tabs,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isSelected = i == selected;
          return GestureDetector(
            onTap: () => onTap(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Center(
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

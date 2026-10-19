import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/session_provider.dart';
import '../components/empty_detail.dart';
import '../components/filter_bar.dart';
import '../components/panel_divider.dart';
import '../components/session_banner.dart';
import '../components/status_bar.dart';
import '../detail/detail_view.dart';
import '../request_list/request_list_view.dart';

/// Read-only screen for a capture opened from a HAR file.
///
/// It sits next to the live view: the proxy keeps running and the live capture
/// keeps accumulating, so closing this screen returns to it unchanged.
class OfflineSessionView extends ConsumerStatefulWidget {
  final OfflineSessionState session;

  const OfflineSessionView({super.key, required this.session});

  @override
  ConsumerState<OfflineSessionView> createState() => _OfflineSessionViewState();
}

class _OfflineSessionViewState extends ConsumerState<OfflineSessionView> {
  double _listWidth = 630;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final notifier = ref.read(offlineSessionProvider.notifier);
    final exchanges = session.filtered;
    final selected = session.selected;

    return Column(
      children: [
        SessionBanner(
          fileName: session.fileName,
          requestCount: session.exchanges.length,
          onClose: () => notifier.close(),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _listWidth,
                child: Column(
                  children: [
                    FilterBar(
                      text: session.filterText,
                      onChanged: notifier.setFilter,
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: RequestListView(
                        exchanges: exchanges,
                        selectedId: session.selectedId,
                        onSelect: (id) => notifier.select(id),
                        // A loaded session is static and read-only: no
                        // auto-scroll and no mutating context-menu actions.
                        autoScroll: false,
                        readOnly: true,
                      ),
                    ),
                  ],
                ),
              ),
              PanelDivider(
                onDelta: (dx) => setState(() {
                  _listWidth = (_listWidth + dx).clamp(300.0, 900.0);
                }),
              ),
              Expanded(
                child: selected != null
                    ? DetailView(exchange: selected)
                    : const EmptyDetail(),
              ),
            ],
          ),
        ),
        StatusBar(
          total: session.exchanges.length,
          filtered: exchanges.length,
          filterText: session.filterText,
          sourceLabel: 'offline',
        ),
      ],
    );
  }
}

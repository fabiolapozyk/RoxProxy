import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/proxy_state.dart';
import '../../providers/exchange_provider.dart';
import '../../providers/proxy_control_provider.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyState = ref.watch(proxyStateProvider);
    final total = ref.watch(exchangeListProvider).length;
    final filtered = ref.watch(filteredExchangesProvider).length;
    final filterText = ref.watch(filterTextProvider);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _StateIndicator(proxyState),
          const Spacer(),
          Text(
            filterText.isNotEmpty
                ? '$filtered of $total requests'
                : '$total requests',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StateIndicator extends StatelessWidget {
  final ProxyState state;
  const _StateIndicator(this.state);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _dotColor(state),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            state.description,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _dotColor(ProxyState s) => switch (s) {
    ProxyRunning() => const Color(0xFF34C759),
    ProxyStarting() => const Color(0xFFFF9500),
    ProxyError() => const Color(0xFFFF3B30),
    _ => const Color(0xFF8E8E93),
  };
}

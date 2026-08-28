import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/breakpoint_notification.dart';
import '../models/breakpoint_rule.dart';
import '../models/map_local_rule.dart';
import '../models/proxy_settings.dart';
import '../models/proxy_state.dart';
import '../providers/breakpoint_provider.dart';
import '../providers/breakpoint_rules_provider.dart';
import '../providers/exchange_provider.dart';
import '../providers/map_local_provider.dart';
import '../providers/proxy_control_provider.dart';
import '../providers/settings_provider.dart';
import 'breakpoint/breakpoint_dialog.dart';
import 'breakpoint/response_breakpoint_dialog.dart';
import 'components/ca_warning_banner.dart';
import 'components/status_bar.dart';
import 'detail/detail_view.dart';
import 'request_list/request_list_view.dart';
import 'settings/settings_view.dart';

class MainWindow extends ConsumerStatefulWidget {
  const MainWindow({super.key});

  @override
  ConsumerState<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends ConsumerState<MainWindow> {
  bool _autoStartDone = false;
  List<String>? _lastDomainRuleIds;
  List<String>? _lastMapLocalRuleKeys;
  List<String>? _lastBreakpointRuleKeys;
  bool? _lastBreakpointEnabled;
  double _listWidth = 630;

  @override
  void initState() {
    super.initState();
    // Handle the rare case where settings load completes before the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(settingsLoadedProvider)) _maybeAutoStart();
    });
  }

  void _maybeAutoStart() {
    if (_autoStartDone) return;
    _autoStartDone = true;
    final settings = ref.read(settingsProvider);
    if (settings.autoStartProxy) {
      ref.read(proxyStateProvider.notifier).start(settings);
    }
  }

  /// Restarts the proxy whenever domain rules change while it's running,
  /// so MITM rules take effect immediately without a manual stop/start.
  void _maybeRestartForRuleChange(ProxySettings settings) {
    // Ignore calls before settings are loaded from disk — the default empty
    // rules would look like a "change" compared to the real saved rules.
    if (!ref.read(settingsLoadedProvider)) return;

    final currentIds =
        settings.domainRules.map((r) => '${r.id}:${r.isEnabled}').toList()
          ..sort();

    final proxyState = ref.read(proxyStateProvider);
    if (proxyState.isRunning &&
        _lastDomainRuleIds != null &&
        !listEquals(_lastDomainRuleIds, currentIds)) {
      final notifier = ref.read(proxyStateProvider.notifier);
      notifier.stop().then((_) => notifier.start(settings));
    }

    _lastDomainRuleIds = currentIds;
  }

  /// Restarts the proxy whenever Map Local rules change while it's running,
  /// so the new rules take effect immediately without a manual stop/start.
  void _maybeRestartForMapLocalChange(List<MapLocalRule> rules) {
    if (!ref.read(mapLocalLoadedProvider)) return;

    final currentKeys = rules.map(_ruleKey).toList()..sort();

    final proxyState = ref.read(proxyStateProvider);
    if (proxyState.isRunning &&
        _lastMapLocalRuleKeys != null &&
        !listEquals(_lastMapLocalRuleKeys, currentKeys)) {
      final notifier = ref.read(proxyStateProvider.notifier);
      final settings = ref.read(settingsProvider);
      notifier.stop().then((_) => notifier.start(settings));
    }

    _lastMapLocalRuleKeys = currentKeys;
  }

  /// Restarts the proxy whenever the breakpoint toggle changes while the
  /// proxy is running, so the feature takes effect immediately.
  void _maybeRestartForBreakpointChange(ProxySettings settings) {
    if (!ref.read(settingsLoadedProvider)) return;
    final proxyState = ref.read(proxyStateProvider);
    if (proxyState.isRunning &&
        _lastBreakpointEnabled != null &&
        _lastBreakpointEnabled != settings.breakpointEnabled) {
      final notifier = ref.read(proxyStateProvider.notifier);
      notifier.stop().then((_) => notifier.start(settings));
    }
    _lastBreakpointEnabled = settings.breakpointEnabled;
  }

  /// Restarts the proxy whenever breakpoint rules change while it's running,
  /// so the new rules take effect immediately.
  void _maybeRestartForBreakpointRuleChange(List<BreakpointRule> rules) {
    if (!ref.read(breakpointRulesLoadedProvider)) return;

    final currentKeys = rules.map(_breakpointRuleKey).toList()..sort();

    final proxyState = ref.read(proxyStateProvider);
    if (proxyState.isRunning &&
        _lastBreakpointRuleKeys != null &&
        !listEquals(_lastBreakpointRuleKeys, currentKeys)) {
      final notifier = ref.read(proxyStateProvider.notifier);
      final settings = ref.read(settingsProvider);
      notifier.stop().then((_) => notifier.start(settings));
    }

    _lastBreakpointRuleKeys = currentKeys;
  }

  static String _breakpointRuleKey(BreakpointRule r) =>
      '${r.id}:${r.isEnabled}:${r.hostPattern}:${r.pathPattern}:'
      '${r.httpMethod}:${r.target.name}';

  static String _ruleKey(MapLocalRule r) =>
      '${r.id}:${r.isEnabled}:${r.hostPattern}:${r.pathPattern}:'
      '${r.httpMethod}:${r.filePath}:${r.statusCode}:${r.contentType}:'
      '${r.isCaseSensitive}:${r.useRegex}:${r.customHeaders}:'
      '${r.responseSource}:${r.inlineBody}';

  void _openSettings() {
    showDialog(
      context: context,
      builder: (_) => const Dialog(
        child: SizedBox(width: 760, height: 560, child: SettingsView()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Auto-start once settings are loaded from disk (ref.listen is valid here).
    ref.listen(settingsLoadedProvider, (_, isLoaded) {
      if (isLoaded) _maybeAutoStart();
    });

    // Mostra il dialog automaticamente a ogni richiesta sospesa e lo lascia
    // chiudere da solo quando la richiesta viene risolta (timeout/decisione).
    // Il defer doppio evita che il dialog del prossimo elemento della coda
    // venga aperto prima che quello corrente si chiuda (RF7.1).
    ref.listen(breakpointProvider, (prev, next) {
      final notification = next.active;
      if (notification == null || notification.id == prev?.active?.id) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final current = ref.read(breakpointProvider).active;
          if (current == null || current.id != notification.id) return;
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => switch (current) {
              RequestBreakpointNotification(:final request) => BreakpointDialog(
                request: request,
              ),
              ResponseBreakpointNotification(:final response) =>
                ResponseBreakpointDialog(response: response),
            },
          );
        });
      });
    });

    final proxyState = ref.watch(proxyStateProvider);
    final filterText = ref.watch(filterTextProvider);
    final exchanges = ref.watch(exchangeListProvider);
    final selectedExchange = ref.watch(selectedExchangeProvider);
    final settings = ref.watch(settingsProvider);
    final mapLocalRules = ref.watch(mapLocalProvider);
    final breakpointRules = ref.watch(breakpointRulesProvider);
    final httpsEnabled = settings.httpsInterceptionEnabled;

    // Restart proxy if domain rules, Map Local rules, HTTPS interception
    // flag, breakpoints toggle or breakpoint rules changed while running
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeRestartForRuleChange(settings),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeRestartForMapLocalChange(mapLocalRules),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeRestartForBreakpointChange(settings),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeRestartForBreakpointRuleChange(breakpointRules),
    );

    return Scaffold(
      appBar: _buildToolbar(
        context,
        proxyState,
        httpsEnabled,
        exchanges.isEmpty,
      ),
      body: Column(
        children: [
          CaWarningBanner(onOpenSettings: _openSettings),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sidebar: request list
                SizedBox(
                  width: _listWidth,
                  child: Column(
                    children: [
                      _SearchBar(
                        text: filterText,
                        onChanged: (v) =>
                            ref.read(filterTextProvider.notifier).state = v,
                      ),
                      const Divider(height: 1),
                      const Expanded(child: RequestListView()),
                    ],
                  ),
                ),
                _PanelDivider(
                  onDelta: (dx) => setState(() {
                    _listWidth = (_listWidth + dx).clamp(300.0, 900.0);
                  }),
                ),
                // Detail pane
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return selectedExchange != null
                          ? DetailView(exchange: selectedExchange)
                          : const _EmptyDetail();
                    },
                  ),
                ),
              ],
            ),
          ),
          const StatusBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildToolbar(
    BuildContext context,
    ProxyState proxyState,
    bool httpsEnabled,
    bool exchangesEmpty,
  ) {
    return AppBar(
      toolbarHeight: 44,
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 12,
      title: const Text(
        'Rox Proxy',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      actions: [
        // Start / Stop
        _ToolbarButton(
          icon: proxyState.isRunning
              ? Icons.stop_circle_outlined
              : Icons.play_circle_outlined,
          label: proxyState.isRunning ? 'Stop' : 'Start',
          color: proxyState.isRunning
              ? const Color(0xFFFF3B30)
              : const Color(0xFF34C759),
          enabled: proxyState is! ProxyStarting,
          onPressed: () {
            if (proxyState.isRunning) {
              ref.read(proxyStateProvider.notifier).stop();
            } else {
              final settings = ref.read(settingsProvider);
              ref.read(proxyStateProvider.notifier).start(settings);
            }
          },
        ),
        const SizedBox(width: 4),
        // HTTPS interception toggle
        _ToolbarButton(
          icon: httpsEnabled ? Icons.lock_outlined : Icons.lock_open_outlined,
          label: httpsEnabled
              ? 'HTTPS interception on'
              : 'HTTPS interception off',
          color: httpsEnabled
              ? const Color(0xFF34C759)
              : const Color(0xFFFF9500),
          onPressed: () {
            final notifier = ref.read(settingsProvider.notifier);
            notifier.setHttpsInterceptionEnabled(!httpsEnabled);
            // Restart proxy immediately if running so the change takes effect
            if (proxyState.isRunning) {
              final settings = ref.read(settingsProvider);
              final ctrl = ref.read(proxyStateProvider.notifier);
              ctrl.stop().then((_) => ctrl.start(settings));
            }
          },
        ),
        const SizedBox(width: 4),
        // Clear
        _ToolbarButton(
          icon: Icons.delete_outline,
          label: 'Clear',
          enabled: !exchangesEmpty,
          onPressed: () => ref.read(exchangeListProvider.notifier).clear(),
        ),
        const SizedBox(width: 4),
        // Settings
        _ToolbarButton(
          icon: Icons.settings_outlined,
          label: 'Settings',
          onPressed: _openSettings,
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Divider(height: 0.5, color: Theme.of(context).dividerColor),
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  final String text;
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.text, required this.onChanged});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Filter requests…',
          hintStyle: const TextStyle(fontSize: 13),
          prefixIcon: const Icon(Icons.search, size: 16),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 14),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool enabled;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: enabled ? effectiveColor : effectiveColor.withAlpha(80),
        onPressed: enabled ? onPressed : null,
        splashRadius: 18,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }
}

// MARK: - Resizable panel divider

class _PanelDivider extends StatefulWidget {
  final ValueChanged<double> onDelta;
  const _PanelDivider({required this.onDelta});

  @override
  State<_PanelDivider> createState() => _PanelDividerState();
}

class _PanelDividerState extends State<_PanelDivider> {
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
          width: 6,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _hovering ? 2 : 1,
              color: _hovering
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)
                  : Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_tethering,
            size: 48,
            color: Colors.grey.withAlpha(100),
          ),
          const SizedBox(height: 12),
          Text(
            'Select a request to inspect',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

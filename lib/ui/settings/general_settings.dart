import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';

class GeneralSettings extends ConsumerStatefulWidget {
  const GeneralSettings({super.key});

  @override
  ConsumerState<GeneralSettings> createState() => _GeneralSettingsState();
}

class _GeneralSettingsState extends ConsumerState<GeneralSettings> {
  late final TextEditingController _portController;
  late final TextEditingController _maxExchangesController;
  late final TextEditingController _timeoutController;
  late final FocusNode _portFocus;
  late final FocusNode _maxExchangesFocus;
  late final FocusNode _timeoutFocus;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _portController = TextEditingController(text: settings.port.toString());
    _maxExchangesController = TextEditingController(
      text: settings.maxExchanges.toString(),
    );
    _timeoutController = TextEditingController(
      text: settings.connectionTimeoutSeconds.toString(),
    );

    _portFocus = FocusNode()
      ..addListener(() {
        if (!_portFocus.hasFocus) _savePort(_portController.text);
      });
    _maxExchangesFocus = FocusNode()
      ..addListener(() {
        if (!_maxExchangesFocus.hasFocus) {
          _saveMaxExchanges(_maxExchangesController.text);
        }
      });
    _timeoutFocus = FocusNode()
      ..addListener(() {
        if (!_timeoutFocus.hasFocus) {
          _saveTimeout(_timeoutController.text);
        }
      });
  }

  void _savePort(String v) {
    final port = int.tryParse(v);
    if (port != null && port > 0 && port < 65536) {
      ref.read(settingsProvider.notifier).setPort(port);
    } else {
      _portController.text = ref.read(settingsProvider).port.toString();
    }
  }

  void _saveMaxExchanges(String v) {
    final n = int.tryParse(v);
    if (n != null && n > 0) {
      ref.read(settingsProvider.notifier).setMaxExchanges(n);
    } else {
      _maxExchangesController.text = ref
          .read(settingsProvider)
          .maxExchanges
          .toString();
    }
  }

  void _saveTimeout(String v) {
    final t = int.tryParse(v);
    if (t != null && t > 0) {
      ref.read(settingsProvider.notifier).setConnectionTimeout(t);
    } else {
      _timeoutController.text = ref
          .read(settingsProvider)
          .connectionTimeoutSeconds
          .toString();
    }
  }

  @override
  void dispose() {
    _portController.dispose();
    _maxExchangesController.dispose();
    _timeoutController.dispose();
    _portFocus.dispose();
    _maxExchangesFocus.dispose();
    _timeoutFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionLabel('Proxy'),
        _FormRow(
          label: 'Port',
          child: SizedBox(
            width: 100,
            child: TextField(
              controller: _portController,
              focusNode: _portFocus,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 13),
              decoration: _inputDecoration(),
              onSubmitted: _savePort,
            ),
          ),
        ),
        _FormRow(
          label: 'Auto-start on launch',
          child: Switch(
            value: settings.autoStartProxy,
            onChanged: notifier.setAutoStartProxy,
          ),
        ),
        _FormRow(
          label: 'Configure macOS system proxy',
          child: Switch(
            value: settings.setSystemProxy,
            onChanged: notifier.setSetSystemProxy,
          ),
        ),
        _FormRow(
          label: 'Breakpoints',
          child: Switch(
            value: settings.breakpointEnabled,
            onChanged: notifier.setBreakpointEnabled,
          ),
        ),
        _FormRow(
          label: 'Connection timeout (seconds)',
          child: SizedBox(
            width: 100,
            child: TextField(
              controller: _timeoutController,
              focusNode: _timeoutFocus,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 13),
              decoration: _inputDecoration(),
              onSubmitted: _saveTimeout,
            ),
          ),
        ),
        const Divider(height: 24),
        _SectionLabel('Traffic'),
        _FormRow(
          label: 'Max captured exchanges',
          child: SizedBox(
            width: 100,
            child: TextField(
              controller: _maxExchangesController,
              focusNode: _maxExchangesFocus,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 13),
              decoration: _inputDecoration(),
              onSubmitted: _saveMaxExchanges,
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration _inputDecoration() => InputDecoration(
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
);

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _FormRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          child,
        ],
      ),
    );
  }
}

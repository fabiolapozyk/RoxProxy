import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/breakpoint.dart';
import '../../providers/settings_provider.dart';

class BreakpointListView extends ConsumerWidget {
  const BreakpointListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final breakpoints = settings.breakpoints;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Breakpoints',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add URLs to intercept and modify requests/responses',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              _AddBreakpointForm(
                onAdd: (urlPattern, trigger) {
                  notifier.addBreakpoint(urlPattern, trigger);
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: breakpoints.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'No breakpoints configured',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: breakpoints.length,
                  itemBuilder: (context, index) {
                    final breakpoint = breakpoints[index];
                    return _BreakpointItem(
                      breakpoint: breakpoint,
                      onToggle: () => notifier.toggleBreakpoint(breakpoint.id),
                      onRemove: () => notifier.removeBreakpoint(breakpoint.id),
                      onTriggerChange: (trigger) => notifier.updateBreakpointTrigger(breakpoint.id, trigger),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AddBreakpointForm extends StatefulWidget {
  final Function(String urlPattern, BreakpointTrigger trigger) onAdd;

  const _AddBreakpointForm({required this.onAdd});

  @override
  State<_AddBreakpointForm> createState() => _AddBreakpointFormState();
}

class _AddBreakpointFormState extends State<_AddBreakpointForm> {
  final _controller = TextEditingController();
  BreakpointTrigger _selectedTrigger = BreakpointTrigger.both;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addBreakpoint() {
    final urlPattern = _controller.text.trim();
    if (urlPattern.isEmpty) return;
    widget.onAdd(urlPattern, _selectedTrigger);
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: 'Enter URL pattern (e.g., https://api.example.com/data)',
            hintStyle: const TextStyle(fontSize: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.add, size: 20),
              onPressed: _addBreakpoint,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ),
          style: const TextStyle(fontSize: 13),
          onSubmitted: (_) => _addBreakpoint(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Trigger:', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            _buildTriggerChip(BreakpointTrigger.request, 'Request'),
            const SizedBox(width: 4),
            _buildTriggerChip(BreakpointTrigger.response, 'Response'),
            const SizedBox(width: 4),
            _buildTriggerChip(BreakpointTrigger.both, 'Both'),
          ],
        ),
      ],
    );
  }

  Widget _buildTriggerChip(BreakpointTrigger trigger, String label) {
    final isSelected = _selectedTrigger == trigger;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedTrigger = trigger);
        }
      },
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      labelPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _BreakpointItem extends StatelessWidget {
  final Breakpoint breakpoint;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  final Function(BreakpointTrigger) onTriggerChange;

  const _BreakpointItem({
    required this.breakpoint,
    required this.onToggle,
    required this.onRemove,
    required this.onTriggerChange,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        breakpoint.urlPattern,
        style: const TextStyle(fontSize: 13),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Text(
            'Trigger: ${_triggerLabel(breakpoint.trigger)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 8),
          if (!breakpoint.isEnabled)
            Text(
              'Disabled',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              breakpoint.isEnabled ? Icons.pause_circle_outline : Icons.play_circle_outline,
              size: 18,
            ),
            tooltip: breakpoint.isEnabled ? 'Disable breakpoint' : 'Enable breakpoint',
            onPressed: onToggle,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Remove breakpoint',
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
      onTap: () {
        // Could show edit dialog in future
      },
    );
  }

  String _triggerLabel(BreakpointTrigger trigger) {
    return switch (trigger) {
      BreakpointTrigger.request => 'Request',
      BreakpointTrigger.response => 'Response',
      BreakpointTrigger.both => 'Both',
    };
  }
}
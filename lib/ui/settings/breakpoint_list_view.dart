import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/breakpoint_rule.dart';
import '../../providers/breakpoint_provider.dart';

class BreakpointListView extends ConsumerStatefulWidget {
  const BreakpointListView({super.key});

  @override
  ConsumerState<BreakpointListView> createState() => _BreakpointListViewState();
}

class _BreakpointListViewState extends ConsumerState<BreakpointListView> {
  final _urlController = TextEditingController();
  bool _interceptRequest = true;
  bool _interceptResponse = true;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _addRule() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    
    final rule = BreakpointRule(
      urlPattern: url,
      interceptRequest: _interceptRequest,
      interceptResponse: _interceptResponse,
    );
    
    ref.read(breakpointProvider.notifier).addRule(rule);
    _urlController.clear();
    setState(() {
      _interceptRequest = true;
      _interceptResponse = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(breakpointProvider);
    final notifier = ref.read(breakpointProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _urlController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'example.com or *.example.com or example.com/*',
                  hintStyle: const TextStyle(fontSize: 13),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                onSubmitted: (_) => _addRule(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _interceptRequest,
                    onChanged: (value) => setState(() => _interceptRequest = value ?? true),
                  ),
                  const Text('Intercept Request', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 16),
                  Checkbox(
                    value: _interceptResponse,
                    onChanged: (value) => setState(() => _interceptResponse = value ?? true),
                  ),
                  const Text('Intercept Response', style: TextStyle(fontSize: 13)),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _addRule,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: rules.isEmpty
              ? const Center(
                  child: Text(
                    'No breakpoints configured.\nAdd URL patterns to intercept requests/responses.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  itemCount: rules.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final rule = rules[i];
                    return ListTile(
                      dense: true,
                      leading: Checkbox(
                        value: rule.isEnabled,
                        onChanged: (_) => notifier.toggleRule(rule.id),
                      ),
                      title: Text(
                        rule.urlPattern,
                        style: TextStyle(
                          fontSize: 13,
                          color: rule.isEnabled
                              ? null
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withAlpha(100),
                        ),
                      ),
                      subtitle: Text(
                        '${rule.interceptRequest ? "Req" : ""}${rule.interceptRequest && rule.interceptResponse ? "/" : ""}${rule.interceptResponse ? "Res" : ""}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => notifier.removeRule(rule.id),
                        tooltip: 'Remove',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

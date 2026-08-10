import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';

class DomainListView extends ConsumerStatefulWidget {
  const DomainListView({super.key});

  @override
  ConsumerState<DomainListView> createState() => _DomainListViewState();
}

class _DomainListViewState extends ConsumerState<DomainListView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(settingsProvider.notifier).addDomain(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(settingsProvider).domainRules;
    final notifier = ref.read(settingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'example.com or *.example.com',
                    hintStyle: const TextStyle(fontSize: 13),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _add,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 13),
                ),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: rules.isEmpty
              ? const Center(
                  child: Text(
                    'No HTTPS domains configured.\nAdd domains to enable MITM interception.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  itemCount: rules.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final rule = rules[i];
                    return ListTile(
                      dense: true,
                      leading: Checkbox(
                        value: rule.isEnabled,
                        onChanged: (_) => notifier.toggleDomain(rule.id),
                      ),
                      title: Text(
                        rule.domain,
                        style: TextStyle(
                          fontSize: 13,
                          color: rule.isEnabled
                              ? null
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(100),
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => notifier.removeDomain(rule.id),
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

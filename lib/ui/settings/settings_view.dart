import 'package:flutter/material.dart';

import '../map_local/map_local_panel.dart';
import 'certificate_setup_view.dart';
import 'domain_list_view.dart';
import 'general_settings.dart';

/// Settings window with a macOS-style sidebar navigation.
/// Each future feature gets a new section here instead of a toolbar icon.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  int _selectedIndex = 0;

  static const _sections = [
    (icon: Icons.settings_outlined, label: 'General'),
    (icon: Icons.lock_outlined, label: 'HTTPS Domains'),
    (icon: Icons.verified_user_outlined, label: 'Certificate'),
    (icon: Icons.source_outlined, label: 'Map Local'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(onClose: () => Navigator.of(context).pop()),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sidebar
              Container(
                width: 180,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: ListView.builder(
                  itemCount: _sections.length,
                  itemBuilder: (context, i) {
                    final section = _sections[i];
                    final selected = i == _selectedIndex;
                    return ListTile(
                      dense: true,
                      leading: Icon(section.icon, size: 18),
                      title: Text(
                        section.label,
                        style: const TextStyle(fontSize: 13),
                      ),
                      selected: selected,
                      selectedTileColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withAlpha(140),
                      onTap: () => setState(() => _selectedIndex = i),
                    );
                  },
                ),
              ),
              const VerticalDivider(width: 1),
              // Content
              Expanded(
                child: switch (_selectedIndex) {
                  0 => const GeneralSettings(),
                  1 => const DomainListView(),
                  2 => const CertificateSetupView(),
                  _ => const MapLocalRuleManager(),
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Text(
            'Settings',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

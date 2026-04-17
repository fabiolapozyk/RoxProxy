import 'package:flutter/material.dart';

import 'certificate_setup_view.dart';
import 'domain_list_view.dart';
import 'general_settings.dart';
import 'breakpoint_list_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(onClose: () => Navigator.of(context).pop()),
        const Divider(height: 1),
        TabBar(
          controller: _tabController,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: 'General'),
            Tab(text: 'HTTPS Domains'),
            Tab(text: 'Breakpoints'),
            Tab(text: 'Certificate'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              GeneralSettings(),
              DomainListView(),
              BreakpointListView(),
              CertificateSetupView(),
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

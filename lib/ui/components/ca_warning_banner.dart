import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/certificate_provider.dart';
import '../../providers/settings_provider.dart';

class CaWarningBanner extends ConsumerWidget {
  final VoidCallback onOpenSettings;

  const CaWarningBanner({super.key, required this.onOpenSettings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caState = ref.watch(caTrustProvider);
    final settings = ref.watch(settingsProvider);
    final hasDomainRules = settings.domainRules.any((r) => r.isEnabled);

    // Only show when there are MITM rules enabled but CA is not trusted
    if (caState.trusted || !hasDomainRules) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFFF9500).withAlpha(30),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFFF9500),
            size: 16,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'CA certificate not installed. HTTPS interception will not work.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onOpenSettings,
            child: const Text('Open Settings', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

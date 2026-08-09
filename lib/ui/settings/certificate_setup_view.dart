import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/certificate_provider.dart';
import '../../providers/settings_provider.dart';

class CertificateSetupView extends ConsumerWidget {
  const CertificateSetupView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ca = ref.watch(caTrustProvider);
    final notifier = ref.read(caTrustProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ca.trusted
                    ? Icons.verified_user_outlined
                    : Icons.gpp_bad_outlined,
                size: 20,
                color: ca.trusted
                    ? const Color(0xFF34C759)
                    : const Color(0xFFFF3B30),
              ),
              const SizedBox(width: 8),
              Text(
                ca.trusted
                    ? 'CA certificate is trusted'
                    : 'CA certificate is not trusted',
                style: TextStyle(
                  fontSize: 13,
                  color: ca.trusted
                      ? const Color(0xFF34C759)
                      : const Color(0xFFFF3B30),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                tooltip: 'Refresh',
                onPressed: notifier.refresh,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'To intercept HTTPS traffic, Rox Proxy needs its CA certificate '
            'to be trusted by macOS. Click the button below to install and '
            'trust the certificate (requires your admin password).',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),
          if (ca.installError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                ca.installError!,
                style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 12),
              ),
            ),
          FilledButton.icon(
            onPressed: ca.isInstalling ? null : notifier.install,
            icon: ca.isInstalling
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined, size: 16),
            label: Text(
              ca.trusted
                  ? 'Reinstall CA Certificate'
                  : 'Install & Trust CA Certificate',
            ),
            style: FilledButton.styleFrom(
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.phone_android_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Mobile / LAN devices',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'To intercept traffic from another device on the same network:',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 10),
          _LanInstructions(),
        ],
      ),
    );
  }
}

class _LanInstructions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final port = ref.watch(settingsProvider.select((s) => s.port));

    return FutureBuilder<String>(
      future: _getLanIp(),
      builder: (context, snapshot) {
        final ip = snapshot.data ?? '…';
        final proxyAddress = '$ip:$port';
        const certUrl = 'http://cert.roxproxy/';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InstructionStep(
              number: '1',
              text: 'Configure the device to use this Mac as HTTP/HTTPS proxy:',
              trailing: _CopyableChip(value: proxyAddress),
            ),
            const SizedBox(height: 8),
            _InstructionStep(
              number: '2',
              text:
                  'Open the browser on the device and navigate to the cert URL:',
              trailing: _CopyableChip(value: certUrl),
            ),
            const SizedBox(height: 8),
            const _InstructionStep(
              number: '3',
              text:
                  'Download and install the certificate, then trust it in '
                  'the device settings.',
            ),
          ],
        );
      },
    );
  }

  Future<String> _getLanIp() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return 'localhost';
  }
}

class _InstructionStep extends StatelessWidget {
  final String number;
  final String text;
  final Widget? trailing;

  const _InstructionStep({
    required this.number,
    required this.text,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 1, right: 8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.secondaryContainer,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
              if (trailing != null) ...[const SizedBox(height: 4), trailing!],
            ],
          ),
        ),
      ],
    );
  }
}

class _CopyableChip extends StatefulWidget {
  final String value;
  const _CopyableChip({required this.value});

  @override
  State<_CopyableChip> createState() => _CopyableChipState();
}

class _CopyableChipState extends State<_CopyableChip> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: widget.value));
          setState(() => _copied = true);
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) setState(() => _copied = false);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.value,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(width: 6),
              Icon(
                _copied ? Icons.check : Icons.copy_outlined,
                size: 12,
                color: _copied
                    ? const Color(0xFF34C759)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

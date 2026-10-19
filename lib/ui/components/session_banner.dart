import 'package:flutter/material.dart';

/// Shown while an offline session (opened from a HAR file) is displayed, so it
/// is clear that the view is read-only and the proxy keeps running.
class SessionBanner extends StatelessWidget {
  final String fileName;
  final int requestCount;
  final VoidCallback onClose;

  const SessionBanner({
    super.key,
    required this.fileName,
    required this.requestCount,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF007AFF);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: accent.withAlpha(30),
      child: Row(
        children: [
          const Icon(Icons.history_edu_outlined, color: accent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline session (read-only): $fileName '
              '· $requestCount requests',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onClose,
            child: const Text('Back to live', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Placeholder shown in the detail pane when no exchange is selected.
class EmptyDetail extends StatelessWidget {
  const EmptyDetail({super.key});

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

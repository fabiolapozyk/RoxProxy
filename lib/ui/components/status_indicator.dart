import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/captured_exchange.dart';

class StatusIndicator extends StatelessWidget {
  final int? statusCode;
  final ExchangeState state;

  const StatusIndicator({
    super.key,
    required this.statusCode,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    if (state == ExchangeState.inProgress) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CupertinoActivityIndicator(radius: 7),
      );
    }
    if (state == ExchangeState.failed) {
      return const Icon(
        Icons.error_outline,
        size: 14,
        color: Color(0xFFFF3B30),
      );
    }
    if (statusCode == null) return const SizedBox(width: 40);

    final code = statusCode!;
    return Text(
      '$code',
      style: TextStyle(
        color: _color(code),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Color _color(int code) {
    if (code < 300) return const Color(0xFF34C759);
    if (code < 400) return const Color(0xFF007AFF);
    if (code < 500) return const Color(0xFFFF9500);
    return const Color(0xFFFF3B30);
  }
}

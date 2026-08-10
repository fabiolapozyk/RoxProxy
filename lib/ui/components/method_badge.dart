import 'package:flutter/material.dart';

class MethodBadge extends StatelessWidget {
  final String method;

  const MethodBadge(this.method, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color(method).withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color(method).withAlpha(80)),
      ),
      child: Text(
        method,
        style: TextStyle(
          color: _color(method),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Color _color(String m) => switch (m.toUpperCase()) {
    'GET' => const Color(0xFF34C759),
    'POST' => const Color(0xFF007AFF),
    'PUT' => const Color(0xFFFF9500),
    'PATCH' => const Color(0xFFAF52DE),
    'DELETE' => const Color(0xFFFF3B30),
    'HEAD' => const Color(0xFF5AC8FA),
    'OPTIONS' => const Color(0xFF636366),
    'CONNECT' => const Color(0xFF8E8E93),
    _ => const Color(0xFF8E8E93),
  };
}

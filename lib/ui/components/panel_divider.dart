import 'package:flutter/material.dart';

/// Draggable vertical divider between the request list and the detail pane.
class PanelDivider extends StatefulWidget {
  final ValueChanged<double> onDelta;

  const PanelDivider({super.key, required this.onDelta});

  @override
  State<PanelDivider> createState() => _PanelDividerState();
}

class _PanelDividerState extends State<PanelDivider> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onDelta(d.delta.dx),
        child: SizedBox(
          width: 6,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _hovering ? 2 : 1,
              color: _hovering
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)
                  : Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

/// Stateful wrapper that auto-hides revealed sensitive content after a
/// short window. Built around an [AnimationController] so the
/// countdown ring stays in sync with the timer with no jitter.
///
/// Usage:
///   RevealHold(
///     duration: const Duration(seconds: 15),
///     onAutoHide: () => setState(() => _showPassword = false),
///   )
///
/// We don't manage the "is revealed" boolean — the caller does, because
/// it's usually one of several pieces of state. We just notify when the
/// window expires so the caller can flip its own flag back.
class RevealHold extends StatefulWidget {
  const RevealHold({
    super.key,
    required this.duration,
    required this.onAutoHide,
    this.size = 18,
    this.color,
  });

  final Duration duration;
  final VoidCallback onAutoHide;
  final double size;
  final Color? color;

  @override
  State<RevealHold> createState() => _RevealHoldState();
}

class _RevealHoldState extends State<RevealHold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..addStatusListener(_onStatus);

  @override
  void initState() {
    super.initState();
    // Drive 0 → 1 once. The animation reaches "completed" exactly when
    // the timer expires, so the visual ring and the actual hide are
    // pixel-aligned.
    _ctrl.forward();
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && mounted) {
      // One frame after completion is enough to let the ring render at
      // 100% before the parent rebuilds with the password hidden.
      scheduleMicrotask(widget.onAutoHide);
    }
  }

  @override
  void dispose() {
    _ctrl
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: 'Auto-hides in ${widget.duration.inSeconds}s',
      child: SizedBox(
        width: widget.size + 8,
        height: widget.size + 8,
        child: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final remaining = (1 - _ctrl.value).clamp(0.0, 1.0);
              return SizedBox(
                width: widget.size,
                height: widget.size,
                child: CircularProgressIndicator(
                  value: remaining,
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  backgroundColor: color.withValues(alpha: 0.18),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

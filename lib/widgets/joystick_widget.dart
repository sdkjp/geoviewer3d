import 'dart:async';
import 'package:flutter/material.dart';

/// ゲームコントローラ風ジョイスティック
/// ドラッグ量を -1.0 〜 1.0 に正規化してコールバックに渡す
class JoystickWidget extends StatefulWidget {
  final void Function(double dx, double dy) onMove;
  final void Function()? onRelease;
  final double size;
  final Color baseColor;
  final Color knobColor;
  final String? label;

  const JoystickWidget({
    super.key,
    required this.onMove,
    this.onRelease,
    this.size = 100,
    this.baseColor = const Color(0x66FFFFFF),
    this.knobColor = const Color(0xCCFFFFFF),
    this.label,
  });

  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  Offset _knobOffset = Offset.zero;
  Timer? _repeatTimer;
  double _dx = 0, _dy = 0;

  void _startRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_dx != 0 || _dy != 0) {
        widget.onMove(_dx, _dy);
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final half = widget.size / 2 - 20;
    final raw = _knobOffset + d.delta;
    final clamped = Offset(
      raw.dx.clamp(-half, half),
      raw.dy.clamp(-half, half),
    );
    setState(() => _knobOffset = clamped);
    _dx = clamped.dx / half;
    _dy = clamped.dy / half;
    widget.onMove(_dx, _dy);
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() => _knobOffset = Offset.zero);
    _dx = 0;
    _dy = 0;
    _repeatTimer?.cancel();
    widget.onRelease?.call();
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Text(widget.label!,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 10)),
        GestureDetector(
          onPanStart: (_) => _startRepeat(),
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: SizedBox(
            width: s,
            height: s,
            child: CustomPaint(
              painter: _JoystickPainter(
                  _knobOffset, widget.baseColor, widget.knobColor),
            ),
          ),
        ),
      ],
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset knobOffset;
  final Color baseColor;
  final Color knobColor;

  _JoystickPainter(this.knobOffset, this.baseColor, this.knobColor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;
    final knobRadius = baseRadius * 0.38;

    // 外輪
    canvas.drawCircle(center, baseRadius - 4,
        Paint()
          ..color = baseColor
          ..style = PaintingStyle.fill);
    canvas.drawCircle(center, baseRadius - 4,
        Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // 方向線
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 1;
    canvas.drawLine(center + Offset(0, -baseRadius + 12),
        center + Offset(0, baseRadius - 12), linePaint);
    canvas.drawLine(center + Offset(-baseRadius + 12, 0),
        center + Offset(baseRadius - 12, 0), linePaint);

    // ノブ
    final knobCenter = center + knobOffset;
    canvas.drawCircle(knobCenter, knobRadius,
        Paint()
          ..color = knobColor
          ..style = PaintingStyle.fill);
    canvas.drawCircle(knobCenter, knobRadius,
        Paint()
          ..color = Colors.white.withOpacity(0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_JoystickPainter old) =>
      old.knobOffset != knobOffset;
}

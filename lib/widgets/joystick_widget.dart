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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xCC1B3A6B),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: Text(widget.label!,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ),
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

    // ドロップシャドウ
    canvas.drawCircle(
      center + const Offset(0, 3),
      baseRadius - 4,
      Paint()
        ..color = Colors.black.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // 外輪（塗り）
    canvas.drawCircle(center, baseRadius - 4,
        Paint()
          ..color = baseColor
          ..style = PaintingStyle.fill);

    // 外輪（ボーダー: テーマカラー薄め）
    canvas.drawCircle(center, baseRadius - 4,
        Paint()
          ..color = knobColor.withOpacity(0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // 十字ガイド線
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 1;
    canvas.drawLine(center + Offset(0, -baseRadius + 14),
        center + Offset(0, baseRadius - 14), linePaint);
    canvas.drawLine(center + Offset(-baseRadius + 14, 0),
        center + Offset(baseRadius - 14, 0), linePaint);

    // ノブ（塗り + グラデーション風）
    final knobCenter = center + knobOffset;
    canvas.drawCircle(knobCenter, knobRadius,
        Paint()
          ..color = knobColor
          ..style = PaintingStyle.fill);
    // ノブ内部の白いハイライト
    canvas.drawCircle(
      knobCenter + Offset(-knobRadius * 0.2, -knobRadius * 0.2),
      knobRadius * 0.35,
      Paint()
        ..color = Colors.white.withOpacity(0.35)
        ..style = PaintingStyle.fill,
    );
    // ノブ外枠
    canvas.drawCircle(knobCenter, knobRadius,
        Paint()
          ..color = Colors.white.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_JoystickPainter old) =>
      old.knobOffset != knobOffset;
}

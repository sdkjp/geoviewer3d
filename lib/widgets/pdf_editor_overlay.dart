import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/cesium_bridge.dart';

/// PowerPoint 風 PDF エディタ
/// - 初期化時に Cesium カメラ操作を無効化
/// - dispose 時に再有効化
/// - ドラッグはハンドルのみ（地図は動かない）
/// - 座標変換は Cesium の ray picking を使用
class PdfEditorOverlay extends StatefulWidget {
  final String layerId;
  final double initialCenterLon;
  final double initialCenterLat;
  final double initialWidthM;
  final double initialHeightM;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const PdfEditorOverlay({
    super.key,
    required this.layerId,
    required this.initialCenterLon,
    required this.initialCenterLat,
    required this.initialWidthM,
    required this.initialHeightM,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<PdfEditorOverlay> createState() => _PdfEditorOverlayState();
}

class _PdfEditorOverlayState extends State<PdfEditorOverlay> {
  late double _centerLon;
  late double _centerLat;
  late double _widthM;
  late double _heightM;
  double _rotDeg = 0;
  double _alpha  = 0.7;

  List<Map<String, double>?> _handles = [];
  Timer? _pollTimer;

  // ドラッグ状態
  _DragType? _dragging;
  // ドラッグ開始時のジオ座標 (ray picking)
  double _dragStartGeoLon = 0, _dragStartGeoLat = 0;
  double _dragStartCenterLon = 0, _dragStartCenterLat = 0;
  double _dragStartW = 0, _dragStartH = 0, _dragStartRot = 0;
  Offset _dragStartScreen = Offset.zero;
  // 拡縮時の基準 (反対角コーナーのジオ座標)
  double _anchorLon = 0, _anchorLat = 0;

  @override
  void initState() {
    super.initState();
    _centerLon = widget.initialCenterLon;
    _centerLat = widget.initialCenterLat;
    _widthM    = widget.initialWidthM;
    _heightM   = widget.initialHeightM;

    // 地図カメラを無効化（地図が動かないように）
    CesiumBridge.disableCameraControls();

    // ハンドル座標を 50ms ごとに更新
    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final h = CesiumBridge.getPdfScreenHandles(widget.layerId);
      if (h != null && mounted) setState(() => _handles = h);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    // カメラ操作を復元
    CesiumBridge.enableCameraControls();
    super.dispose();
  }

  // ─── Cesium に変換を送信 ───
  void _pushTransform() {
    CesiumBridge.updatePdfTransform(widget.layerId,
        centerLon: _centerLon, centerLat: _centerLat,
        widthM: _widthM, heightM: _heightM,
        rotDeg: _rotDeg, alpha: _alpha);
  }

  // ─── ドラッグ開始 ───
  void _onHandlePanStart(DragStartDetails d, _DragType type) {
    _dragging = type;
    _dragStartScreen = d.globalPosition;
    _dragStartCenterLon = _centerLon;
    _dragStartCenterLat = _centerLat;
    _dragStartW   = _widthM;
    _dragStartH   = _heightM;
    _dragStartRot = _rotDeg;

    // ray picking でドラッグ開始地点のジオ座標を取得
    final geo = CesiumBridge.screenToGeo(d.globalPosition.dx, d.globalPosition.dy);
    if (geo != null) {
      _dragStartGeoLon = geo['lon']!;
      _dragStartGeoLat = geo['lat']!;
    }

    // 拡縮の場合: 反対角の地理座標を固定アンカーとして保存
    if (type == _DragType.scaleCornerTL && _handles.length >= 3 && _handles[2] != null) {
      final g = CesiumBridge.screenToGeo(_handles[2]!['x']!, _handles[2]!['y']!);
      _anchorLon = g?['lon'] ?? _centerLon;
      _anchorLat = g?['lat'] ?? _centerLat;
    } else if (type == _DragType.scaleCornerTR && _handles.length >= 4 && _handles[3] != null) {
      final g = CesiumBridge.screenToGeo(_handles[3]!['x']!, _handles[3]!['y']!);
      _anchorLon = g?['lon'] ?? _centerLon;
      _anchorLat = g?['lat'] ?? _centerLat;
    } else if (type == _DragType.scaleCornerBR && _handles.isNotEmpty && _handles[0] != null) {
      final g = CesiumBridge.screenToGeo(_handles[0]!['x']!, _handles[0]!['y']!);
      _anchorLon = g?['lon'] ?? _centerLon;
      _anchorLat = g?['lat'] ?? _centerLat;
    } else if (type == _DragType.scaleCornerBL && _handles.length >= 2 && _handles[1] != null) {
      final g = CesiumBridge.screenToGeo(_handles[1]!['x']!, _handles[1]!['y']!);
      _anchorLon = g?['lon'] ?? _centerLon;
      _anchorLat = g?['lat'] ?? _centerLat;
    }
  }

  // ─── ドラッグ更新 ───
  void _onHandlePanUpdate(DragUpdateDetails d) {
    if (_dragging == null) return;

    // 現在のスクリーン位置のジオ座標
    final geo = CesiumBridge.screenToGeo(d.globalPosition.dx, d.globalPosition.dy);
    if (geo == null) return;
    final curLon = geo['lon']!;
    final curLat = geo['lat']!;

    // スクリーン差分
    final dsx = d.globalPosition.dx - _dragStartScreen.dx;
    final dsy = d.globalPosition.dy - _dragStartScreen.dy;

    switch (_dragging!) {
      case _DragType.move:
        // ジオ差分をそのまま適用（ドラッグ開始点からの地理差分で移動）
        final dLon = curLon - _dragStartGeoLon;
        final dLat = curLat - _dragStartGeoLat;
        _centerLon = _dragStartCenterLon + dLon;
        _centerLat = _dragStartCenterLat + dLat;
        break;

      case _DragType.rotate:
        // 中心からの角度変化
        if (_handles.length > 4 && _handles[4] != null) {
          final cx = _handles[4]!['x']!;
          final cy = _handles[4]!['y']!;
          final startAngle = atan2(_dragStartScreen.dy - cy, _dragStartScreen.dx - cx);
          final curAngle   = atan2(d.globalPosition.dy - cy, d.globalPosition.dx - cx);
          _rotDeg = (_dragStartRot + (curAngle - startAngle) * 180 / pi) % 360;
        }
        break;

      case _DragType.scaleCornerTL:
      case _DragType.scaleCornerTR:
      case _DragType.scaleCornerBR:
      case _DragType.scaleCornerBL:
        // アンカーコーナーと現在コーナーの地理距離からサイズ計算
        final dLon = (curLon - _anchorLon).abs();
        final dLat = (curLat - _anchorLat).abs();
        final cosLat = cos(_centerLat * pi / 180);
        final newW = (dLon * 111320 * cosLat * 2).clamp(10, 50000).toDouble();
        final newH = (dLat * 110540 * 2).clamp(10, 50000).toDouble();
        if (newW > 10) _widthM  = newW;
        if (newH > 10) _heightM = newH;
        // 中心 = アンカー + 現在コーナーの中点
        _centerLon = (_anchorLon + curLon) / 2;
        _centerLat = (_anchorLat + curLat) / 2;
        break;
    }

    _pushTransform();
  }

  void _onHandlePanEnd(DragEndDetails _) => setState(() => _dragging = null);

  // ─── ビルド ───
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ────────────────────────────
        // PDF アウトライン描画
        // ────────────────────────────
        if (_handles.length >= 5)
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _PdfOutlinePainter(_handles, _rotDeg),
            ),
          ),

        // ────────────────────────────
        // ハンドルウィジェット
        // ────────────────────────────
        if (_handles.length >= 5) ...[
          // 中心 (移動)
          _handle(4, _DragType.move, Colors.white,       Icons.open_with, SystemMouseCursors.move),
          // 4コーナー (拡縮)
          _handle(0, _DragType.scaleCornerTL, Colors.white, null, SystemMouseCursors.resizeUpLeftDownRight),
          _handle(1, _DragType.scaleCornerTR, Colors.white, null, SystemMouseCursors.resizeUpRightDownLeft),
          _handle(2, _DragType.scaleCornerBR, Colors.white, null, SystemMouseCursors.resizeUpLeftDownRight),
          _handle(3, _DragType.scaleCornerBL, Colors.white, null, SystemMouseCursors.resizeUpRightDownLeft),
          // 回転ハンドル（上辺中点の外側）
          _rotationHandle(),
        ],

        // ────────────────────────────
        // 下部コントロールバー
        // ────────────────────────────
        _controlBar(),
      ],
    );
  }

  Widget _handle(int idx, _DragType type, Color color, IconData? icon, MouseCursor cursor) {
    if (idx >= _handles.length || _handles[idx] == null) return const SizedBox();
    final x = _handles[idx]!['x']!;
    final y = _handles[idx]!['y']!;
    const sz = 26.0;
    return Positioned(
      left: x - sz / 2,
      top:  y - sz / 2,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          onPanStart: (d) => _onHandlePanStart(d, type),
          onPanUpdate: _onHandlePanUpdate,
          onPanEnd: _onHandlePanEnd,
          behavior: HitTestBehavior.opaque,
          child: _HandleDot(size: sz, color: color, icon: icon,
              isCircle: icon != null || type == _DragType.move),
        ),
      ),
    );
  }

  Widget _rotationHandle() {
    if (_handles.length < 2 || _handles[0] == null || _handles[1] == null) return const SizedBox();
    final tx = (_handles[0]!['x']! + _handles[1]!['x']!) / 2;
    final ty = (_handles[0]!['y']! + _handles[1]!['y']!) / 2;
    // 上辺の外側 (回転に応じた法線方向)
    final rot = _rotDeg * pi / 180;
    const dist = 44.0;
    final nx = -sin(rot) * dist;
    final ny = -cos(rot) * dist;
    const sz = 28.0;
    return Positioned(
      left: tx + nx - sz / 2,
      top:  ty + ny - sz / 2,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          onPanStart: (d) => _onHandlePanStart(d, _DragType.rotate),
          onPanUpdate: _onHandlePanUpdate,
          onPanEnd: _onHandlePanEnd,
          behavior: HitTestBehavior.opaque,
          child: const _HandleDot(
              size: sz, color: Color(0xFF2ECC71),
              icon: Icons.rotate_right, isCircle: true),
        ),
      ),
    );
  }

  Widget _controlBar() {
    return Positioned(
      bottom: 110,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xF01B3A6B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A5298)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 16)],
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 透明度
              const Icon(Icons.opacity, color: Colors.white70, size: 16),
              SizedBox(
                width: 120,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbColor: Colors.white,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _alpha, min: 0.1, max: 1.0,
                    onChanged: (v) { setState(() => _alpha = v); _pushTransform(); },
                  ),
                ),
              ),
              Text('${(_alpha * 100).round()}%',
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
              // 回転角
              const Icon(Icons.rotate_right, color: Colors.white70, size: 16),
              Text('${_rotDeg.toStringAsFixed(1)}°',
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
              // 回転リセット
              _Btn(icon: Icons.north, label: '0°リセット',
                  onTap: () { setState(() => _rotDeg = 0); _pushTransform(); }),
              // キャンセル
              _Btn(icon: Icons.close, label: 'キャンセル',
                  color: Colors.red.shade300, onTap: widget.onCancel),
              // 確定
              _Btn(icon: Icons.check, label: '配置確定',
                  color: const Color(0xFF2ECC71), onTap: widget.onConfirm),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── ハンドル種別 ───
enum _DragType { move, rotate, scaleCornerTL, scaleCornerTR, scaleCornerBR, scaleCornerBL }

// ─── ハンドルドット ───
class _HandleDot extends StatelessWidget {
  final double size;
  final Color color;
  final IconData? icon;
  final bool isCircle;
  const _HandleDot({required this.size, required this.color, this.icon, required this.isCircle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: color,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(5),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: icon != null
          ? Icon(icon, size: size * 0.55, color: Colors.white)
          : null,
    );
  }
}

// ─── アウトラインペインター ───
class _PdfOutlinePainter extends CustomPainter {
  final List<Map<String, double>?> handles;
  final double rotDeg;
  const _PdfOutlinePainter(this.handles, this.rotDeg);

  @override
  void paint(Canvas canvas, Size size) {
    if (handles.length < 4) return;
    final pts = handles.take(4).map((h) {
      if (h == null) return null;
      return Offset(h['x']!, h['y']!);
    }).toList();
    if (pts.any((p) => p == null)) return;

    final path = Path()
      ..moveTo(pts[0]!.dx, pts[0]!.dy)
      ..lineTo(pts[1]!.dx, pts[1]!.dy)
      ..lineTo(pts[2]!.dx, pts[2]!.dy)
      ..lineTo(pts[3]!.dx, pts[3]!.dy)
      ..close();

    // 影
    canvas.drawPath(path, Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    // 外枠
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF1B3A6B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
    // 細破線
    canvas.drawPath(path, Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);

    // 回転ハンドルへの線
    if (handles.length >= 2 && handles[0] != null && handles[1] != null) {
      final tx = (handles[0]!['x']! + handles[1]!['x']!) / 2;
      final ty = (handles[0]!['y']! + handles[1]!['y']!) / 2;
      final r  = rotDeg * pi / 180;
      canvas.drawLine(
        Offset(tx, ty),
        Offset(tx - sin(r) * 44, ty - cos(r) * 44),
        Paint()..color = const Color(0xFF2ECC71).withOpacity(0.8)..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_PdfOutlinePainter old) => true;
}

// ─── コントロールバーボタン ───
class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c, size: 14),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

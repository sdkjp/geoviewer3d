import 'package:flutter/material.dart';
import '../models/layer.dart';
import '../services/cesium_bridge.dart';

/// GCP 登録ダイアログ
/// 点群の4点 → 地図上の4点を対応づける
class GcpDialog extends StatefulWidget {
  final MapLayer layer;
  final List<Map<String, dynamic>> rawPoints; // 点群の座標 (projected)

  const GcpDialog({super.key, required this.layer, required this.rawPoints});

  @override
  State<GcpDialog> createState() => _GcpDialogState();
}

class _GcpDialogState extends State<GcpDialog> {
  static const int _requiredPoints = 4;

  // 点群側の手動入力座標 (平面直角 x,y,z)
  final List<TextEditingController> _pcXCtrl =
      List.generate(_requiredPoints, (_) => TextEditingController());
  final List<TextEditingController> _pcYCtrl =
      List.generate(_requiredPoints, (_) => TextEditingController());
  final List<TextEditingController> _pcZCtrl =
      List.generate(_requiredPoints, (_) => TextEditingController());

  // 地図側でクリック取得した座標
  final List<GeoPoint?> _mapPoints = List.filled(_requiredPoints, null);

  int _pickingIndex = -1; // 現在ピッキング中のインデックス (-1 = なし)

  @override
  void dispose() {
    CesiumBridge.stopGcpPicking();
    for (final c in [..._pcXCtrl, ..._pcYCtrl, ..._pcZCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _allReady {
    for (int i = 0; i < _requiredPoints; i++) {
      if (_mapPoints[i] == null) return false;
      if (_pcXCtrl[i].text.isEmpty ||
          _pcYCtrl[i].text.isEmpty ||
          _pcZCtrl[i].text.isEmpty) return false;
    }
    return true;
  }

  void _startPicking(int index) {
    setState(() => _pickingIndex = index);
    CesiumBridge.startGcpPicking((lon, lat, height) {
      if (!mounted) return;
      setState(() {
        _mapPoints[index] = GeoPoint(lon, lat, height);
        _pickingIndex = -1;
      });
      CesiumBridge.stopGcpPicking();
    });
  }

  void _apply() {
    final pairs = <GcpPair>[];
    for (int i = 0; i < _requiredPoints; i++) {
      final x = double.tryParse(_pcXCtrl[i].text) ?? 0;
      final y = double.tryParse(_pcYCtrl[i].text) ?? 0;
      final z = double.tryParse(_pcZCtrl[i].text) ?? 0;
      pairs.add(GcpPair(mapPoint: _mapPoints[i]!, pcPoint: [x, y, z]));
    }
    Navigator.pop(context, pairs);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.gps_fixed, color: Color(0xFF4FC3F7)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'GCP 登録 (4点対応)',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '点群側の座標を入力し、地図上の対応点をクリックしてください。',
              style:
                  TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
            ),
            const SizedBox(height: 16),
            // ヘッダー行
            _buildTableHeader(),
            const Divider(color: Colors.white12),
            // 4点入力行
            ...List.generate(_requiredPoints, (i) => _buildPointRow(i)),
            const SizedBox(height: 16),
            if (_pickingIndex >= 0)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4FC3F7).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF4FC3F7).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF4FC3F7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '地図上の点${_pickingIndex + 1}をクリックしてください',
                      style: const TextStyle(
                          color: Color(0xFF4FC3F7), fontSize: 13),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル',
                      style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('変換を適用'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _allReady
                        ? const Color(0xFF4FC3F7)
                        : Colors.grey,
                    foregroundColor: Colors.black87,
                  ),
                  onPressed: _allReady ? _apply : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 28),
          SizedBox(
            width: 80,
            child: Text('点群 X', style: _headerStyle),
          ),
          SizedBox(width: 6),
          SizedBox(
            width: 80,
            child: Text('点群 Y', style: _headerStyle),
          ),
          SizedBox(width: 6),
          SizedBox(
            width: 70,
            child: Text('点群 Z', style: _headerStyle),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text('地図上の座標', style: _headerStyle),
          ),
        ],
      ),
    );
  }

  static const _headerStyle =
      TextStyle(color: Colors.white38, fontSize: 11);

  Widget _buildPointRow(int i) {
    final map = _mapPoints[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFF4FC3F7).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('${i + 1}',
                  style: const TextStyle(
                      color: Color(0xFF4FC3F7),
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 6),
          _coordField(_pcXCtrl[i], 'X'),
          const SizedBox(width: 6),
          _coordField(_pcYCtrl[i], 'Y'),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: _coordField(_pcZCtrl[i], 'Z')),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => _startPicking(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: _pickingIndex == i
                      ? const Color(0xFF4FC3F7).withOpacity(0.15)
                      : map != null
                          ? Colors.green.withOpacity(0.1)
                          : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _pickingIndex == i
                        ? const Color(0xFF4FC3F7)
                        : map != null
                            ? Colors.green.withOpacity(0.5)
                            : Colors.white12,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      map != null ? Icons.check_circle : Icons.location_on,
                      size: 14,
                      color: map != null ? Colors.green : Colors.white38,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        map != null
                            ? '${map.lon.toStringAsFixed(5)},\n${map.lat.toStringAsFixed(5)}'
                            : 'クリックして選択',
                        style: TextStyle(
                          color: map != null ? Colors.green : Colors.white38,
                          fontSize: 10,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coordField(TextEditingController ctrl, String hint) {
    return SizedBox(
      width: 80,
      height: 36,
      child: TextField(
        controller: ctrl,
        style:
            const TextStyle(color: Colors.white, fontSize: 12),
        keyboardType:
            const TextInputType.numberWithOptions(signed: true, decimal: true),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              const TextStyle(color: Colors.white24, fontSize: 12),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                const BorderSide(color: Color(0xFF4FC3F7)),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

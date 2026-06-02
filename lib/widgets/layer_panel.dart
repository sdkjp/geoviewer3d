import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/layer.dart';
import '../providers/app_state.dart';
import '../services/cesium_bridge.dart';

// ─── 共通カラー定数 ───
const _kNavy      = Color(0xFF1B3A6B);   // 紺 (主色)
const _kNavyMid   = Color(0xFF2A5298);   // 中間紺 (ボーダー・アクセント)
const _kTextPrim  = Color(0xFF1B3A6B);   // 紺文字 (白背景上)
const _kTextSub   = Color(0xFF6B7A99);   // グレー文字 (補足)
const _kBgPanel   = Colors.white;        // パネル背景
const _kBgTile    = Color(0xFFF0F4F8);   // タイル背景 (薄灰)
const _kBorder    = Color(0xFFDDE2EE);   // 区切り線

class LayerPanel extends StatelessWidget {
  const LayerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: _kBgPanel,
        border: Border(left: BorderSide(color: _kBorder)),
        boxShadow: [
          BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(-2, 0)),
        ],
      ),
      child: Column(
        children: [
          _PanelHeader(onClose: state.toggleLayerPanel),
          _BaseMapSelector(),
          const Divider(color: _kBorder, height: 1),
          _LayerListHeader(state: state),
          Expanded(
            child: state.layers.isEmpty
                ? _EmptyState()
                : _LayerList(state: state),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final VoidCallback onClose;
  const _PanelHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: const BoxDecoration(
        color: _kNavy,
        border: Border(bottom: BorderSide(color: _kNavyMid)),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Text('レイヤー',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _BaseMapSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ベースマップ',
              style: TextStyle(color: _kTextSub, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final type in BaseMapType.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _BaseMapChip(
                      type: type,
                      selected: state.baseMap == type,
                      onTap: () => state.setBaseMap(type),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BaseMapChip extends StatelessWidget {
  final BaseMapType type;
  final bool selected;
  final VoidCallback onTap;

  const _BaseMapChip(
      {required this.type, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final labels = {
      BaseMapType.standard: '標準',
      BaseMapType.photo: '空中写真',
      BaseMapType.pale: '淡色',
      BaseMapType.blank: '白地図',
    };
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          // 選択・非選択ともに白地、選択時は紺ボーダー2px
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? _kNavy : _kBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          labels[type]!,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? _kNavy : Colors.black87,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _LayerListHeader extends StatelessWidget {
  final AppState state;
  const _LayerListHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFD),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 6),
      child: Row(
        children: [
          const Text('追加レイヤー',
              style: TextStyle(
                  color: _kTextSub,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.add, color: _kNavy, size: 20),
            color: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: _kBorder),
            ),
            itemBuilder: (ctx) => [
              _menuItemStr('pc_file', '点群ファイル (LAS/LAZ)', Icons.blur_on),
              _menuItemStr('pdf_file', 'PDF 図面', Icons.picture_as_pdf),
              _menuItemStr('glb_file', '3D モデル (GLB)', Icons.view_in_ar),
              const PopupMenuDivider(),
              _menuItemStr('sample_kyobashi', 'サンプル: 大阪 京橋 点群', Icons.cloud_download),
            ],
            onSelected: (key) => _onMenuSelected(context, key),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItemStr(String key, String label, IconData icon) {
    return PopupMenuItem<String>(
      value: key,
      child: Row(
        children: [
          Icon(icon, color: _kNavy, size: 18),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  color: _kTextPrim, fontSize: 13)),
        ],
      ),
    );
  }

  void _onMenuSelected(BuildContext context, String key) {
    final state = context.read<AppState>();
    if (key == 'sample_kyobashi') {
      state.setError('load_sample:sample_kyobashi.las');
    } else {
      final typeMap = {
        'pc_file': LayerType.pointCloud,
        'pdf_file': LayerType.pdf,
        'glb_file': LayerType.glbModel,
      };
      final type = typeMap[key];
      if (type != null) {
        state.setError('add:${type.name}');
      }
    }
  }
}

class _LayerList extends StatelessWidget {
  final AppState state;
  const _LayerList({required this.state});

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 80),
      itemCount: state.layers.length,
      onReorder: state.reorderLayer,
      itemBuilder: (ctx, i) {
        final layer = state.layers[i];
        return _LayerTile(key: ValueKey(layer.id), layer: layer);
      },
    );
  }
}

class _LayerTile extends StatelessWidget {
  final MapLayer layer;
  const _LayerTile({super.key, required this.layer});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      decoration: BoxDecoration(
        color: _kBgTile,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Theme(
        // ExpansionTile の矢印・テキストを紺に
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: _kNavy,
          ),
        ),
        child: ExpansionTile(
          iconColor: _kNavy,
          collapsedIconColor: _kTextSub,
          leading: Icon(layer.icon, color: _kNavy, size: 18),
          title: Text(
            layer.name,
            style: const TextStyle(
                color: _kTextPrim, fontSize: 13, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  layer.visible ? Icons.visibility : Icons.visibility_off,
                  color: layer.visible ? _kNavy : const Color(0xFFB0BAD0),
                  size: 18,
                ),
                onPressed: () => state.toggleLayerVisibility(layer.id),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent, size: 18),
                onPressed: () => _confirmDelete(context, state),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
              const Icon(Icons.drag_handle,
                  color: Color(0xFFB0BAD0), size: 18),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: _kBorder, height: 16),
                  Row(
                    children: [
                      const Text('透明度',
                          style: TextStyle(
                              color: _kTextSub,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            thumbColor: _kNavy,
                            activeTrackColor: _kNavy,
                            inactiveTrackColor: _kBorder,
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7),
                          ),
                          child: Slider(
                            value: layer.opacity,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (v) =>
                                state.setLayerOpacity(layer.id, v),
                          ),
                        ),
                      ),
                      Text('${(layer.opacity * 100).round()}%',
                          style: const TextStyle(
                              color: _kTextSub, fontSize: 11)),
                    ],
                  ),
                  // GCP 警告: 手動登録が必要な場合のみ表示
                  // (URL 経由 / crsHint 自動変換済みの場合は isProjected=false)
                  if (layer.type == LayerType.pointCloud &&
                      layer.isProjected &&
                      layer.gcpPairs.length < 4)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, color: Colors.orange, size: 14),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              '投影座標系の点群です\nファイル追加時のダイアログで GCP を 4 点登録してください',
                              style: TextStyle(color: Colors.orange, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ─── WebAR ボタン (点群レイヤーのみ) ───
                  if (layer.type == LayerType.pointCloud) ...[
                    const SizedBox(height: 8),
                    _ArButton(layerId: layer.id, layerName: layer.name),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppState state) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _kBorder),
        ),
        title: const Text('レイヤーを削除',
            style: TextStyle(color: _kTextPrim, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('「${layer.name}」を削除しますか？',
            style: const TextStyle(color: _kTextSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: _kTextSub)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, true);
              state.removeLayer(layer.id);
            },
            child: const Text('削除',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_outlined,
                color: _kNavy.withOpacity(0.18), size: 48),
            const SizedBox(height: 12),
            const Text(
              'レイヤーがありません\n右上の + から追加してください',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kTextSub, fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 3D / AR ビューアボタン ───
class _ArButton extends StatefulWidget {
  final String layerId;
  final String layerName;
  const _ArButton({required this.layerId, required this.layerName});

  @override
  State<_ArButton> createState() => _ArButtonState();
}

class _ArButtonState extends State<_ArButton> {
  bool _loading = false;

  Future<void> _startAR() async {
    setState(() => _loading = true);
    try {
      final result = await CesiumBridge.startPointCloudAR(
        widget.layerId,
        layerName: widget.layerName,
      );
      if (!mounted) return;
      if (result['error'] != null) {
        _showMsg(result['error'] as String, isError: true);
      }
    } catch (e) {
      if (mounted) _showMsg('ビューアの起動に失敗しました: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMsg(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : _kNavy,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: _loading
            ? const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: _kNavy))
            : const Icon(Icons.view_in_ar, size: 16),
        label: Text(_loading ? '読み込み中...' : '3D / AR ビューアで表示'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _kNavy,
          side: const BorderSide(color: _kNavyMid),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: _loading ? null : _startAR,
      ),
    );
  }
}

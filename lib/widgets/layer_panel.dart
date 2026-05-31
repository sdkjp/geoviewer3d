import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/layer.dart';
import '../providers/app_state.dart';

class LayerPanel extends StatelessWidget {
  const LayerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: const Color(0xF01A1A2E),
        border: Border(left: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Column(
        children: [
          _PanelHeader(onClose: state.toggleLayerPanel),
          _BaseMapSelector(),
          const Divider(color: Colors.white12, height: 1),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.layers, color: Color(0xFF4FC3F7), size: 20),
          const SizedBox(width: 8),
          const Text('レイヤー',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ベースマップ',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
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
          color: selected
              ? const Color(0xFF4FC3F7).withOpacity(0.25)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? const Color(0xFF4FC3F7)
                : Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Text(
          labels[type]!,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? const Color(0xFF4FC3F7) : Colors.white60,
            fontSize: 10,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      child: Row(
        children: [
          const Text('追加レイヤー',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const Spacer(),
          PopupMenuButton<LayerType>(
            icon: const Icon(Icons.add, color: Color(0xFF4FC3F7), size: 20),
            color: const Color(0xFF1E2035),
            itemBuilder: (ctx) => [
              _menuItem(LayerType.pointCloud, '点群 (LAS/LAZ/GLB)'),
              _menuItem(LayerType.pdf, 'PDF 図面'),
              _menuItem(LayerType.glbModel, '3D モデル (GLB)'),
            ],
            onSelected: (type) =>
                _showAddLayerDialog(context, type),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<LayerType> _menuItem(LayerType type, String label) {
    return PopupMenuItem<LayerType>(
      value: type,
      child: Row(
        children: [
          Icon(_iconFor(type), color: const Color(0xFF4FC3F7), size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  IconData _iconFor(LayerType t) {
    switch (t) {
      case LayerType.pointCloud:
        return Icons.blur_on;
      case LayerType.pdf:
        return Icons.picture_as_pdf;
      case LayerType.glbModel:
        return Icons.view_in_ar;
      case LayerType.annotation:
        return Icons.place;
    }
  }

  void _showAddLayerDialog(BuildContext context, LayerType type) {
    // 実際のファイル選択ダイアログはメイン画面で処理
    final state = context.read<AppState>();
    // ダイアログの代わりにイベントを発火
    state.setError('add:${type.name}'); // hack: 画面側でインターセプト
  }
}

class _LayerList extends StatelessWidget {
  final AppState state;
  const _LayerList({required this.state});

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
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
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        leading: Icon(layer.icon, color: const Color(0xFF4FC3F7), size: 18),
        title: Text(
          layer.name,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                layer.visible ? Icons.visibility : Icons.visibility_off,
                color: layer.visible ? Colors.white70 : Colors.white30,
                size: 18,
              ),
              onPressed: () => state.toggleLayerVisibility(layer.id),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.red, size: 18),
              onPressed: () => _confirmDelete(context, state),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
            const Icon(Icons.drag_handle, color: Colors.white30, size: 18),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('透明度',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 11)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbColor: const Color(0xFF4FC3F7),
                          activeTrackColor: const Color(0xFF4FC3F7),
                          inactiveTrackColor: Colors.white12,
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
                            color: Colors.white54, fontSize: 11)),
                  ],
                ),
                if (layer.type == LayerType.pointCloud &&
                    layer.isProjected &&
                    layer.gcpPairs.length < 4)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber,
                            color: Colors.orange, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'GCP 登録が必要です (${layer.gcpPairs.length}/4)',
                            style: const TextStyle(
                                color: Colors.orange, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppState state) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2035),
        title: const Text('レイヤーを削除',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text('「${layer.name}」を削除しますか？',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, true);
              state.removeLayer(layer.id);
            },
            child:
                const Text('削除', style: TextStyle(color: Colors.red)),
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
                color: Colors.white.withOpacity(0.2), size: 48),
            const SizedBox(height: 12),
            Text(
              'レイヤーがありません\n右上の + から追加してください',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.3), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

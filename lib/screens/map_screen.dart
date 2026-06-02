import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import '../models/layer.dart';
import '../providers/app_state.dart';
import '../services/cesium_bridge.dart';
import '../services/file_service.dart';
import '../utils/gcp_transform.dart';
import '../widgets/joystick_widget.dart';
import '../widgets/layer_panel.dart';
import '../widgets/gcp_dialog.dart';
import '../widgets/viewpoint_dialog.dart';
import '../widgets/pdf_editor_overlay.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Timer? _cesiumInitTimer;
  bool _cesiumViewRegistered = false;
  bool _showControls = true;
  bool _annotationMode = false;
  bool _walkingMode = false;
  // PDF エディタ
  String? _editingPdfId;
  Map<String, dynamic>? _editingPdfState;

  @override
  void initState() {
    super.initState();
    _registerCesiumView();
    _waitForCesium();
  }

  static const String _cesiumViewType = 'cesium-view';

  void _registerCesiumView() {
    if (_cesiumViewRegistered) return;
    _cesiumViewRegistered = true;
    // Flutter Web の HtmlElementView として Cesium コンテナを登録
    ui_web.platformViewRegistry.registerViewFactory(
      _cesiumViewType,
      (int viewId) {
        // JS の _cesiumContainerFactory を呼んで div を作成
        final div = _createCesiumDiv();
        return div;
      },
    );
  }

  void _waitForCesium() {
    _cesiumInitTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (CesiumBridge.isReady) {
        _cesiumInitTimer?.cancel();
        final state = context.read<AppState>();
        state.setCesiumReady();
      } else {
        // まだ準備できていなければ初期化を試みる
        try {
          CesiumBridge.initialize();
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _cesiumInitTimer?.cancel();
    super.dispose();
  }

  // ─── 歩行モード ───
  void _toggleWalkingMode() {
    if (_walkingMode) {
      // 解除
      CesiumBridge.disableWalkingMode();
      setState(() => _walkingMode = false);
    } else {
      // 有効化: ユーザーが地図をクリックするまで待機
      setState(() => _walkingMode = true);
      final cam = CesiumBridge.getCameraState();
      if (cam != null) {
        // 現在地から歩行開始
        CesiumBridge.enableWalkingMode(
          lon: (cam['lon'] as num).toDouble(),
          lat: (cam['lat'] as num).toDouble(),
        );
      }
    }
  }

  // ─── エラーメッセージのインターセプト (add:xxx) ───
  void _handleAddLayer(String typeStr) {
    final type = LayerType.values.firstWhere((t) => t.name == typeStr,
        orElse: () => LayerType.pointCloud);
    _addLayer(type);
  }

  // ─── レイヤー追加 ───
  Future<void> _addLayer(LayerType type) async {
    final state = context.read<AppState>();

    switch (type) {
      case LayerType.pointCloud:
        await _addPointCloudLayer(state);
        break;
      case LayerType.pdf:
        await _addPdfLayer(state);
        break;
      case LayerType.glbModel:
        await _addGlbLayer(state);
        break;
      case LayerType.annotation:
        setState(() => _annotationMode = true);
        break;
    }
  }

  /// URL から点群を読み込んでレイヤーパネルに追加（JS 高速パス）
  Future<void> loadPointCloudFromUrl(String url, String name,
      {int? jgdZone, bool jgdSwapped = false}) async {
    final state = context.read<AppState>();
    final layerId = 'pc_${DateTime.now().millisecondsSinceEpoch}';

    final layer = MapLayer(
      id: layerId,
      name: name,
      type: LayerType.pointCloud,
      // URL 経由ロードは JS 側が crsHint で自動変換済み → GCP 不要
      isProjected: false,
    );
    state.addLayer(layer);
    state.setLoading(true, message: '点群を読み込み中...');

    _loadPointCloudUrl(
      url.toJS,
      layerId.toJS,
      jgdZone?.toJS ?? 0.toJS,
      jgdSwapped.toJS,
      ((JSString resultJson) {
        final r = jsonDecode(resultJson.toDart) as Map<String, dynamic>;
        if (!mounted) return;
        state.setLoading(false);
        if (r['error'] != null) {
          state.setError('読み込みエラー: ${r['error']}');
        } else {
          final center = r['center'] as Map<String, dynamic>?;
          if (center != null) {
            CesiumBridge.flyTo(
              lon: (center['lon'] as num).toDouble(),
              lat: (center['lat'] as num).toDouble(),
              height: 400,
              pitch: -45,
            );
          }
          _showSnack('$name — ${r['pts']} 点 読み込み完了');
        }
      }).toJS,
    );
  }

  Future<void> _addPointCloudLayer(AppState state) async {
    final file = await FileService.pickPointCloud();
    if (file == null) return;

    state.setLoading(true, message: '点群を解析中...');

    try {
      final result = await _parsePointCloud(file.bytes, file.name);

      final layer = MapLayer(
        id: 'pc_${DateTime.now().millisecondsSinceEpoch}',
        name: file.name,
        type: LayerType.pointCloud,
        isProjected: result['isProjected'] as bool? ?? false,
        coordinateInfo: result,
      );

      state.addLayer(layer);
      state.setLoading(false);

      final points = result['points'] as List<Map<String, dynamic>>;
      final autoConverted = result['autoConverted'] as bool? ?? false;
      final coordInfo = result['coordinateInfo'] as String? ?? '';

      if (autoConverted || !layer.isProjected) {
        // 地理座標 or JGD2011 自動変換済み → そのまま表示
        CesiumBridge.addPointCloudLayer(layer.id, points);
        if (points.isNotEmpty) {
          final center = result['center'] as Map<String, dynamic>?;
          final lon = center != null
              ? (center['lon'] as num).toDouble()
              : (points[points.length ~/ 2]['x'] as num).toDouble();
          final lat = center != null
              ? (center['lat'] as num).toDouble()
              : (points[points.length ~/ 2]['y'] as num).toDouble();
          CesiumBridge.flyTo(lon: lon, lat: lat, height: 500, pitch: -45);
        }
        _showSnack(
            '${autoConverted ? coordInfo : "点群"} — ${result['loadedPoints']} 点 表示中');
      } else {
        // 投影座標（UTM 等）→ GCP 登録が必要
        if (!mounted) return;
        final pairs = await showDialog<List<GcpPair>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => GcpDialog(layer: layer, rawPoints: points),
        );
        if (pairs != null && pairs.length >= 4) {
          layer.gcpPairs.addAll(pairs);
          final transform = GcpTransform.estimate(pairs);
          final geoPoints = transform.transformPoints(points);
          CesiumBridge.addPointCloudLayer(layer.id, geoPoints);
          _showSnack(
              '点群を配置しました（残差 RMS: ${transform.residualRms.toStringAsFixed(3)} m）');
        }
      }
    } catch (e) {
      state.setLoading(false);
      state.setError('点群の読み込みに失敗しました: $e');
    }
  }

  Future<Map<String, dynamic>> _parsePointCloud(
      Uint8List bytes, String filename) async {
    // Web Worker で解析
    final completer = Completer<Map<String, dynamic>>();

    // JS Worker を起動
    _startLasWorker(bytes, filename, completer);

    return completer.future.timeout(const Duration(minutes: 3));
  }

  void _startLasWorker(Uint8List bytes, String filename,
      Completer<Map<String, dynamic>> completer) {
    final jsCallback = (JSString jsResult) {
      try {
        final resultJson = jsResult.toDart;
        final decoded = jsonDecode(resultJson) as Map<String, dynamic>;
        if (decoded['type'] == 'error') {
          completer.completeError(decoded['message'] as String);
        } else {
          final rawPoints = decoded['points'] as List;
          final points = rawPoints
              .map((p) => Map<String, dynamic>.from(p as Map))
              .toList();
          completer.complete({
            'points': points,
            'isProjected': decoded['isProjected'] as bool? ?? false,
            'autoConverted': decoded['autoConverted'] as bool? ?? false,
            'coordinateInfo': decoded['coordinateInfo'] as String? ?? '',
            'totalPoints': decoded['totalPoints'] as int? ?? points.length,
            'loadedPoints': decoded['loadedPoints'] as int? ?? points.length,
            'center': decoded['center'] as Map<String, dynamic>?,
          });
        }
      } catch (e) {
        completer.completeError('パース失敗: $e');
      }
    }.toJS;
    _runLasWorker(bytes.buffer.toJS, filename.toJS, jsCallback);
  }

  Future<void> _addPdfLayer(AppState state) async {
    final file = await FileService.pickPdf();
    if (file == null) return;

    state.setLoading(true, message: 'PDF を処理中...');

    try {
      // PDF → Canvas 変換は JS 側で実施
      final dataUrl = FileService.bytesToDataUrl(file.bytes, 'application/pdf');

      // PDF → Canvas 画像に変換
      final canvasDataUrl = await _renderPdfToCanvas(dataUrl);

      // アスペクト比を取得（canvas から）
      final aspectRatio = await _getPdfAspectRatio(dataUrl);

      final layerId = 'pdf_${DateTime.now().millisecondsSinceEpoch}';
      final layer = MapLayer(
        id: layerId,
        name: file.name,
        type: LayerType.pdf,
      );

      state.addLayer(layer);
      state.setLoading(false);

      // カメラ中心にデフォルト配置
      final initState = CesiumBridge.initPdfPlacement(
          layerId, canvasDataUrl, aspectRatio);
      if (initState == null) {
        state.setError('PDF の配置に失敗しました');
        return;
      }

      // PowerPoint 風エディタを表示
      if (!mounted) return;
      setState(() {
        _editingPdfId = layerId;
        _editingPdfState = initState;
      });
      _showSnack('PDF を配置しました。ドラッグで移動・拡縮・回転できます。');
    } catch (e) {
      state.setLoading(false);
      state.setError('PDF の読み込みに失敗しました: $e');
    }
  }

  Future<double> _getPdfAspectRatio(String dataUrl) async {
    // pdf.js で1ページ目のアスペクト比を取得
    try {
      final ratio = await _getPdfAspectRatioJS(dataUrl.toJS).toDart;
      return ratio.toDartDouble;
    } catch (_) {
      return 1.0 / 1.414; // A4縦
    }
  }

  Future<void> _addGlbLayer(AppState state) async {
    final file = await FileService.pickGlb();
    if (file == null) return;

    state.setLoading(true, message: '3D モデルを読み込み中...');

    final camera = CesiumBridge.getCameraState();
    final lon = camera?['lon'] as double? ?? 135.0;
    final lat = camera?['lat'] as double? ?? 35.0;
    final height = 0.0;

    final dataUrl = FileService.glbBytesToObjectUrl(file.bytes);

    final layer = MapLayer(
      id: 'glb_${DateTime.now().millisecondsSinceEpoch}',
      name: file.name,
      type: LayerType.glbModel,
      glbUrl: dataUrl,
      glbPosition: GeoPoint(lon, lat, height),
    );

    state.addLayer(layer);
    CesiumBridge.addGlbLayer(layer.id, dataUrl,
        lon: lon, lat: lat, height: height);

    state.setLoading(false);
    _showSnack('3D モデルを現在地に配置しました');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: const Color(0xFF1B3A6B),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  // ─── メインビルド ───
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // エラーメッセージをインターセプト
    if (state.errorMessage != null) {
      final msg = state.errorMessage!;
      if (msg.startsWith('add:')) {
        final typeStr = msg.substring(4);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          state.setError(null);
          _handleAddLayer(typeStr);
        });
      } else if (msg.startsWith('load_sample:')) {
        final filename = msg.substring(12);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          state.setError(null);
          loadPointCloudFromUrl(filename, filename,
              jgdZone: 6, jgdSwapped: true);
        });
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Cesium を HtmlElementView として全画面に埋め込む
          const HtmlElementView(viewType: _cesiumViewType),

          // ローディング
          if (state.isLoading) _LoadingOverlay(message: state.loadingMessage),

          // 注釈モードバナー
          if (_annotationMode)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _AnnotationModeBanner(
                onCancel: () => setState(() => _annotationMode = false),
              ),
            ),

          // 歩行モードバナー
          if (_walkingMode)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _WalkingModeBanner(
                onExit: _toggleWalkingMode,
              ),
            ),

          // 右上: 操作ボタン
          Positioned(
            top: 16,
            right: 16,
            child: _TopRightButtons(
              state: state,
              onAnnotation: () => setState(() => _annotationMode = !_annotationMode),
              annotationActive: _annotationMode,
              walkingActive: _walkingMode,
              onWalking: _toggleWalkingMode,
              onShare: () => _showShareViewpoint(context, state),
              onImport: () => _showImportViewpoint(context, state),
            ),
          ),

          // レイヤーパネル (右サイド)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            right: state.showLayerPanel ? 0 : -290,
            child: const LayerPanel(),
          ),

          // PDF エディタオーバーレイ (PowerPoint 風)
          if (_editingPdfId != null && _editingPdfState != null)
            PdfEditorOverlay(
              layerId: _editingPdfId!,
              initialCenterLon: (_editingPdfState!['centerLon'] as num).toDouble(),
              initialCenterLat: (_editingPdfState!['centerLat'] as num).toDouble(),
              initialWidthM: (_editingPdfState!['widthM'] as num).toDouble(),
              initialHeightM: (_editingPdfState!['heightM'] as num).toDouble(),
              onConfirm: () => setState(() {
                _editingPdfId = null;
                _editingPdfState = null;
                _showSnack('PDF を確定しました');
              }),
              onCancel: () {
                if (_editingPdfId != null) {
                  context.read<AppState>().removeLayer(_editingPdfId!);
                }
                setState(() {
                  _editingPdfId = null;
                  _editingPdfState = null;
                });
              },
            ),

          // 左下: ジョイスティック
          if (_showControls)
            Positioned(
              bottom: 30,
              left: 20,
              child: _ControlsWidget(),
            ),

          // 右下: ズームボタン
          if (_showControls)
            Positioned(
              bottom: 100,
              right: state.showLayerPanel ? 296 : 16,
              child: _ZoomButtons(),
            ),

          // エラーバー
          if (state.errorMessage != null &&
              !state.errorMessage!.startsWith('add:'))
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: _ErrorBar(
                message: state.errorMessage!,
                onDismiss: () => state.setError(null),
              ),
            ),
        ],
      ),
    );
  }

  void _showShareViewpoint(BuildContext context, AppState state) {
    final json = state.exportViewpointJson();
    showDialog(
      context: context,
      builder: (_) => ViewpointExportDialog(viewpointJson: json),
    );
  }

  void _showImportViewpoint(BuildContext context, AppState state) async {
    final json = await showDialog<String>(
      context: context,
      builder: (_) => const ViewpointImportDialog(),
    );
    if (json != null) {
      state.importViewpointJson(json);
    }
  }
}

// ─── JS Interop ───
@JS('_createCesiumDiv')
external JSObject _createCesiumDivJS();

// Cesium コンテナ div を JS 側で作成して返す
Object _createCesiumDiv() => _createCesiumDivJS();

@JS('_runLasWorker')
external void _runLasWorker(
    JSArrayBuffer buffer, JSString filename, JSFunction callback);

// URL から点群をロードして Cesium に表示 + コールバック
@JS('_loadPointCloudFromFlutter')
external void _loadPointCloudUrl(
    JSString url, JSString layerId,
    JSNumber jgdZone, JSBoolean jgdSwapped,
    JSFunction callback);

@JS('_renderPdfToCanvas')
external JSPromise<JSString> _renderPdfToCanvasJS(JSString dataUrl);

@JS('_getPdfAspectRatio')
external JSPromise<JSNumber> _getPdfAspectRatioJS(JSString dataUrl);

Future<String> _renderPdfToCanvas(String dataUrl) async {
  final result = await _renderPdfToCanvasJS(dataUrl.toJS).toDart;
  return result.toDart;
}

// ─── ウィジェット群 ───

class _LoadingOverlay extends StatelessWidget {
  final String? message;
  const _LoadingOverlay({this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1B3A6B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(message!,
                    style: const TextStyle(color: Colors.white70)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnotationModeBanner extends StatelessWidget {
  final VoidCallback onCancel;
  const _AnnotationModeBanner({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xEA1B3A6B),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.place, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('地図をクリックして注釈を追加',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
          TextButton(
            onPressed: onCancel,
            child:
                const Text('キャンセル', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// 歩行モードバナー
class _WalkingModeBanner extends StatelessWidget {
  final VoidCallback onExit;
  const _WalkingModeBanner({required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xCC2ECC71),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.directions_walk, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '歩行モード ─ 地図をタップして移動 / ジョイスティックで歩行・視点回転',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onExit,
            child: const Text('終了', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _TopRightButtons extends StatelessWidget {
  final AppState state;
  final VoidCallback onAnnotation;
  final bool annotationActive;
  final bool walkingActive;
  final VoidCallback onWalking;
  final VoidCallback onShare;
  final VoidCallback onImport;

  const _TopRightButtons({
    required this.state,
    required this.onAnnotation,
    required this.annotationActive,
    required this.walkingActive,
    required this.onWalking,
    required this.onShare,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _GlassButton(
          icon: Icons.layers,
          tooltip: 'レイヤーパネル',
          active: state.showLayerPanel,
          onTap: state.toggleLayerPanel,
        ),
        const SizedBox(height: 8),
        _GlassButton(
          icon: Icons.place,
          tooltip: '注釈を追加',
          active: annotationActive,
          onTap: onAnnotation,
        ),
        const SizedBox(height: 8),
        _GlassButton(
          icon: Icons.directions_walk,
          tooltip: '歩行モード（地図をタップして開始）',
          active: walkingActive,
          activeColor: const Color(0xFF2ECC71),
          onTap: onWalking,
        ),
        const SizedBox(height: 8),
        _GlassButton(
          icon: Icons.share_location,
          tooltip: '視点を共有',
          onTap: onShare,
        ),
        const SizedBox(height: 8),
        _GlassButton(
          icon: Icons.my_location,
          tooltip: '視点を読み込む',
          onTap: onImport,
        ),
        const SizedBox(height: 8),
        _GlassButton(
          icon: Icons.explore,
          tooltip: '北向きにリセット',
          onTap: () => CesiumBridge.resetNorth(),
        ),
      ],
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final Color? activeColor;
  final VoidCallback onTap;

  const _GlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.activeColor,
  });

  Color get _activeColor => activeColor ?? const Color(0xFF2A5298);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            // 通常: ソリッド紺、アクティブ: アクセントカラー
            color: active
                ? _activeColor.withOpacity(0.85)
                : const Color(0xEA1B3A6B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? _activeColor
                  : const Color(0xFF2A5298),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _ControlsWidget extends StatelessWidget {
  // 紺色テーマ
  static const Color _base = Color(0xCC1B3A6B);   // 半透明紺
  static const Color _knob = Color(0xFFFFFFFF);    // 白ノブ

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 移動ジョイスティック
        JoystickWidget(
          size: 110,
          label: '移動',
          baseColor: _base,
          knobColor: _knob,
          onMove: (dx, dy) => CesiumBridge.moveCamera(dx, dy, 0),
        ),
        const SizedBox(width: 16),
        // 視点ジョイスティック
        JoystickWidget(
          size: 90,
          label: '視点',
          baseColor: _base,
          knobColor: _knob,
          onMove: (dx, dy) =>
              CesiumBridge.rotateCamera(dx * 2, dy * 2),
        ),
      ],
    );
  }
}

class _ZoomButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GlassButton(
          icon: Icons.add,
          tooltip: 'ズームイン',
          onTap: CesiumBridge.zoomIn,
        ),
        const SizedBox(height: 8),
        _GlassButton(
          icon: Icons.remove,
          tooltip: 'ズームアウト',
          onTap: CesiumBridge.zoomOut,
        ),
      ],
    );
  }
}

class _ErrorBar extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorBar({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
        ],
      ),
    );
  }
}

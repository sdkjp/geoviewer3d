import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/layer.dart';
import '../models/annotation.dart';
import '../models/viewpoint.dart';
import '../services/cesium_bridge.dart';

enum BaseMapType { standard, photo, pale, blank }

class AppState extends ChangeNotifier {
  final List<MapLayer> layers = [];
  final List<Annotation> annotations = [];
  bool _cesiumReady = false;
  BaseMapType baseMap = BaseMapType.standard;
  bool showLayerPanel = false;
  bool isLoading = false;
  String? loadingMessage;
  String? errorMessage;

  bool get cesiumReady => _cesiumReady;

  void setCesiumReady() {
    _cesiumReady = true;
    notifyListeners();
  }

  // ─── レイヤー管理 ───
  void addLayer(MapLayer layer) {
    layers.add(layer);
    notifyListeners();
  }

  void removeLayer(String id) {
    layers.removeWhere((l) => l.id == id);
    CesiumBridge.removeLayer(id);
    notifyListeners();
  }

  void toggleLayerVisibility(String id) {
    final layer = layers.firstWhere((l) => l.id == id);
    layer.visible = !layer.visible;
    CesiumBridge.setLayerVisibility(id, visible: layer.visible);
    notifyListeners();
  }

  void setLayerOpacity(String id, double opacity) {
    final layer = layers.firstWhere((l) => l.id == id);
    layer.opacity = opacity;
    CesiumBridge.setLayerOpacity(id, opacity);
    notifyListeners();
  }

  void reorderLayer(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final layer = layers.removeAt(oldIndex);
    layers.insert(newIndex, layer);
    notifyListeners();
  }

  // ─── ベースマップ ───
  void setBaseMap(BaseMapType type) {
    baseMap = type;
    CesiumBridge.setBaseMap(type.name);
    notifyListeners();
  }

  // ─── 注釈 ───
  void addAnnotation(Annotation ann) {
    annotations.add(ann);
    CesiumBridge.addAnnotation(ann.id,
        lon: ann.position.lon,
        lat: ann.position.lat,
        height: ann.position.height,
        text: ann.text,
        color: ann.color);
    notifyListeners();
  }

  void removeAnnotation(String id) {
    annotations.removeWhere((a) => a.id == id);
    CesiumBridge.removeAnnotation(id);
    notifyListeners();
  }

  void updateAnnotationText(String id, String text) {
    final ann = annotations.firstWhere((a) => a.id == id);
    ann.text = text;
    CesiumBridge.updateAnnotationText(id, text);
    notifyListeners();
  }

  // ─── UI 状態 ───
  void toggleLayerPanel() {
    showLayerPanel = !showLayerPanel;
    notifyListeners();
  }

  void setLoading(bool loading, {String? message}) {
    isLoading = loading;
    loadingMessage = message;
    if (!loading) loadingMessage = null;
    notifyListeners();
  }

  void setError(String? message) {
    errorMessage = message;
    notifyListeners();
  }

  // ─── 視点 JSON ───
  String exportViewpointJson({String? label}) {
    final state = CesiumBridge.getViewpointJson();
    if (state == null) return '{}';
    final vp = Viewpoint.fromJson(state)..label = label;
    return vp.toShareJson();
  }

  void importViewpointJson(String json) {
    try {
      CesiumBridge.applyViewpointJson(json);
    } catch (e) {
      setError('視点JSONの適用に失敗しました: $e');
    }
  }

  // ─── プロジェクト保存 (LocalStorage) ───
  Map<String, dynamic> toProjectJson() => {
        'layers': layers.map((l) => l.toJson()).toList(),
        'annotations': annotations.map((a) => a.toJson()).toList(),
        'baseMap': baseMap.name,
      };

  String toProjectJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toProjectJson());
}

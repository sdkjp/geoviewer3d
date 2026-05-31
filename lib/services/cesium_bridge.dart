// ignore_for_file: avoid_web_libraries_in_flutter
@JS()
library cesium_bridge;

import 'dart:js_interop';
import 'dart:convert';

@JS('CesiumBridge.init')
external JSBoolean _init(JSAny? options);

@JS('CesiumBridge.flyTo')
external void _flyTo(
    JSNumber lon, JSNumber lat, JSNumber height,
    JSNumber heading, JSNumber pitch, JSNumber duration);

@JS('CesiumBridge.getCameraState')
external JSString? _getCameraState();

@JS('CesiumBridge.moveCamera')
external void _moveCamera(JSNumber dx, JSNumber dy, JSNumber dz);

@JS('CesiumBridge.rotateCamera')
external void _rotateCamera(JSNumber dHeading, JSNumber dPitch);

@JS('CesiumBridge.setBaseMap')
external void _setBaseMap(JSString type);

@JS('CesiumBridge.addPointCloudLayer')
external JSBoolean _addPointCloudLayer(JSString id, JSString pointsJson, JSAny options);

@JS('CesiumBridge.addPdfLayer')
external JSBoolean _addPdfLayer(JSString id, JSString dataUrl, JSString cornersJson);

@JS('CesiumBridge.addGlbLayer')
external JSBoolean _addGlbLayer(
    JSString id, JSString url,
    JSNumber lon, JSNumber lat, JSNumber height,
    JSNumber heading, JSNumber pitch, JSNumber roll,
    JSNumber scale);

@JS('CesiumBridge.removeLayer')
external void _removeLayer(JSString id);

@JS('CesiumBridge.setLayerVisibility')
external void _setLayerVisibility(JSString id, JSBoolean visible);

@JS('CesiumBridge.setLayerOpacity')
external void _setLayerOpacity(JSString id, JSNumber opacity);

@JS('CesiumBridge.startGcpPicking')
external void _startGcpPicking(JSFunction callback);

@JS('CesiumBridge.stopGcpPicking')
external void _stopGcpPicking();

@JS('CesiumBridge.addAnnotation')
external void _addAnnotation(
    JSString id, JSNumber lon, JSNumber lat,
    JSNumber height, JSString text, JSString color);

@JS('CesiumBridge.removeAnnotation')
external void _removeAnnotation(JSString id);

@JS('CesiumBridge.updateAnnotationText')
external void _updateAnnotationText(JSString id, JSString text);

@JS('CesiumBridge.getViewpointJson')
external JSString? _getViewpointJson();

@JS('CesiumBridge.applyViewpointJson')
external void _applyViewpointJson(JSString json);

@JS('CesiumBridge.zoomIn')
external void _zoomIn();

@JS('CesiumBridge.zoomOut')
external void _zoomOut();

@JS('CesiumBridge.resetNorth')
external void _resetNorth();

@JS('CesiumBridge.isInitialized')
external JSBoolean _isInitialized();

// ─────────────────────────────────────────────
// Dart ラッパー
// ─────────────────────────────────────────────
class CesiumBridge {
  static bool _ready = false;

  static void initialize() {
    if (_ready) return;
    _init(null);
    _ready = true;
  }

  static bool get isReady => _isInitialized().toDart;

  static void flyTo({
    required double lon,
    required double lat,
    required double height,
    double heading = 0,
    double pitch = -45,
    double duration = 1.5,
  }) {
    _flyTo(lon.toJS, lat.toJS, height.toJS,
        heading.toJS, pitch.toJS, duration.toJS);
  }

  static Map<String, dynamic>? getCameraState() {
    final s = _getCameraState()?.toDart;
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }

  static void moveCamera(double dx, double dy, double dz) =>
      _moveCamera(dx.toJS, dy.toJS, dz.toJS);

  static void rotateCamera(double dHeading, double dPitch) =>
      _rotateCamera(dHeading.toJS, dPitch.toJS);

  static void setBaseMap(String type) => _setBaseMap(type.toJS);

  static void addPointCloudLayer(
      String id, List<Map<String, dynamic>> points) {
    _addPointCloudLayer(id.toJS, jsonEncode(points).toJS, <String, dynamic>{}.jsify()!);
  }

  static void addPdfLayer(
      String id, String dataUrl, List<Map<String, dynamic>> corners) {
    _addPdfLayer(id.toJS, dataUrl.toJS, jsonEncode(corners).toJS);
  }

  static void addGlbLayer(String id, String url,
      {required double lon, required double lat, double height = 0,
       double heading = 0, double pitch = 0, double roll = 0, double scale = 1.0}) {
    _addGlbLayer(id.toJS, url.toJS,
        lon.toJS, lat.toJS, height.toJS,
        heading.toJS, pitch.toJS, roll.toJS, scale.toJS);
  }

  static void removeLayer(String id) => _removeLayer(id.toJS);

  static void setLayerVisibility(String id, {required bool visible}) =>
      _setLayerVisibility(id.toJS, visible.toJS);

  static void setLayerOpacity(String id, double opacity) =>
      _setLayerOpacity(id.toJS, opacity.toJS);

  static void startGcpPicking(void Function(double lon, double lat, double height) onPick) {
    _startGcpPicking(((JSString jsonStr) {
      final m = jsonDecode(jsonStr.toDart) as Map<String, dynamic>;
      onPick(
        (m['lon'] as num).toDouble(),
        (m['lat'] as num).toDouble(),
        (m['height'] as num).toDouble(),
      );
    }).toJS);
  }

  static void stopGcpPicking() => _stopGcpPicking();

  static void addAnnotation(String id,
      {required double lon, required double lat, double height = 0,
       required String text, String color = '#FF6B35'}) {
    _addAnnotation(id.toJS, lon.toJS, lat.toJS, height.toJS, text.toJS, color.toJS);
  }

  static void removeAnnotation(String id) => _removeAnnotation(id.toJS);

  static void updateAnnotationText(String id, String text) =>
      _updateAnnotationText(id.toJS, text.toJS);

  static Map<String, dynamic>? getViewpointJson() {
    final s = _getViewpointJson()?.toDart;
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }

  static void applyViewpointJson(String json) =>
      _applyViewpointJson(json.toJS);

  static void zoomIn() => _zoomIn();
  static void zoomOut() => _zoomOut();
  static void resetNorth() => _resetNorth();
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
}

class FileService {
  static Future<PickedFile?> pickPointCloud() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['las', 'laz', 'glb'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    return PickedFile(f.name, f.bytes!);
  }

  static Future<PickedFile?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    return PickedFile(f.name, f.bytes!);
  }

  static Future<PickedFile?> pickGlb() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['glb', 'gltf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    return PickedFile(f.name, f.bytes!);
  }

  static Future<PickedFile?> pickJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    return PickedFile(f.name, f.bytes!);
  }

  /// bytes を Base64 DataURL に変換 (PDF → Canvas 描画用)
  static String bytesToDataUrl(Uint8List bytes, String mimeType) {
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  /// GLB を Object URL に変換 (Cesium に渡す用)
  static String glbBytesToObjectUrl(Uint8List bytes) {
    // Web のみ: Blob → URL.createObjectURL は JS 側で行う
    // Flutter Web では dart:html が必要だが、JS Interop 経由で行う
    return bytesToDataUrl(bytes, 'model/gltf-binary');
  }

  /// JSON テキストを保存ダウンロード
  static void downloadJson(String jsonText, String filename) {
    if (kIsWeb) {
      _downloadOnWeb(
          Uint8List.fromList(utf8.encode(jsonText)), filename, 'application/json');
    }
  }

  static void _downloadOnWeb(Uint8List bytes, String filename, String mime) {
    // JS 側で実行（dart:html は deprecated のため）
    _jsDownload(bytes, filename, mime);
  }

  static void _jsDownload(Uint8List bytes, String filename, String mime) {
    // JS Interop で実装（cesium_bridge.js の downloadBlob を呼び出す）
    // 実際の呼び出しは JsBridge 経由
  }
}

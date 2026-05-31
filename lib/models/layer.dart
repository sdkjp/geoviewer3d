import 'package:flutter/material.dart';

enum LayerType { pointCloud, pdf, glbModel, annotation }

class GeoPoint {
  final double lon;
  final double lat;
  final double height;
  const GeoPoint(this.lon, this.lat, this.height);

  factory GeoPoint.fromJson(Map<String, dynamic> j) =>
      GeoPoint(j['lon'] as double, j['lat'] as double, (j['height'] as num?)?.toDouble() ?? 0.0);

  Map<String, dynamic> toJson() => {'lon': lon, 'lat': lat, 'height': height};
}

class GcpPair {
  final GeoPoint mapPoint;     // 地図上の座標
  final List<double> pcPoint;  // 点群内座標 [x, y, z]
  const GcpPair({required this.mapPoint, required this.pcPoint});

  factory GcpPair.fromJson(Map<String, dynamic> j) => GcpPair(
        mapPoint: GeoPoint.fromJson(j['map'] as Map<String, dynamic>),
        pcPoint: List<double>.from(j['pc'] as List),
      );

  Map<String, dynamic> toJson() => {
        'map': mapPoint.toJson(),
        'pc': pcPoint,
      };
}

class MapLayer {
  final String id;
  final String name;
  final LayerType type;
  bool visible;
  double opacity;
  Color color;

  // 点群専用
  String? pointCloudFile;
  bool isProjected;             // true → 平面直角座標 (要 GCP)
  List<GcpPair> gcpPairs;      // GCP 登録済みペア
  Map<String, dynamic>? coordinateInfo;

  // PDF 専用
  String? pdfFile;
  List<GeoPoint> pdfCorners;   // 4隅の座標

  // GLB 専用
  String? glbUrl;
  GeoPoint? glbPosition;
  double glbHeading;
  double glbPitch;
  double glbRoll;
  double glbScale;

  MapLayer({
    required this.id,
    required this.name,
    required this.type,
    this.visible = true,
    this.opacity = 1.0,
    Color? color,
    this.pointCloudFile,
    this.isProjected = false,
    List<GcpPair>? gcpPairs,
    this.coordinateInfo,
    this.pdfFile,
    List<GeoPoint>? pdfCorners,
    this.glbUrl,
    this.glbPosition,
    this.glbHeading = 0,
    this.glbPitch = 0,
    this.glbRoll = 0,
    this.glbScale = 1.0,
  })  : color = color ?? const Color(0xFF4FC3F7),
        gcpPairs = gcpPairs ?? [],
        pdfCorners = pdfCorners ?? [];

  IconData get icon {
    switch (type) {
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'visible': visible,
        'opacity': opacity,
        'isProjected': isProjected,
        'gcpPairs': gcpPairs.map((g) => g.toJson()).toList(),
        'pdfCorners': pdfCorners.map((c) => c.toJson()).toList(),
        'glbUrl': glbUrl,
        'glbPosition': glbPosition?.toJson(),
        'glbHeading': glbHeading,
        'glbPitch': glbPitch,
        'glbRoll': glbRoll,
        'glbScale': glbScale,
      };
}

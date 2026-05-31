class Viewpoint {
  final double lon;
  final double lat;
  final double height;
  final double heading;
  final double pitch;
  String? label;
  DateTime? savedAt;

  Viewpoint({
    required this.lon,
    required this.lat,
    required this.height,
    required this.heading,
    required this.pitch,
    this.label,
    this.savedAt,
  });

  factory Viewpoint.fromJson(Map<String, dynamic> j) => Viewpoint(
        lon: (j['lon'] as num).toDouble(),
        lat: (j['lat'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
        heading: (j['heading'] as num).toDouble(),
        pitch: (j['pitch'] as num).toDouble(),
        label: j['label'] as String?,
        savedAt: j['savedAt'] != null ? DateTime.parse(j['savedAt'] as String) : null,
      );

  Map<String, dynamic> toJson() => {
        'lon': lon,
        'lat': lat,
        'height': height,
        'heading': heading,
        'pitch': pitch,
        'label': label,
        'savedAt': savedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      };

  String toShareJson() {
    final m = toJson();
    m['savedAt'] = DateTime.now().toIso8601String();
    return _prettyJson(m);
  }

  static String _prettyJson(Map<String, dynamic> m) {
    final buf = StringBuffer('{\n');
    m.forEach((k, v) {
      final val = v is String ? '"$v"' : v;
      buf.writeln('  "$k": $val,');
    });
    return '${buf.toString().trimRight().replaceAll(RegExp(r',$'), '')}\n}';
  }
}

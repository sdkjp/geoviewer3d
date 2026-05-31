import 'layer.dart';

class Annotation {
  final String id;
  String text;
  final GeoPoint position;
  final DateTime createdAt;
  String? author;
  String color;

  Annotation({
    required this.id,
    required this.text,
    required this.position,
    DateTime? createdAt,
    this.author,
    this.color = '#FF6B35',
  }) : createdAt = createdAt ?? DateTime.now();

  factory Annotation.fromJson(Map<String, dynamic> j) => Annotation(
        id: j['id'] as String,
        text: j['text'] as String,
        position: GeoPoint.fromJson(j['position'] as Map<String, dynamic>),
        createdAt: DateTime.parse(j['createdAt'] as String),
        author: j['author'] as String?,
        color: j['color'] as String? ?? '#FF6B35',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'position': position.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'author': author,
        'color': color,
      };
}

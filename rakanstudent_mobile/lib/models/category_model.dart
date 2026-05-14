class Category {
  const Category({
    required this.id,
    required this.userId,
    required this.name,
    required this.colorHex,
  });

  final String id;
  final String userId;
  final String name;
  final String colorHex;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      colorHex: _normalizeColorHex(json['color_hex'] ?? json['colorHex']),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'user_id': userId, 'name': name, 'color_hex': colorHex};
  }

  static String _normalizeColorHex(Object? value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return '#64748B';
    }

    final withHash = normalized.startsWith('#') ? normalized : '#$normalized';
    if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(withHash)) {
      return withHash.toUpperCase();
    }

    return '#64748B';
  }
}

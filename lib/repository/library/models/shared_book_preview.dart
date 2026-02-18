class SharedBookPreview {
  final String id;
  final String name;
  final String color;
  final String icon;
  final String? ownerDisplayName;
  final int gameCount;

  const SharedBookPreview({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    this.ownerDisplayName,
    required this.gameCount,
  });

  factory SharedBookPreview.fromJson(Map<String, dynamic> json) {
    return SharedBookPreview(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as String? ?? '#0FB4E5',
      icon: json['icon'] as String? ?? 'folder',
      ownerDisplayName: json['owner_display_name'] as String?,
      gameCount: (json['game_count'] as num?)?.toInt() ?? 0,
    );
  }
}

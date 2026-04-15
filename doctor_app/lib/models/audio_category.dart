class AudioCategory {
  final int id;
  final String name;
  final int? parentId;
  final List<AudioCategory> children;

  AudioCategory({
    required this.id,
    required this.name,
    this.parentId,
    this.children = const [],
  });

  factory AudioCategory.fromJson(Map<String, dynamic> json) => AudioCategory(
        id: json['id'],
        name: json['name'],
        parentId: json['parent_id'],
        children: (json['children'] as List<dynamic>?)
                ?.map((e) => AudioCategory.fromJson(e))
                .toList() ??
            [],
      );
}

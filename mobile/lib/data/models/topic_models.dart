class TopicCategory {
  final String id;
  final String name;
  final int level;
  final String? parentId;
  bool followed;

  TopicCategory({
    required this.id,
    required this.name,
    required this.level,
    this.parentId,
    required this.followed,
  });

  factory TopicCategory.fromJson(Map<String, dynamic> json) => TopicCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        level: json['level'] as int,
        parentId: json['parent_id'] as String?,
        followed: json['followed'] as bool,
      );
}

class TopicGroup {
  final TopicCategory parent;
  final List<TopicCategory> children;

  const TopicGroup({required this.parent, required this.children});
}

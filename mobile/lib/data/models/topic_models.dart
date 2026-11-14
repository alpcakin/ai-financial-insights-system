class TopicCategory {
  final String id;
  final String name;

  /// 1 for a sector, 2 for a category inside it; null for a topic users wrote.
  final int? level;
  final String? parentId;

  /// "category" for the fixed list, "topic" for a topic users added.
  final String kind;
  final bool followed;

  const TopicCategory({
    required this.id,
    required this.name,
    required this.level,
    this.parentId,
    this.kind = 'category',
    required this.followed,
  });

  bool get isOwnTopic => kind == 'topic';

  TopicCategory copyWith({bool? followed}) => TopicCategory(
        id: id,
        name: name,
        level: level,
        parentId: parentId,
        kind: kind,
        followed: followed ?? this.followed,
      );

  factory TopicCategory.fromJson(Map<String, dynamic> json) => TopicCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        level: json['level'] as int?,
        parentId: json['parent_id'] as String?,
        kind: json['kind'] as String? ?? 'category',
        followed: json['followed'] as bool,
      );
}

class TopicGroup {
  final TopicCategory parent;
  final List<TopicCategory> children;

  const TopicGroup({required this.parent, required this.children});
}

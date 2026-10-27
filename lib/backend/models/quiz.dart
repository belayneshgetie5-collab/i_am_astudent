class Quiz {
  const Quiz({
    required this.id,
    required this.title,
    required this.cachedAt,
    this.description,
    this.createdBy,
  });

  final String id;
  final String title;
  final String? description;
  final String? createdBy;
  final DateTime cachedAt;

  factory Quiz.fromMap(Map<String, Object?> map) => Quiz(
    id: map['id']! as String,
    title: map['title']! as String,
    description: map['description'] as String?,
    createdBy: map['created_by'] as String?,
    cachedAt: DateTime.parse(map['cached_at']! as String),
  );

  Map<String, Object?> toMap({bool isSynced = false}) => {
    'id': id,
    'title': title,
    'description': description,
    'created_by': createdBy,
    'cached_at': cachedAt.toUtc().toIso8601String(),
    'is_synced': isSynced ? 1 : 0,
  };
}

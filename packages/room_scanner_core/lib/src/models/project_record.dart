class ProjectRecord {
  final int id;
  final String uuid;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProjectRecord({
    required this.id,
    required this.uuid,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  ProjectRecord copyWith({
    int? id,
    String? uuid,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProjectRecord(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Resumen de un proyecto guardado, independiente del motor de persistencia.
///
/// La UI trabaja con este tipo en lugar de las colecciones Isar, de modo que
/// cambiar el backend local no obliga a tocar pantallas ni providers.
class ProjectSummary {
  final String uuid;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProjectSummary({
    required this.uuid,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  bool operator ==(Object other) =>
      other is ProjectSummary &&
      other.uuid == uuid &&
      other.name == name &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(uuid, name, createdAt, updatedAt);
}

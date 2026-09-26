import '../models/isar_models.dart';
import '../models/room_model.dart';
import 'local_database_service.dart';
import 'project_repository.dart';
import 'project_summary.dart';

/// Implementación de [ProjectRepository] sobre Isar Community.
///
/// Delega en [LocalDatabaseService] sin cambiar el formato persistido.
class IsarProjectRepository implements ProjectRepository {
  final LocalDatabaseService _database;

  IsarProjectRepository(this._database);

  /// Repositorio sobre la base local por defecto de la aplicación.
  factory IsarProjectRepository.local() {
    return IsarProjectRepository(LocalDatabaseService());
  }

  @override
  Future<void> open({required String directoryPath}) {
    return _database.init(directoryPath: directoryPath);
  }

  @override
  Future<List<ProjectSummary>> getAllProjects() async {
    final projects = await _database.getAllProjects();
    return projects.map(toSummary).toList(growable: false);
  }

  @override
  Future<List<RoomModel>> getRoomsForProject(String uuid) {
    return _database.getRoomsForProject(uuid);
  }

  @override
  Future<void> saveProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) {
    return _database.saveProject(uuid: uuid, name: name, rooms: rooms);
  }

  @override
  Future<void> deleteProject(String uuid) {
    return _database.deleteProject(uuid);
  }

  /// Convierte la colección Isar al modelo de dominio.
  static ProjectSummary toSummary(IsarProject project) {
    return ProjectSummary(
      uuid: project.uuid,
      name: project.name,
      createdAt: project.createdAt,
      updatedAt: project.updatedAt,
    );
  }
}

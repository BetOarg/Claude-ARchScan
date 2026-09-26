import '../models/room_model.dart';
import 'project_summary.dart';

/// Contrato de persistencia local de proyectos.
///
/// Es la frontera entre la aplicación y el motor de almacenamiento. La
/// implementación actual es [IsarProjectRepository]; un backend futuro debe
/// respetar el mismo comportamiento observable.
abstract interface class ProjectRepository {
  /// Abre el almacenamiento local en [directoryPath].
  Future<void> open({required String directoryPath});

  /// Proyectos ordenados por fecha de actualización descendente.
  Future<List<ProjectSummary>> getAllProjects();

  /// Ambientes del proyecto [uuid], o una lista vacía si no existe.
  Future<List<RoomModel>> getRoomsForProject(String uuid);

  /// Crea o reemplaza el proyecto [uuid] con sus ambientes completos.
  Future<void> saveProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  });

  /// Elimina el proyecto [uuid] y todos sus ambientes.
  Future<void> deleteProject(String uuid);
}

import '../models/project_record.dart';
import '../models/room_model.dart';

abstract interface class ProjectRepository {
  Future<void> init({required String directoryPath});
  Future<List<ProjectRecord>> getAllProjects();
  Future<List<RoomModel>> getRoomsForProject(String uuid);
  Future<void> saveProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  });
  Future<void> deleteProject(String uuid);
}

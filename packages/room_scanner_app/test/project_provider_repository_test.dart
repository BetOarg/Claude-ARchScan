import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/providers/project_provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

class _InMemoryProjectRepository implements ProjectRepository {
  final Map<String, ProjectSummary> projects = {};
  final Map<String, List<RoomModel>> rooms = {};
  int _clock = 0;

  DateTime _tick() => DateTime(2026, 1, 1).add(Duration(minutes: _clock++));

  @override
  Future<void> open({required String directoryPath}) async {}

  @override
  Future<List<ProjectSummary>> getAllProjects() async {
    final list = projects.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<List<RoomModel>> getRoomsForProject(String uuid) async {
    return List<RoomModel>.of(rooms[uuid] ?? const <RoomModel>[]);
  }

  @override
  Future<void> saveProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) async {
    final now = _tick();
    final existing = projects[uuid];
    projects[uuid] = ProjectSummary(
      uuid: uuid,
      name: name,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    this.rooms[uuid] = List<RoomModel>.of(rooms);
  }

  @override
  Future<void> deleteProject(String uuid) async {
    projects.remove(uuid);
    rooms.remove(uuid);
  }
}

void main() {
  test('guarda y lista proyectos a través del repositorio', () async {
    final repository = _InMemoryProjectRepository();
    final provider = ProjectProvider(repository: repository);

    await provider.saveCurrentProject(uuid: 'a', name: 'A', rooms: const []);
    await provider.saveCurrentProject(uuid: 'b', name: 'B', rooms: const []);

    expect(provider.projects.map((p) => p.uuid), ['b', 'a']);
    expect(provider.isLoading, isFalse);
  });

  test('renombrar conserva UUID y actualiza el proyecto actual', () async {
    final repository = _InMemoryProjectRepository();
    final provider = ProjectProvider(repository: repository);

    await provider.saveCurrentProject(uuid: 'a', name: 'A', rooms: const []);
    await provider.selectProject(provider.projects.single);
    await provider.renameProject(uuid: 'a', name: '  Living  ');

    expect(provider.projects.single.uuid, 'a');
    expect(provider.projects.single.name, 'Living');
    expect(provider.currentProject?.name, 'Living');
  });

  test('un nombre vacío no modifica el proyecto', () async {
    final repository = _InMemoryProjectRepository();
    final provider = ProjectProvider(repository: repository);

    await provider.saveCurrentProject(uuid: 'a', name: 'A', rooms: const []);
    await provider.renameProject(uuid: 'a', name: '   ');

    expect(provider.projects.single.name, 'A');
  });
}

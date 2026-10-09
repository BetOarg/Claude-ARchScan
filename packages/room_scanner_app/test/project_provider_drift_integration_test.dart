import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/providers/project_provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ProjectProvider persists and reloads through its injected Drift repository',
      () async {
    final database = ArchScanDatabase.inMemory();
    final repository = DriftProjectRepository(database: database);
    final provider = ProjectProvider(repository: repository);
    addTearDown(provider.dispose);

    final room = RoomModel(
      id: 'room-1',
      name: 'Dormitorio',
      type: RoomType.dormitorio,
      isClosed: true,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 3),
        ARPoint(x: 0, y: 0, z: 3),
      ],
    );

    await provider.saveCurrentProject(
      uuid: 'project-1',
      name: 'Casa',
      rooms: [room],
    );

    expect(provider.projects, hasLength(1));
    expect(provider.projects.single.uuid, 'project-1');
    expect(provider.projects.single.name, 'Casa');

    final loaded = await provider.selectProject(provider.projects.single);
    expect(loaded.single.toJson(), room.toJson());

    await provider.renameProject(uuid: 'project-1', name: 'Casa renovada');

    expect(provider.currentProject?.name, 'Casa renovada');
    expect((await repository.getAllProjects()).single.name, 'Casa renovada');
    expect(
      (await repository.getRoomsForProject('project-1')).single.toJson(),
      room.toJson(),
    );

    await provider.deleteProject('project-1');

    expect(provider.projects, isEmpty);
    expect(provider.currentProject, isNull);
    expect(await repository.getAllProjects(), isEmpty);
    expect(await repository.getRoomsForProject('project-1'), isEmpty);

    // Simulate a repository write that has not yet appeared in the provider's
    // in-memory list. "Delete all" must use the authoritative persisted state.
    await provider.saveCurrentProject(
      uuid: 'project-2',
      name: 'Casa dos',
      rooms: [room],
    );
    await provider.selectProject(provider.projects.single);
    await repository.saveProject(
      uuid: 'project-3',
      name: 'Casa externa',
      rooms: [room],
    );

    await provider.deleteAllLocalProjects();

    expect(provider.projects, isEmpty);
    expect(provider.currentProject, isNull);
    expect(await repository.getAllProjects(), isEmpty);
    expect(await repository.getRoomsForProject('project-2'), isEmpty);
    expect(await repository.getRoomsForProject('project-3'), isEmpty);
  });
}

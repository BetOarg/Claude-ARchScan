import 'dart:io';

import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDirectory;
  late DriftProjectRepository repository;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('archscan_drift_');
    repository = DriftProjectRepository.local();
    await repository.open(directoryPath: tempDirectory.path);
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  test('guarda, recupera y lista un proyecto con sus ambientes', () async {
    final createdAtRoom = RoomModel(
      id: 'room-1',
      name: 'Living',
      type: RoomType.living,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 3, y: 0, z: 0),
        ARPoint(x: 3, y: 0, z: 4),
      ],
      isClosed: true,
    );

    await repository.saveProject(
      uuid: 'project-1',
      name: 'Departamento',
      rooms: [createdAtRoom],
    );

    final projects = await repository.getAllProjects();
    expect(projects, hasLength(1));
    expect(projects.single.uuid, 'project-1');
    expect(projects.single.name, 'Departamento');

    final rooms = await repository.getRoomsForProject('project-1');
    expect(rooms, hasLength(1));
    expect(rooms.single.name, 'Living');
    expect(rooms.single.points, hasLength(3));
    expect(rooms.single.isClosed, isTrue);
  });

  test('actualizar conserva la fecha de creación y reemplaza ambientes', () async {
    await repository.saveProject(
      uuid: 'project-1',
      name: 'Original',
      rooms: const [],
    );

    final first = (await repository.getAllProjects()).single;

    await repository.saveProject(
      uuid: 'project-1',
      name: 'Renombrado',
      rooms: const [],
    );

    final second = (await repository.getAllProjects()).single;
    expect(second.uuid, 'project-1');
    expect(second.name, 'Renombrado');
    expect(second.createdAt, first.createdAt);
    expect(second.updatedAt.isAfter(first.updatedAt) ||
        second.updatedAt.isAtSameMomentAs(first.updatedAt), isTrue);
  });

  test('conserva el proyecto al cerrar y reabrir el repositorio', () async {
    await repository.saveProject(
      uuid: 'project-persistent',
      name: 'Persistente',
      rooms: const [],
    );

    await repository.close();

    final reopened = DriftProjectRepository.local();
    await reopened.open(directoryPath: tempDirectory.path);

    addTearDown(reopened.close);

    final projects = await reopened.getAllProjects();
    expect(projects, hasLength(1));
    expect(projects.single.uuid, 'project-persistent');
    expect(projects.single.name, 'Persistente');
  });

  test('guardar el mismo UUID reemplaza el proyecto sin duplicarlo', () async {
    await repository.saveProject(
      uuid: 'project-1',
      name: 'Primero',
      rooms: const [],
    );

    await repository.saveProject(
      uuid: 'project-1',
      name: 'Segundo',
      rooms: const [],
    );

    final projects = await repository.getAllProjects();
    expect(projects, hasLength(1));
    expect(projects.single.name, 'Segundo');
  });

  test('eliminar un proyecto también elimina sus datos asociados', () async {
    await repository.saveProject(
      uuid: 'project-1',
      name: 'A',
      rooms: const [],
    );

    await repository.deleteProject('project-1');

    expect(await repository.getAllProjects(), isEmpty);
    expect(await repository.getRoomsForProject('project-1'), isEmpty);
  });
}

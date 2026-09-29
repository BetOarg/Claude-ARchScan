import 'package:test/test.dart';

import '../lib/src/models/room_model.dart';
import '../lib/src/persistence/drift_database.dart';
import '../lib/src/persistence/drift_project_repository.dart';

void main() {
  late ArchScanDatabase database;
  late DriftProjectRepository repository;

  setUp(() {
    database = ArchScanDatabase.inMemory();
    repository = DriftProjectRepository(database: database);
  });

  tearDown(() async {
    await repository.dispose();
  });

  test('round-trips projects, 3D points, walls and openings', () async {
    final room = RoomModel(
      id: 'room-1',
      name: 'Living',
      type: RoomType.living,
      isClosed: true,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 0),
        ARPoint(x: 4, y: 3, z: 0),
      ],
      features: [
        WallFeature(
          id: 'door-1',
          type: FeatureType.door,
          start: ARPoint(x: 0.5, y: 0, z: 0),
          end: ARPoint(x: 1.4, y: 0, z: 0),
          doorHingeSide: DoorHingeSide.end,
          doorSwingSide: DoorSwingSide.right,
          doorOpeningDirection: DoorOpeningDirection.exterior,
          openingHeightMeters: 2.1,
          sillHeightMeters: 0,
        ),
      ],
    );

    await repository.saveProject(
      uuid: 'project-1',
      name: 'Test project',
      rooms: [room],
    );

    final projects = await repository.getAllProjects();
    final rooms = await repository.getRoomsForProject('project-1');

    expect(projects, hasLength(1));
    expect(projects.single.uuid, 'project-1');
    expect(projects.single.name, 'Test project');
    expect(rooms, hasLength(1));
    expect(rooms.single.id, room.id);
    expect(rooms.single.isClosed, isTrue);
    expect(rooms.single.points, hasLength(3));
    expect(rooms.single.points[1].x, 4);
    expect(rooms.single.points[2].y, 3);
    expect(rooms.single.features, hasLength(1));
    expect(rooms.single.features.single.id, 'door-1');
    expect(
      rooms.single.features.single.doorOpeningDirection,
      DoorOpeningDirection.exterior,
    );
  });

  test('replacing a project does not duplicate rooms, points or features', () async {
    final initial = RoomModel(
      id: 'room-1',
      name: 'Room',
      type: RoomType.living,
      points: [ARPoint(x: 0, y: 0, z: 0)],
    );

    await repository.saveProject(
      uuid: 'project-1',
      name: 'Project',
      rooms: [initial],
    );

    final updated = initial.copyWith(
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 1, y: 0, z: 0),
      ],
    );

    await repository.saveProject(
      uuid: 'project-1',
      name: 'Project renamed',
      rooms: [updated],
    );

    final rooms = await repository.getRoomsForProject('project-1');
    expect(rooms, hasLength(1));
    expect(rooms.single.points, hasLength(2));
    expect((await repository.getAllProjects()).single.name, 'Project renamed');
  });

  test('deleting a project removes its rooms and dependent rows', () async {
    final room = RoomModel(
      id: 'room-1',
      name: 'Room',
      type: RoomType.living,
      points: [ARPoint(x: 0, y: 0, z: 0)],
      features: [
        WallFeature(
          id: 'window-1',
          type: FeatureType.window,
          start: ARPoint(x: 0, y: 0, z: 0),
          end: ARPoint(x: 1, y: 0, z: 0),
        ),
      ],
    );

    await repository.saveProject(
      uuid: 'project-1',
      name: 'Project',
      rooms: [room],
    );

    await repository.deleteProject('project-1');

    expect(await repository.getAllProjects(), isEmpty);
    expect(await repository.getRoomsForProject('project-1'), isEmpty);
  });
}

import 'dart:io';

import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late DriftProjectRepository repository;
  late ArchScanDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('archscan-integrity-');
    database = ArchScanDatabase('${directory.path}/archscan.sqlite');
    repository = DriftProjectRepository(database: database);
  });

  tearDown(() async {
    await repository.dispose();
    await directory.delete(recursive: true);
  });

  RoomModel room(String id, double x) {
    return RoomModel(
      id: id,
      name: 'Room $id',
      type: RoomType.living,
      isClosed: true,
      points: [
        ARPoint(x: x, y: 0.123456789, z: -0.987654321),
        ARPoint(x: x + 2.345678901, y: 0, z: 3.456789012),
      ],
      features: [
        WallFeature(
          id: 'opening-$id',
          type: FeatureType.window,
          start: ARPoint(x: x + 0.123456789, y: 0, z: 0.25),
          end: ARPoint(x: x + 1.234567891, y: 0, z: 0.25),
          connectedRoomId: null,
          connectionSide: null,
          openingHeightMeters: 1.23456789,
          sillHeightMeters: 0.87654321,
        ),
      ],
    );
  }

  test('failed project deletion rolls back child deletions', () async {
    final originalRoom = room('room-protected', 1.23456789);
    await repository.saveProject(
      uuid: 'project-protected',
      name: 'Must survive failed deletion',
      rooms: [originalRoom],
    );

    await database.customStatement('''
      CREATE TRIGGER reject_project_delete
      BEFORE DELETE ON projects
      BEGIN
        SELECT RAISE(ABORT, 'forced project delete failure');
      END;
    ''');

    await expectLater(
      repository.deleteProject('project-protected'),
      throwsA(anything),
    );

    final projects = await repository.getAllProjects();
    final restoredRooms = await repository.getRoomsForProject(
      'project-protected',
    );
    expect(projects, hasLength(1));
    expect(projects.single.uuid, 'project-protected');
    expect(projects.single.name, 'Must survive failed deletion');
    expect(restoredRooms, hasLength(1));
    expect(restoredRooms.single.id, originalRoom.id);
    expect(restoredRooms.single.points.first.x, closeTo(1.23456789, 1e-12));
    expect(restoredRooms.single.points.last.x, closeTo(3.580246791, 1e-12));
    expect(
      restoredRooms.single.features.single.id,
      'opening-room-protected',
    );
  });

  test('concurrent saves never mix child rows from different snapshots',
      () async {
    final roomA = room('snapshot-a', 10);
    final roomB = room('snapshot-b', 20);

    await Future.wait([
      repository.saveProject(
        uuid: 'project-concurrent',
        name: 'Snapshot A',
        rooms: [roomA],
      ),
      repository.saveProject(
        uuid: 'project-concurrent',
        name: 'Snapshot B',
        rooms: [roomB],
      ),
    ]);

    final projects = await repository.getAllProjects();
    final rooms = await repository.getRoomsForProject('project-concurrent');
    expect(projects, hasLength(1));
    expect(rooms, hasLength(1));

    if (projects.single.name == 'Snapshot A') {
      expect(rooms.single.id, 'snapshot-a');
      expect(rooms.single.features.single.id, 'opening-snapshot-a');
    } else {
      expect(projects.single.name, 'Snapshot B');
      expect(rooms.single.id, 'snapshot-b');
      expect(rooms.single.features.single.id, 'opening-snapshot-b');
    }
  });

  test(
    'file-backed reopen preserves precise geometry and nullable opening metadata',
    () async {
      final originalRoom = room('room-precision', 1.23456789);
      await repository.saveProject(
        uuid: 'project-precision',
        name: 'Precision and nullability',
        rooms: [originalRoom],
      );
      await repository.dispose();

      repository = DriftProjectRepository();
      await repository.init(directoryPath: directory.path);

      final projects = await repository.getAllProjects();
      final restoredRooms = await repository.getRoomsForProject(
        'project-precision',
      );

      expect(projects, hasLength(1));
      expect(projects.single.name, 'Precision and nullability');
      expect(restoredRooms, hasLength(1));
      expect(restoredRooms.single.isClosed, isTrue);
      expect(restoredRooms.single.points.first.x, 1.23456789);
      expect(restoredRooms.single.points.first.y, 0.123456789);
      expect(restoredRooms.single.points.last.x, closeTo(3.580246791, 1e-12));
      expect(
        restoredRooms.single.features.single.start.x,
        closeTo(1.358024679, 1e-12),
      );
      expect(
        restoredRooms.single.features.single.openingHeightMeters,
        1.23456789,
      );
      expect(
        restoredRooms.single.features.single.sillHeightMeters,
        0.87654321,
      );
      expect(restoredRooms.single.features.single.connectedRoomId, isNull);
      expect(restoredRooms.single.features.single.connectionSide, isNull);
    },
  );

  test(
    'file-backed reopen preserves door orientation and connected-opening metadata',
    () async {
      final roomWithOpenings = RoomModel(
        id: 'room-openings',
        name: 'Room with openings',
        type: RoomType.living,
        isClosed: true,
        points: [
          ARPoint(x: 0.123456789, y: 0, z: 0),
          ARPoint(x: 4.987654321, y: 0, z: 3.141592653),
        ],
        features: [
          WallFeature(
            id: 'door-connected',
            type: FeatureType.door,
            start: ARPoint(x: 1.123456789, y: 0.1, z: 0.25),
            end: ARPoint(x: 2.234567891, y: 0.1, z: 0.25),
            connectedRoomId: 'room-adjacent',
            connectionSide: OpeningConnectionSide.right,
            doorHingeSide: DoorHingeSide.end,
            doorSwingSide: DoorSwingSide.right,
            doorOpeningDirection: DoorOpeningDirection.exterior,
            openingHeightMeters: 2.045678901,
            sillHeightMeters: 0.012345678,
          ),
          WallFeature(
            id: 'window-unconnected',
            type: FeatureType.window,
            start: ARPoint(x: 2.5, y: 0.4, z: 1.25),
            end: ARPoint(x: 3.5, y: 0.4, z: 1.25),
            connectedRoomId: null,
            connectionSide: null,
            openingHeightMeters: 1.456789012,
            sillHeightMeters: 0.765432109,
          ),
        ],
      );

      await repository.saveProject(
        uuid: 'project-openings',
        name: 'Opening metadata',
        rooms: [roomWithOpenings],
      );
      await repository.dispose();

      repository = DriftProjectRepository();
      await repository.init(directoryPath: directory.path);

      final restoredRooms = await repository.getRoomsForProject(
        'project-openings',
      );
      expect(restoredRooms, hasLength(1));
      final restored = restoredRooms.single;
      expect(restored.isClosed, isTrue);
      expect(restored.points.first.x, 0.123456789);
      expect(restored.points.last.z, 3.141592653);
      expect(restored.features, hasLength(2));

      final door = restored.features.first;
      expect(door.id, 'door-connected');
      expect(door.type, FeatureType.door);
      expect(door.start.x, 1.123456789);
      expect(door.end.x, 2.234567891);
      expect(door.connectedRoomId, 'room-adjacent');
      expect(door.connectionSide, OpeningConnectionSide.right);
      expect(door.doorHingeSide, DoorHingeSide.end);
      expect(door.doorSwingSide, DoorSwingSide.right);
      expect(door.doorOpeningDirection, DoorOpeningDirection.exterior);
      expect(door.openingHeightMeters, 2.045678901);
      expect(door.sillHeightMeters, 0.012345678);

      final window = restored.features.last;
      expect(window.id, 'window-unconnected');
      expect(window.type, FeatureType.window);
      expect(window.connectedRoomId, isNull);
      expect(window.connectionSide, isNull);
      expect(window.openingHeightMeters, 1.456789012);
      expect(window.sillHeightMeters, 0.765432109);
    },
  );

}

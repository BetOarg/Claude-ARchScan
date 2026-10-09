import 'dart:io';

import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late DriftProjectRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('archscan-integrity-');
    repository = DriftProjectRepository();
    await repository.init(directoryPath: directory.path);
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

    final database = ArchScanDatabase(
      '${directory.path}/archscan.sqlite',
    );
    try {
      await database.customStatement('''
        CREATE TRIGGER reject_project_delete
        BEFORE DELETE ON projects
        BEGIN
          SELECT RAISE(ABORT, 'forced project delete failure');
        END;
      ''');
    } finally {
      await database.close();
    }

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
    expect(restoredRooms.single.points.map((point) => point.x), [
      1.23456789,
      3.580246791,
    ]);
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
      expect(restoredRooms.single.points.last.x, 3.580246791);
      expect(restoredRooms.single.features.single.start.x, 1.358024679);
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
}

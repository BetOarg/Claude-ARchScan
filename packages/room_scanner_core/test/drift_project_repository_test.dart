import 'dart:io';

import 'package:drift/drift.dart';
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
          connectedRoomId: 'room-2',
          connectionSide: OpeningConnectionSide.right,
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
    expect(rooms.single.features.single.connectedRoomId, 'room-2');
    expect(
      rooms.single.features.single.connectionSide,
      OpeningConnectionSide.right,
    );
    expect(
      rooms.single.features.single.doorOpeningDirection,
      DoorOpeningDirection.exterior,
    );
  });

  test('rolls back a project replacement when a child insert fails', () async {
    final originalRoom = RoomModel(
      id: 'room-original',
      name: 'Original room',
      type: RoomType.living,
      points: [
        ARPoint(x: 1, y: 0, z: 1),
        ARPoint(x: 2, y: 0, z: 1),
      ],
      features: [
        WallFeature(
          id: 'original-window',
          type: FeatureType.window,
          start: ARPoint(x: 1, y: 0, z: 1),
          end: ARPoint(x: 2, y: 0, z: 1),
        ),
      ],
    );

    await repository.saveProject(
      uuid: 'project-rollback',
      name: 'Original project',
      rooms: [originalRoom],
    );

    await database.customStatement('''
      CREATE TRIGGER fail_feature_insert
      BEFORE INSERT ON wall_features_table
      BEGIN
        SELECT RAISE(ABORT, 'forced feature insert failure');
      END;
    ''');

    final replacementRoom = RoomModel(
      id: 'room-replacement',
      name: 'Replacement room',
      type: RoomType.cocina,
      points: [ARPoint(x: 9, y: 0, z: 9)],
      features: [
        WallFeature(
          id: 'replacement-door',
          type: FeatureType.door,
          start: ARPoint(x: 9, y: 0, z: 9),
          end: ARPoint(x: 10, y: 0, z: 9),
        ),
      ],
    );

    await expectLater(
      repository.saveProject(
        uuid: 'project-rollback',
        name: 'Replacement project',
        rooms: [replacementRoom],
      ),
      throwsA(anything),
    );

    final projects = await repository.getAllProjects();
    final restored = await repository.getRoomsForProject('project-rollback');

    expect(projects, hasLength(1));
    expect(projects.single.name, 'Original project');
    expect(restored, hasLength(1));
    expect(restored.single.id, 'room-original');
    expect(restored.single.points.map((point) => point.x), [1, 2]);
    expect(restored.single.features.single.id, 'original-window');
  });

  test('round-trips complete door metadata and opening dimensions', () async {
    final door = WallFeature(
      id: 'door-complete',
      type: FeatureType.door,
      start: ARPoint(x: 1, y: 2, z: 3),
      end: ARPoint(x: 2, y: 2, z: 3),
      doorHingeSide: DoorHingeSide.end,
      doorSwingSide: DoorSwingSide.right,
      doorOpeningDirection: DoorOpeningDirection.exterior,
      connectedRoomId: 'room-connected',
      connectionSide: OpeningConnectionSide.right,
      openingHeightMeters: 2.15,
      sillHeightMeters: 0.25,
    );

    await repository.saveProject(
      uuid: 'project-door-metadata',
      name: 'Door metadata',
      rooms: [
        RoomModel(
          id: 'room-door',
          name: 'Room',
          type: RoomType.living,
          points: [ARPoint(x: 0, y: 0, z: 0)],
          features: [door],
        ),
      ],
    );

    final restored = (await repository.getRoomsForProject(
      'project-door-metadata',
    )).single.features.single;

    expect(restored.id, door.id);
    expect(restored.type, FeatureType.door);
    expect(restored.start.x, door.start.x);
    expect(restored.start.y, door.start.y);
    expect(restored.start.z, door.start.z);
    expect(restored.end.x, door.end.x);
    expect(restored.end.y, door.end.y);
    expect(restored.end.z, door.end.z);
    expect(restored.doorHingeSide, DoorHingeSide.end);
    expect(restored.doorSwingSide, DoorSwingSide.right);
    expect(restored.doorOpeningDirection, DoorOpeningDirection.exterior);
    expect(restored.connectedRoomId, 'room-connected');
    expect(restored.connectionSide, OpeningConnectionSide.right);
    expect(restored.openingHeightMeters, 2.15);
    expect(restored.sillHeightMeters, 0.25);
  });

  test('round-trips connected rooms with a shared opening on both sides', () async {
    final sharedA = WallFeature(
      id: 'shared-door',
      type: FeatureType.door,
      start: ARPoint(x: 2, y: 0, z: 0.5),
      end: ARPoint(x: 2, y: 0, z: 1.5),
      connectedRoomId: 'room-b',
      connectionSide: OpeningConnectionSide.right,
      doorHingeSide: DoorHingeSide.end,
      doorSwingSide: DoorSwingSide.right,
      doorOpeningDirection: DoorOpeningDirection.exterior,
      openingHeightMeters: 2.15,
      sillHeightMeters: 0.25,
    );
    final sharedB = sharedA.copyWith(
      connectedRoomId: 'room-a',
      connectionSide: OpeningConnectionSide.left,
    );

    await repository.saveProject(
      uuid: 'project-connected',
      name: 'Connected rooms',
      rooms: [
        RoomModel(
          id: 'room-a',
          name: 'Living',
          type: RoomType.living,
          isClosed: true,
          points: [
            ARPoint(x: 0, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 2),
            ARPoint(x: 0, y: 0, z: 2),
          ],
          features: [sharedA],
        ),
        RoomModel(
          id: 'room-b',
          name: 'Cocina',
          type: RoomType.cocina,
          isClosed: true,
          points: [
            ARPoint(x: 2, y: 0, z: 0),
            ARPoint(x: 4, y: 0, z: 0),
            ARPoint(x: 4, y: 0, z: 2),
            ARPoint(x: 2, y: 0, z: 2),
          ],
          features: [sharedB],
        ),
      ],
    );

    final restored = await repository.getRoomsForProject('project-connected');

    expect(restored.map((room) => room.id), ['room-a', 'room-b']);
    final restoredA = restored.firstWhere((room) => room.id == 'room-a');
    final restoredB = restored.firstWhere((room) => room.id == 'room-b');
    final doorA = restoredA.features.single;
    final doorB = restoredB.features.single;

    expect(doorA.id, 'shared-door');
    expect(doorB.id, 'shared-door');
    expect(doorA.connectedRoomId, 'room-b');
    expect(doorB.connectedRoomId, 'room-a');
    expect(doorA.connectionSide, OpeningConnectionSide.right);
    expect(doorB.connectionSide, OpeningConnectionSide.left);
    expect(doorA.start.x, doorB.start.x);
    expect(doorA.start.z, doorB.start.z);
    expect(doorA.end.x, doorB.end.x);
    expect(doorA.end.z, doorB.end.z);
    expect(doorA.openingHeightMeters, 2.15);
    expect(doorA.sillHeightMeters, 0.25);
  });

  test('round-trips shared opening with reciprocal endpoint orientation after reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'archscan-drift-shared-orientation-',
    );
    final firstRepository = DriftProjectRepository();

    final sharedA = WallFeature(
      id: 'shared-reversed',
      type: FeatureType.door,
      start: ARPoint(x: 1, y: 0, z: 0),
      end: ARPoint(x: 2, y: 0, z: 0),
      connectedRoomId: 'room-b',
      connectionSide: OpeningConnectionSide.right,
    );
    final sharedB = sharedA.copyWith(
      connectedRoomId: 'room-a',
      connectionSide: OpeningConnectionSide.left,
      start: ARPoint(x: 2, y: 0, z: 0),
      end: ARPoint(x: 1, y: 0, z: 0),
    );

    final rooms = [
      RoomModel(
        id: 'room-a',
        name: 'A',
        type: RoomType.living,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 2),
          ARPoint(x: 0, y: 0, z: 2),
        ],
        features: [sharedA],
      ),
      RoomModel(
        id: 'room-b',
        name: 'B',
        type: RoomType.cocina,
        points: [
          ARPoint(x: 3, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: -2),
          ARPoint(x: 0, y: 0, z: -2),
          ARPoint(x: 0, y: 0, z: 0),
        ],
        features: [sharedB],
      ),
    ];

    try {
      await firstRepository.init(directoryPath: directory.path);
      await firstRepository.saveProject(
        uuid: 'project-connected-reversed',
        name: 'Connected reversed',
        rooms: rooms,
      );
      await firstRepository.dispose();

      final secondRepository = DriftProjectRepository();
      try {
        await secondRepository.init(directoryPath: directory.path);
        final restored = await secondRepository.getRoomsForProject(
          'project-connected-reversed',
        );
        final doorA = restored.first.features.single;
        final doorB = restored.last.features.single;

        expect(doorA.connectedRoomId, 'room-b');
        expect(doorB.connectedRoomId, 'room-a');
        expect(doorA.connectionSide, OpeningConnectionSide.right);
        expect(doorB.connectionSide, OpeningConnectionSide.left);
        expect(doorA.start.x, 1);
        expect(doorA.end.x, 2);
        expect(doorB.start.x, 2);
        expect(doorB.end.x, 1);
      } finally {
        await secondRepository.dispose();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('round-trips every persisted enum by name', () async {
    final rooms = RoomType.values
        .asMap()
        .entries
        .map(
          (entry) => RoomModel(
            id: 'room-enum-${entry.key}',
            name: entry.value.name,
            type: entry.value,
            points: [ARPoint(x: entry.key.toDouble(), y: 0, z: 0)],
            features: [
              WallFeature(
                id: 'feature-enum-${entry.key}',
                type: entry.key.isEven ? FeatureType.door : FeatureType.window,
                start: ARPoint(x: 0, y: 0, z: 0),
                end: ARPoint(x: 1, y: 0, z: 0),
                doorHingeSide: DoorHingeSide.values[entry.key % DoorHingeSide.values.length],
                doorSwingSide: DoorSwingSide.values[entry.key % DoorSwingSide.values.length],
                doorOpeningDirection: DoorOpeningDirection.values[
                  entry.key % DoorOpeningDirection.values.length
                ],
                connectionSide: OpeningConnectionSide.values[
                  entry.key % OpeningConnectionSide.values.length
                ],
              ),
            ],
          ),
        )
        .toList();

    await repository.saveProject(
      uuid: 'project-enums',
      name: 'Enum project',
      rooms: rooms,
    );

    final restored = await repository.getRoomsForProject('project-enums');

    expect(restored.map((room) => room.type), RoomType.values);
    expect(
      restored.map((room) => room.features.single.type),
      rooms.map((room) => room.features.single.type),
    );
    expect(
      restored.map((room) => room.features.single.doorHingeSide),
      rooms.map((room) => room.features.single.doorHingeSide),
    );
    expect(
      restored.map((room) => room.features.single.doorSwingSide),
      rooms.map((room) => room.features.single.doorSwingSide),
    );
    expect(
      restored.map((room) => room.features.single.doorOpeningDirection),
      rooms.map((room) => room.features.single.doorOpeningDirection),
    );
    expect(
      restored.map((room) => room.features.single.connectionSide),
      rooms.map((room) => room.features.single.connectionSide),
    );
  });

  test('rejects unknown persisted enum values instead of remapping data', () async {
    await repository.saveProject(
      uuid: 'project-invalid-enum',
      name: 'Enum validation',
      rooms: [
        RoomModel(
          id: 'room-enum-validation',
          name: 'Room',
          type: RoomType.living,
          points: [ARPoint(x: 0, y: 0, z: 0)],
          features: [
            WallFeature(
              id: 'door-enum-validation',
              type: FeatureType.door,
              start: ARPoint(x: 0, y: 0, z: 0),
              end: ARPoint(x: 1, y: 0, z: 0),
              connectionSide: OpeningConnectionSide.left,
            ),
          ],
        ),
      ],
    );

    await database.customStatement(
      "UPDATE rooms SET type = 'future_room_type'",
    );
    await expectLater(
      repository.getRoomsForProject('project-invalid-enum'),
      throwsA(isA<StateError>()),
    );
    await database.customStatement("UPDATE rooms SET type = 'living'");

    final invalidFeatureColumns = <String, String>{
      'type': 'future_feature_type',
      'hinge_side': 'future_hinge_side',
      'swing_side': 'future_swing_side',
      'opening_direction': 'future_opening_direction',
      'connection_side': 'future_connection_side',
    };
    for (final entry in invalidFeatureColumns.entries) {
      await database.customStatement(
        "UPDATE wall_features_table SET ${entry.key} = '${entry.value}'",
      );
      await expectLater(
        repository.getRoomsForProject('project-invalid-enum'),
        throwsA(isA<StateError>()),
        reason: 'Unknown ${entry.key} must not silently change saved data',
      );
      final validValue = switch (entry.key) {
        'type' => 'door',
        'hinge_side' => 'start',
        'swing_side' => 'left',
        'opening_direction' => 'interior',
        'connection_side' => 'left',
        _ => throw StateError('Unexpected test column ${entry.key}'),
      };
      await database.customStatement(
        "UPDATE wall_features_table SET ${entry.key} = '$validValue'",
      );
    }
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

  test('replacing a project removes stale child rows', () async {
    final initial = RoomModel(
      id: 'room-stale',
      name: 'Room',
      type: RoomType.living,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 1, y: 0, z: 0),
      ],
      features: [
        WallFeature(
          id: 'window-stale',
          type: FeatureType.window,
          start: ARPoint(x: 0, y: 0, z: 0),
          end: ARPoint(x: 1, y: 0, z: 0),
        ),
      ],
    );

    await repository.saveProject(
      uuid: 'project-stale',
      name: 'Project',
      rooms: [initial],
    );

    final replacement = RoomModel(
      id: 'room-stale',
      name: 'Room',
      type: RoomType.living,
      points: [ARPoint(x: 5, y: 0, z: 0)],
    );

    await repository.saveProject(
      uuid: 'project-stale',
      name: 'Project',
      rooms: [replacement],
    );

    final rooms = await repository.getRoomsForProject('project-stale');
    expect(rooms, hasLength(1));
    expect(rooms.single.points, hasLength(1));
    expect(rooms.single.points.single.x, 5);
    expect(rooms.single.features, isEmpty);

    final roomRows = await database.select(database.rooms).get();
    final pointRows = await database.select(database.roomPoints).get();
    final featureRows = await database.select(database.wallFeaturesTable).get();

    expect(roomRows, hasLength(1));
    expect(pointRows, hasLength(1));
    expect(featureRows, isEmpty);
  });

  test('preserves createdAt and advances updatedAt when replacing a project', () async {
    final room = RoomModel(
      id: 'room-1',
      name: 'Room',
      type: RoomType.living,
      points: [ARPoint(x: 0, y: 0, z: 0)],
    );

    await repository.saveProject(
      uuid: 'project-timestamps',
      name: 'Initial',
      rooms: [room],
    );
    final initial = (await repository.getAllProjects()).single;

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await repository.saveProject(
      uuid: 'project-timestamps',
      name: 'Updated',
      rooms: [room],
    );
    final updated = (await repository.getAllProjects()).single;

    expect(updated.createdAt, initial.createdAt);
    expect(updated.updatedAt.isAfter(initial.updatedAt), isTrue);
    expect(updated.name, 'Updated');
  });

  test('persists projects across database close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp('archscan-drift-test-');
    final firstRepository = DriftProjectRepository();
    final room = RoomModel(
      id: 'room-persisted',
      name: 'Persisted room',
      type: RoomType.dormitorio,
      isClosed: true,
      points: [ARPoint(x: 1, y: 2, z: 3)],
    );

    try {
      await firstRepository.init(directoryPath: directory.path);
      await firstRepository.saveProject(
        uuid: 'project-persisted',
        name: 'Persisted project',
        rooms: [room],
      );
      await firstRepository.dispose();

      final secondRepository = DriftProjectRepository();
      try {
        await secondRepository.init(directoryPath: directory.path);
        final projects = await secondRepository.getAllProjects();
        final rooms = await secondRepository.getRoomsForProject(
          'project-persisted',
        );

        expect(projects, hasLength(1));
        expect(projects.single.name, 'Persisted project');
        expect(rooms, hasLength(1));
        expect(rooms.single.id, 'room-persisted');
        expect(rooms.single.isClosed, isTrue);
        expect(rooms.single.points.single.x, 1);
        expect(rooms.single.points.single.y, 2);
        expect(rooms.single.points.single.z, 3);
      } finally {
        await secondRepository.dispose();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('preserves empty projects when saved without rooms', () async {
    await repository.saveProject(
      uuid: 'project-empty',
      name: 'Empty project',
      rooms: const [],
    );

    final projects = await repository.getAllProjects();
    final rooms = await repository.getRoomsForProject('project-empty');

    expect(projects, hasLength(1));
    expect(projects.single.uuid, 'project-empty');
    expect(projects.single.name, 'Empty project');
    expect(rooms, isEmpty);
  });

  test('isolates rooms and data between projects', () async {
    final projectARoom = RoomModel(
      id: 'room-a',
      name: 'Project A room',
      type: RoomType.living,
      points: [ARPoint(x: 1, y: 2, z: 3)],
    );
    final projectBRoom = RoomModel(
      id: 'room-b',
      name: 'Project B room',
      type: RoomType.living,
      points: [ARPoint(x: 4, y: 5, z: 6)],
    );

    await repository.saveProject(
      uuid: 'project-a',
      name: 'Project A',
      rooms: [projectARoom],
    );
    await repository.saveProject(
      uuid: 'project-b',
      name: 'Project B',
      rooms: [projectBRoom],
    );

    final roomsA = await repository.getRoomsForProject('project-a');
    final roomsB = await repository.getRoomsForProject('project-b');

    expect(roomsA.map((room) => room.id), ['room-a']);
    expect(roomsA.single.points.single.x, 1);
    expect(roomsB.map((room) => room.id), ['room-b']);
    expect(roomsB.single.points.single.x, 4);

    await repository.deleteProject('project-a');

    expect(await repository.getRoomsForProject('project-a'), isEmpty);
    expect(await repository.getRoomsForProject('project-b'), hasLength(1));
    expect(
      (await repository.getRoomsForProject('project-b')).single.id,
      'room-b',
    );
    expect((await repository.getAllProjects()).map((project) => project.uuid), [
      'project-b',
    ]);
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

    final projects = await database.select(database.projects).get();
    final rooms = await database.select(database.rooms).get();
    final points = await database.select(database.roomPoints).get();
    final features = await database.select(database.wallFeaturesTable).get();

    expect(projects, isEmpty);
    expect(rooms, isEmpty);
    expect(points, isEmpty);
    expect(features, isEmpty);
  });

  test('handles a large project and reopens the same SQLite file', () async {
    final directory = await Directory.systemTemp.createTemp('archscan-drift-large-');
    final firstRepository = DriftProjectRepository();
    final rooms = List<RoomModel>.generate(40, (roomIndex) {
      return RoomModel(
        id: 'large-room-$roomIndex',
        name: 'Room $roomIndex',
        type: RoomType.values[roomIndex % RoomType.values.length],
        isClosed: true,
        points: List<ARPoint>.generate(
          50,
          (pointIndex) => ARPoint(
            x: pointIndex.toDouble(),
            y: roomIndex.toDouble(),
            z: (pointIndex % 5).toDouble(),
          ),
        ),
        features: List<WallFeature>.generate(
          10,
          (featureIndex) => WallFeature(
            id: 'feature-$roomIndex-$featureIndex',
            type: featureIndex.isEven ? FeatureType.door : FeatureType.window,
            start: ARPoint(
              x: featureIndex.toDouble(),
              y: roomIndex.toDouble(),
              z: 0,
            ),
            end: ARPoint(
              x: featureIndex.toDouble() + 1,
              y: roomIndex.toDouble(),
              z: 0,
            ),
          ),
        ),
      );
    });

    try {
      await firstRepository.init(directoryPath: directory.path);
      await firstRepository.saveProject(
        uuid: 'project-large',
        name: 'Large project',
        rooms: rooms,
      );

      final firstRead = await firstRepository.getRoomsForProject(
        'project-large',
      );
      expect(firstRead, hasLength(40));
      expect(
        firstRead.fold<int>(0, (total, room) => total + room.points.length),
        2000,
      );
      expect(
        firstRead.fold<int>(0, (total, room) => total + room.features.length),
        400,
      );

      await firstRepository.dispose();

      final secondRepository = DriftProjectRepository();
      try {
        await secondRepository.init(directoryPath: directory.path);
        final reopened = await secondRepository.getRoomsForProject(
          'project-large',
        );

        expect(reopened, hasLength(40));
        expect(reopened.first.points, hasLength(50));
        expect(reopened.first.features, hasLength(10));
        expect(reopened.last.points, hasLength(50));
        expect(reopened.last.features, hasLength(10));

        await secondRepository.dispose();

        final thirdRepository = DriftProjectRepository();
        try {
          await thirdRepository.init(directoryPath: directory.path);
          final restarted = await thirdRepository.getAllProjects();
          expect(restarted, hasLength(1));
          expect(restarted.single.name, 'Large project');
        } finally {
          await thirdRepository.dispose();
        }
      } finally {
        await secondRepository.dispose();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });



  test('preserves room, point and feature insertion order after reopen', () async {
    final directory =
        await Directory.systemTemp.createTemp('archscan-drift-order-');
    final firstRepository = DriftProjectRepository();

    final roomA = RoomModel(
      id: 'room-a',
      name: 'A',
      type: RoomType.living,
      points: [
        ARPoint(x: 10, y: 0, z: 10),
        ARPoint(x: 20, y: 0, z: 10),
        ARPoint(x: 20, y: 0, z: 20),
        ARPoint(x: 10, y: 0, z: 20),
      ],
      features: [
        WallFeature(
          id: 'feature-a-1',
          type: FeatureType.window,
          start: ARPoint(x: 11, y: 0, z: 10),
          end: ARPoint(x: 12, y: 0, z: 10),
        ),
        WallFeature(
          id: 'feature-a-2',
          type: FeatureType.door,
          start: ARPoint(x: 13, y: 0, z: 10),
          end: ARPoint(x: 14, y: 0, z: 10),
        ),
      ],
    );
    final roomB = RoomModel(
      id: 'room-b',
      name: 'B',
      type: RoomType.cocina,
      points: [
        ARPoint(x: 30, y: 0, z: 30),
        ARPoint(x: 40, y: 0, z: 30),
        ARPoint(x: 40, y: 0, z: 40),
      ],
    );

    try {
      await firstRepository.init(directoryPath: directory.path);
      await firstRepository.saveProject(
        uuid: 'project-order',
        name: 'Order',
        rooms: [roomA, roomB],
      );
      await firstRepository.dispose();

      final secondRepository = DriftProjectRepository();
      try {
        await secondRepository.init(directoryPath: directory.path);
        final restored =
            await secondRepository.getRoomsForProject('project-order');

        expect(restored.map((room) => room.id), ['room-a', 'room-b']);
        expect(
          restored.first.points.map((point) => point.toJson()),
          roomA.points.map((point) => point.toJson()),
        );
        expect(
          restored.first.features.map((feature) => feature.id),
          ['feature-a-1', 'feature-a-2'],
        );
        expect(
          restored.last.points.map((point) => point.toJson()),
          roomB.points.map((point) => point.toJson()),
        );
      } finally {
        await secondRepository.dispose();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });


}

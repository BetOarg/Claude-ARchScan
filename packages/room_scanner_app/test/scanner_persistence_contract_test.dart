import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/providers/floor_plan_provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

RoomModel _room() {
  return RoomModel(
    id: 'scanner-room',
    name: 'Dormitorio',
    type: RoomType.dormitorio,
    isClosed: true,
    points: [
      ARPoint(x: 0, y: 0, z: 0),
      ARPoint(x: 4, y: 0, z: 0),
      ARPoint(x: 4, y: 0, z: 3),
      ARPoint(x: 0, y: 0, z: 3),
    ],
    features: [
      WallFeature(
        id: 'door-1',
        type: FeatureType.door,
        start: ARPoint(x: 1, y: 0, z: 0),
        end: ARPoint(x: 2, y: 0, z: 0),
        connectedRoomId: 'hall',
        connectionSide: OpeningConnectionSide.right,
        doorHingeSide: DoorHingeSide.end,
        doorSwingSide: DoorSwingSide.right,
        doorOpeningDirection: DoorOpeningDirection.exterior,
        openingHeightMeters: 2.1,
        sillHeightMeters: 0.0,
      ),
    ],
  );
}

void main() {
  test('persists normalized room IDs for the project that was loaded', () async {
    final saves = <String>[];
    final provider = FloorPlanProvider()
      ..persister = ({
        required String uuid,
        required String name,
        required List<RoomModel> rooms,
      }) async {
        saves.add(uuid + ':' + rooms.map((room) => room.id).join(','));
      };
    final room = RoomModel(
      id: '',
      name: 'Ambiente',
      type: RoomType.other,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 1, y: 0, z: 0),
        ARPoint(x: 1, y: 0, z: 1),
      ],
      isClosed: false,
    );
    provider.loadProject(uuid: 'project-normalized', name: 'Proyecto normalizado', rooms: [room]);
    provider.loadProject(uuid: 'project-next', name: 'Proyecto siguiente', rooms: const []);
    await Future<void>.delayed(Duration.zero);
    expect(saves, contains(startsWith('project-normalized:')));
    expect(saves, isNot(contains(startsWith('project-next:'))));
    provider.dispose();
  });

  test('scanner completion persists the exact RoomModel through FloorPlanProvider',
      () async {
    final room = _room();
    List<RoomModel>? persistedRooms;
    final provider = FloorPlanProvider()
      ..loadProject(uuid: 'project', name: 'Home', rooms: const [])
      ..persister = ({required uuid, required name, required rooms}) async {
        persistedRooms = rooms;
      };
    addTearDown(provider.dispose);

    final saved = await provider.addCompletedRoom(room);

    expect(saved, isTrue);
    expect(persistedRooms, isNotNull);
    expect(persistedRooms!.single.toJson(), room.toJson());
  });

  test('scanner completion round-trips through the real Drift repository', () async {
    final database = ArchScanDatabase.inMemory();
    final repository = DriftProjectRepository(database: database);
    addTearDown(repository.dispose);

    final room = _room();
    final provider = FloorPlanProvider()
      ..loadProject(uuid: 'project', name: 'Home', rooms: const [])
      ..persister = repository.saveProject;
    addTearDown(provider.dispose);

    expect(await provider.addCompletedRoom(room), isTrue);

    final restored = await repository.getRoomsForProject('project');
    expect(restored, hasLength(1));
    expect(restored.single.toJson(), room.toJson());
  });

  test('undo persists the restored geometry through the real Drift repository', () async {
    final database = ArchScanDatabase.inMemory();
    final repository = DriftProjectRepository(database: database);
    addTearDown(repository.dispose);

    final provider = FloorPlanProvider()
      ..loadProject(uuid: 'project', name: 'Home', rooms: const [])
      ..persister = repository.saveProject;
    addTearDown(provider.dispose);

    final room = _room().copyWith(features: const []);
    expect(await provider.addCompletedRoom(room), isTrue);

    final original = provider.completedRooms.single;
    final resized = provider.previewGeometry(
      original,
      [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 5, y: 0, z: 0),
        ARPoint(x: 5, y: 0, z: 3),
        ARPoint(x: 0, y: 0, z: 3),
      ],
    );

    expect(resized.error, isNull);
    expect(await provider.applyPlanEdit(resized), isTrue);
    expect(provider.completedRooms.single.points[1].x, 5);
    expect(
      (await repository.getRoomsForProject('project')).single.points[1].x,
      5,
    );

    expect(await provider.undoTransform(), isTrue);
    expect(provider.completedRooms.single.toJson(), original.toJson());

    final restored = await repository.getRoomsForProject('project');
    expect(restored.single.toJson(), original.toJson());

    expect(await provider.redoTransform(), isTrue);
    expect(provider.completedRooms.single.points[1].x, 5);

    final redone = await repository.getRoomsForProject('project');
    expect(redone.single.points[1].x, 5);
    expect(redone.single.toJson(), resized.after.single.toJson());
  });

  test('continuation persists both sides of a shared opening through Drift', () async {
    final database = ArchScanDatabase.inMemory();
    final repository = DriftProjectRepository(database: database);
    addTearDown(repository.dispose);

    final provider = FloorPlanProvider()
      ..loadProject(uuid: 'project', name: 'Home', rooms: const [])
      ..persister = repository.saveProject;
    addTearDown(provider.dispose);

    final baseOpening = _room().features.single;
    final source = _room().copyWith(
      features: [
        WallFeature(
          id: baseOpening.id,
          type: baseOpening.type,
          start: ARPoint(x: 1, y: 0, z: 0),
          end: ARPoint(x: 2, y: 0, z: 0),
          doorHingeSide: baseOpening.doorHingeSide,
          doorSwingSide: baseOpening.doorSwingSide,
          doorOpeningDirection: baseOpening.doorOpeningDirection,
          openingHeightMeters: baseOpening.openingHeightMeters,
          sillHeightMeters: baseOpening.sillHeightMeters,
        ),
      ],
    );
    expect(await provider.addCompletedRoom(source, preservePlacement: true), isTrue);

    final opening = source.features.single;
    final reference = ScanContinuationReference.fromFeature(
      sourceRoomId: source.id,
      feature: opening,
      side: OpeningConnectionSide.right,
      startEndpoint: ContinuationStartEndpoint.start,
    );

    final continuation = RoomModel(
      id: 'continued-room',
      name: 'Cocina',
      type: RoomType.cocina,
      isClosed: true,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 1, y: 0, z: 0),
        ARPoint(x: 1, y: 0, z: 3),
        ARPoint(x: 0, y: 0, z: 3),
      ],
    );

    expect(
      await provider.addCompletedRoomFromContinuation(
        room: continuation,
        reference: reference,
      ),
      isTrue,
    );

    final restored = await repository.getRoomsForProject('project');
    expect(restored, hasLength(2));

    final restoredSource =
        restored.singleWhere((room) => room.id == source.id);
    final restoredContinuation =
        restored.singleWhere((room) => room.id == 'continued-room');

    final sourceOpening = restoredSource.features.single;
    final sharedOpening = restoredContinuation.features.single;

    expect(sourceOpening.connectedRoomId, restoredContinuation.id);
    expect(sourceOpening.connectionSide, OpeningConnectionSide.right);
    expect(sharedOpening.connectedRoomId, restoredSource.id);
    expect(sharedOpening.connectionSide, OpeningConnectionSide.left);
    expect(sharedOpening.id, sourceOpening.id);
    expect(sharedOpening.type, sourceOpening.type);
    expect(sharedOpening.start.toJson(), sourceOpening.start.toJson());
    expect(sharedOpening.end.toJson(), sourceOpening.end.toJson());
  });

  test('shared opening removal and undo/redo round-trip through Drift', () async {
    final database = ArchScanDatabase.inMemory();
    final repository = DriftProjectRepository(database: database);
    addTearDown(repository.dispose);

    final provider = FloorPlanProvider()
      ..loadProject(
        uuid: 'project-shared-undo',
        name: 'Shared',
        rooms: [
          RoomModel(
            id: 'room-a',
            name: 'A',
            type: RoomType.living,
            isClosed: true,
            points: [
              ARPoint(x: 0, y: 0, z: 0),
              ARPoint(x: 2, y: 0, z: 0),
              ARPoint(x: 2, y: 0, z: 2),
              ARPoint(x: 0, y: 0, z: 2),
            ],
            features: [
              WallFeature(
                id: 'shared-door',
                type: FeatureType.door,
                start: ARPoint(x: 2, y: 0, z: 0.5),
                end: ARPoint(x: 2, y: 0, z: 1.5),
                connectedRoomId: 'room-b',
                connectionSide: OpeningConnectionSide.right,
              ),
            ],
          ),
          RoomModel(
            id: 'room-b',
            name: 'B',
            type: RoomType.cocina,
            isClosed: true,
            points: [
              ARPoint(x: 2, y: 0, z: 0),
              ARPoint(x: 4, y: 0, z: 0),
              ARPoint(x: 4, y: 0, z: 2),
              ARPoint(x: 2, y: 0, z: 2),
            ],
            features: [
              WallFeature(
                id: 'shared-door',
                type: FeatureType.door,
                start: ARPoint(x: 2, y: 0, z: 0.5),
                end: ARPoint(x: 2, y: 0, z: 1.5),
                connectedRoomId: 'room-a',
                connectionSide: OpeningConnectionSide.left,
              ),
            ],
          ),
        ],
      )
      ..persister = repository.saveProject;
    addTearDown(provider.dispose);

    // loadProject does not persist when no normalization is required, so seed
    // the exact initial state in Drift before exercising the edit history.
    await repository.saveProject(
      uuid: 'project-shared-undo',
      name: 'Shared',
      rooms: provider.completedRooms,
    );

    expect(await provider.removeOpening('room-a', 'shared-door'), isTrue);
    expect(
      (await repository.getRoomsForProject('project-shared-undo'))
          .every((room) => room.features.isEmpty),
      isTrue,
    );

    expect(await provider.undoTransform(), isTrue);
    final restored = await repository.getRoomsForProject('project-shared-undo');
    expect(restored, hasLength(2));
    expect(restored.every((room) => room.features.length == 1), isTrue);
    expect(
      restored
          .singleWhere((room) => room.id == 'room-a')
          .features
          .single
          .connectedRoomId,
      'room-b',
    );
    expect(
      restored
          .singleWhere((room) => room.id == 'room-b')
          .features
          .single
          .connectedRoomId,
      'room-a',
    );

    expect(await provider.redoTransform(), isTrue);
    final redone = await repository.getRoomsForProject('project-shared-undo');
    expect(redone.every((room) => room.features.isEmpty), isTrue);
  });

  test('scanner completion rolls back when Drift persistence fails', () async {
    final room = _room();
    final provider = FloorPlanProvider()
      ..loadProject(uuid: 'project', name: 'Home', rooms: const [])
      ..persister = ({required uuid, required name, required rooms}) async {
        throw StateError('database unavailable');
      };
    addTearDown(provider.dispose);

    final saved = await provider.addCompletedRoom(room);

    expect(saved, isFalse);
    expect(provider.completedRooms, isEmpty);
  });


  test('precise transform rolls back when persistence fails', () async {
    final provider = FloorPlanProvider()
      ..persister = ({
        required String uuid,
        required String name,
        required List<RoomModel> rooms,
      }) async {
        throw StateError('save failed');
      };

    provider.loadProject(
      uuid: 'project-precise-failure',
      name: 'Proyecto',
      rooms: [
        RoomModel(
          id: 'room-a',
          name: 'Ambiente',
          type: RoomType.other,
          points: [
            ARPoint(x: 0, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 2),
            ARPoint(x: 0, y: 0, z: 2),
          ],
          isClosed: true,
        ),
      ],
    );

    final changed = await provider.transformRoomPrecisely(
      roomId: 'room-a',
      offsetX: 1,
      offsetZ: 0,
      angleDegrees: 0,
    );

    expect(changed, isFalse);
    expect(provider.completedRooms.single.points.first.x, closeTo(0, 0.000001));
    expect(provider.canUndoTransform, isFalse);
    provider.dispose();
  });


  test('undo conserva el historial y permite reintentar tras un fallo de persistencia', () async {
    var failPersistence = false;
    final provider = FloorPlanProvider()
      ..persister = ({
        required String uuid,
        required String name,
        required List<RoomModel> rooms,
      }) async {
        if (failPersistence) {
          throw StateError('database unavailable');
        }
      };

    provider.loadProject(
      uuid: 'project-undo-retry',
      name: 'Proyecto',
      rooms: [
        RoomModel(
          id: 'room-a',
          name: 'Ambiente',
          type: RoomType.other,
          points: [
            ARPoint(x: 0, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 2),
            ARPoint(x: 0, y: 0, z: 2),
          ],
          isClosed: true,
        ),
      ],
    );

    expect(
      await provider.transformRoomPrecisely(
        roomId: 'room-a',
        offsetX: 1,
        offsetZ: 0,
        angleDegrees: 0,
      ),
      isTrue,
    );
    expect(provider.canUndoTransform, isTrue);
    failPersistence = true;

    expect(await provider.undoTransform(), isFalse);
    expect(provider.completedRooms.single.points.first.x, closeTo(1, 0.000001));
    expect(provider.canUndoTransform, isTrue);
    expect(provider.canRedoTransform, isFalse);

    failPersistence = false;
    expect(await provider.undoTransform(), isTrue);
    expect(provider.completedRooms.single.points.first.x, closeTo(0, 0.000001));
    expect(provider.canUndoTransform, isFalse);
    expect(provider.canRedoTransform, isTrue);
    provider.dispose();
  });

  test('redo conserva el historial y permite reintentar tras un fallo de persistencia', () async {
    var failPersistence = false;
    final provider = FloorPlanProvider()
      ..persister = ({
        required String uuid,
        required String name,
        required List<RoomModel> rooms,
      }) async {
        if (failPersistence) {
          throw StateError('database unavailable');
        }
      };

    provider.loadProject(
      uuid: 'project-redo-retry',
      name: 'Proyecto',
      rooms: [
        RoomModel(
          id: 'room-a',
          name: 'Ambiente',
          type: RoomType.other,
          points: [
            ARPoint(x: 0, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 2),
            ARPoint(x: 0, y: 0, z: 2),
          ],
          isClosed: true,
        ),
      ],
    );

    expect(
      await provider.transformRoomPrecisely(
        roomId: 'room-a',
        offsetX: 1,
        offsetZ: 0,
        angleDegrees: 0,
      ),
      isTrue,
    );
    expect(await provider.undoTransform(), isTrue);
    expect(provider.canRedoTransform, isTrue);
    failPersistence = true;

    expect(await provider.redoTransform(), isFalse);
    expect(provider.completedRooms.single.points.first.x, closeTo(0, 0.000001));
    expect(provider.canRedoTransform, isTrue);
    expect(provider.canUndoTransform, isFalse);

    failPersistence = false;
    expect(await provider.redoTransform(), isTrue);
    expect(provider.completedRooms.single.points.first.x, closeTo(1, 0.000001));
    expect(provider.canRedoTransform, isFalse);
    expect(provider.canUndoTransform, isTrue);
    provider.dispose();
  });

  test('opening geometry rolls back and retries after persistence failure', () async {
    var failPersistence = true;
    final provider = FloorPlanProvider()
      ..loadProject(uuid: 'project-opening', name: 'Home', rooms: [_room()])
      ..persister = ({required uuid, required name, required rooms}) async {
        if (failPersistence) throw StateError('save failed');
      };
    addTearDown(provider.dispose);

    final failed = await provider.updateOpeningGeometry(
      roomId: 'scanner-room',
      featureId: 'door-1',
      widthMeters: 1.0,
      distanceFromWallStartMeters: 1.5,
    );

    expect(failed.isSuccess, isFalse);
    expect(provider.completedRooms.single.features.single.start.x,
        closeTo(1.0, 0.000001));
    expect(provider.completedRooms.single.features.single.end.x,
        closeTo(2.0, 0.000001));
    expect(provider.canUndoTransform, isFalse);

    failPersistence = false;
    final retried = await provider.updateOpeningGeometry(
      roomId: 'scanner-room',
      featureId: 'door-1',
      widthMeters: 1.0,
      distanceFromWallStartMeters: 1.5,
    );

    expect(retried.isSuccess, isTrue);
    expect(provider.completedRooms.single.features.single.start.x,
        closeTo(1.5, 0.000001));
    expect(provider.completedRooms.single.features.single.end.x,
        closeTo(2.5, 0.000001));
    expect(provider.canUndoTransform, isTrue);
  });


  test('project rename rolls back and can retry after persistence failure', () async {
    var failPersistence = true;
    final provider = FloorPlanProvider()
      ..loadProject(
        uuid: 'project-rename-retry',
        name: 'Proyecto original',
        rooms: const [],
      )
      ..persister = ({
        required String uuid,
        required String name,
        required List<RoomModel> rooms,
      }) async {
        if (failPersistence) throw StateError('save failed');
      };
    addTearDown(provider.dispose);

    expect(await provider.setProjectName('Nuevo nombre'), isFalse);
    expect(provider.projectName, 'Proyecto original');

    failPersistence = false;
    expect(await provider.setProjectName('Nuevo nombre'), isTrue);
    expect(provider.projectName, 'Nuevo nombre');
  });

}

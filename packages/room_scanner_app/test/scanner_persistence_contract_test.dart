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
}

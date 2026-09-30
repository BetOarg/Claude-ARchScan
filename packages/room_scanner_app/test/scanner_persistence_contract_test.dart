import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/providers/floor_plan_provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

RoomModel _room() {
  return RoomModel(
    id: 'scanner-room',
    name: 'Dormitorio',
    type: RoomType.dormitorio,
    isClosed: true,
    points: const [
      ARPoint(x: 0, y: 0, z: 0),
      ARPoint(x: 4, y: 0, z: 0),
      ARPoint(x: 4, y: 0, z: 3),
      ARPoint(x: 0, y: 0, z: 3),
    ],
    features: [
      WallFeature(
        id: 'door-1',
        type: FeatureType.door,
        start: const ARPoint(x: 1, y: 0, z: 0),
        end: const ARPoint(x: 2, y: 0, z: 0),
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

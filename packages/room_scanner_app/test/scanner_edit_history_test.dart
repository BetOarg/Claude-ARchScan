import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:room_scanner_ar/providers/scanner_provider.dart';
import 'package:room_scanner_ar/providers/floor_plan_provider.dart';

ARPoint point(double x, double z) => ARPoint(x: x, y: 0, z: z);

void main() {
  test('undo/redo restores openings before removing their wall', () {
    final provider = ScannerProvider()..startNewRoom();
    provider.tryAddPoint(0, 0, 0);
    provider.tryAddPoint(3, 0, 0);
    provider.addFeatureToCurrentRoom(FeatureType.door, point(1, 0), widthMeters: 0.8);
    final doorId = provider.currentRoom!.features.single.id;
    expect(provider.undoEdit(), isTrue);
    expect(provider.currentPointsCount, 2);
    expect(provider.currentRoom!.features, isEmpty);
    expect(provider.undoEdit(), isTrue);
    expect(provider.currentPointsCount, 1);
    expect(provider.redoEdit(), isTrue);
    expect(provider.redoEdit(), isTrue);
    expect(provider.currentRoom!.features.single.id, doorId);
  });

  test('removing a wall removes its openings and undo restores both', () {
    final provider = ScannerProvider()..startNewRoom();
    provider.tryAddPoint(0, 0, 0);
    provider.tryAddPoint(3, 0, 0);
    provider.addFeatureToCurrentRoom(FeatureType.door, point(1, 0), widthMeters: 0.8);
    provider.removeLastPoint();
    expect(provider.currentRoom!.features, isEmpty);
    provider.undoEdit();
    expect(provider.currentPointsCount, 2);
    expect(provider.currentRoom!.features, hasLength(1));
  });

  test('a new action invalidates redo and initial anchors cannot be undone', () {
    final provider = ScannerProvider()..startNewRoom(initialPoints: [point(0, 0)]);
    expect(provider.canUndo, isFalse);
    provider.tryAddPoint(3, 0, 0);
    provider.undoEdit();
    expect(provider.canRedo, isTrue);
    provider.tryAddPoint(0, 0, 3);
    expect(provider.canRedo, isFalse);
  });

  test('shared opening removal is atomic across both rooms and undo restores both', () async {
    final provider = FloorPlanProvider();
    provider.loadProject(
      uuid: 'project-shared-remove',
      name: 'Shared',
      rooms: _sharedOpeningRooms(),
    );

    expect(await provider.removeOpening('room-a', 'shared-door'), isTrue);
    expect(
      provider.completedRooms.every((room) => room.features.isEmpty),
      isTrue,
    );
    expect(await provider.undoTransform(), isTrue);
    expect(
      provider.completedRooms.every((room) => room.features.length == 1),
      isTrue,
    );
    expect(
      provider.completedRooms
          .every((room) => room.features.single.connectedRoomId != null),
      isTrue,
    );
  });

  test('orphan opening can be removed and restored without changing contour', () async {
    final provider = FloorPlanProvider();
    provider.loadProject(uuid: 'project', name: 'House', rooms: [RoomModel(
      id: 'room', name: 'Kitchen', type: RoomType.cocina,
      points: [point(0,0),point(3,0),point(3,2),point(0,2)], isClosed: true,
      features: [WallFeature(id:'orphan', type:FeatureType.door,
          start:point(8,8),end:point(9,8))],
    )]);
    expect(await provider.removeOpening('room','orphan'), isTrue);
    expect(provider.completedRooms.single.features, isEmpty);
    expect(provider.completedRooms.single.points, hasLength(4));
    expect(await provider.undoTransform(), isTrue);
    expect(provider.completedRooms.single.features, hasLength(1));
  });
}

List<RoomModel> _sharedOpeningRooms() {
  final first = WallFeature(
    id: 'shared-door',
    type: FeatureType.door,
    start: point(2, 0.5),
    end: point(2, 1.5),
    connectedRoomId: 'room-b',
    connectionSide: OpeningConnectionSide.right,
  );
  final second = first.copyWith(
    connectedRoomId: 'room-a',
    connectionSide: OpeningConnectionSide.left,
  );
  return [
    RoomModel(
      id: 'room-a',
      name: 'A',
      type: RoomType.living,
      points: [point(0,0), point(2,0), point(2,2), point(0,2)],
      features: [first],
      isClosed: true,
    ),
    RoomModel(
      id: 'room-b',
      name: 'B',
      type: RoomType.cocina,
      points: [point(2,0), point(4,0), point(4,2), point(2,2)],
      features: [second],
      isClosed: true,
    ),
  ];
}

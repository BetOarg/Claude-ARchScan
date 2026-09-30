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

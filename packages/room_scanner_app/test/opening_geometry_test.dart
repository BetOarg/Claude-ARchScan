import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/providers/floor_plan_provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

ARPoint point(double x, double z) => ARPoint(x: x, y: 0, z: z);

RoomModel roomWithFeatures(List<WallFeature> features) {
  return RoomModel(
    id: 'room-1',
    name: 'Ambiente',
    type: RoomType.living,
    points: [
      point(0, 0),
      point(4, 0),
      point(4, 3),
      point(0, 3),
    ],
    features: features,
    isClosed: true,
  );
}

WallFeature opening({
  required String id,
  required double start,
  required double end,
  FeatureType type = FeatureType.door,
}) {
  return WallFeature(
    id: id,
    type: type,
    start: point(start, 0),
    end: point(end, 0),
  );
}

void main() {
  for (final wallIndex in [0, 1, 2, 3]) {
    test('placed openings stay on wall $wallIndex and undo restores an orphan', () async {
      final orphan = WallFeature(
        id: 'orphan', type: FeatureType.window,
        start: point(7, 7), end: point(8, 7),
      );
      final provider = FloorPlanProvider()..loadProject(
        uuid: 'p', name: 'Plan', rooms: [roomWithFeatures([orphan])],
      );
      addTearDown(provider.dispose);
      final result = await provider.placeOpeningOnWall(
        roomId: 'room-1', type: FeatureType.window, featureId: 'orphan',
        wallIndex: wallIndex, location: point(2, 1.5), widthMeters: 1,
        openingHeightMeters: 1.4, sillHeightMeters: 0.7,
      );
      expect(result.isSuccess, isTrue);
      final feature = provider.completedRooms.single.features.single;
      if (wallIndex == 0 || wallIndex == 2) {
        expect(feature.start.z, wallIndex == 0 ? 0 : 3);
        expect(feature.end.z, feature.start.z);
      } else {
        expect(feature.start.x, wallIndex == 1 ? 4 : 0);
        expect(feature.end.x, feature.start.x);
      }
      expect(GeometryService.calculateDistance(feature.start, feature.end), closeTo(1, 1e-8));
      expect(feature.openingHeightMeters, 1.4);
      expect(await provider.undoTransform(), isTrue);
      expect(provider.completedRooms.single.features.single.start.x, 7);
      expect(await provider.redoTransform(), isTrue);
      expect(provider.completedRooms.single.features.single.start.x, feature.start.x);
    });
  }

  test('placement rejects overlap and excessive width without mutation', () async {
    final provider = FloorPlanProvider()..loadProject(
      uuid: 'p', name: 'Plan',
      rooms: [roomWithFeatures([opening(id: 'door', start: 1, end: 2)])],
    );
    addTearDown(provider.dispose);
    for (final width in [1.0, 6.0, double.nan]) {
      final result = await provider.placeOpeningOnWall(
        roomId: 'room-1', type: FeatureType.window, wallIndex: 0,
        location: point(1.5, 0), widthMeters: width,
        openingHeightMeters: 1.2, sillHeightMeters: 0.9,
      );
      expect(result.isSuccess, isFalse);
      expect(provider.completedRooms.single.features, hasLength(1));
    }
  });

  test('shared openings move atomically only on the common wall', () async {
    final shared = opening(id: 'shared', start: 1, end: 2)
        .copyWith(connectedRoomId: 'room-2');
    final other = RoomModel(
      id: 'room-2', name: 'Other', type: RoomType.living, isClosed: true,
      points: [point(0, 0), point(0, -3), point(4, -3), point(4, 0)],
      features: [shared.copyWith(
        connectedRoomId: 'room-1',
        start: point(2, 0),
        end: point(1, 0),
      )],
    );
    final provider = FloorPlanProvider()..loadProject(
      uuid: 'p', name: 'Plan', rooms: [roomWithFeatures([shared]), other],
    );
    addTearDown(provider.dispose);
    final rejected = await provider.placeOpeningOnWall(
      roomId: 'room-1', type: FeatureType.door, featureId: 'shared',
      wallIndex: 1, location: point(4, 1.5), widthMeters: 1,
      openingHeightMeters: 2.1, sillHeightMeters: 0,
    );
    expect(rejected.isSuccess, isFalse);
    expect(provider.completedRooms.first.features.single.start.x, 1);
    final moved = await provider.placeOpeningOnWall(
      roomId: 'room-1', type: FeatureType.door, featureId: 'shared',
      wallIndex: 0, location: point(2.5, 0), widthMeters: 1,
      openingHeightMeters: 2.1, sillHeightMeters: 0,
    );
    expect(moved.isSuccess, isTrue);
    for (final room in provider.completedRooms) {
      expect(room.features.single.start.x, 2);
      expect(room.features.single.end.x, 3);
      expect(room.features.single.isConnected, isTrue);
    }
  });

  test('shared opening geometry preserves each copy endpoint orientation', () async {
    final shared = opening(id: 'shared', start: 1, end: 2)
        .copyWith(connectedRoomId: 'room-2');
    final reversed = shared.copyWith(
      connectedRoomId: 'room-1',
      start: point(2, 0),
      end: point(1, 0),
    );
    final other = RoomModel(
      id: 'room-2', name: 'Other', type: RoomType.living, isClosed: true,
      points: [point(0, 0), point(0, -3), point(4, -3), point(4, 0)],
      features: [reversed],
    );
    final provider = FloorPlanProvider()..loadProject(
      uuid: 'p', name: 'Plan', rooms: [roomWithFeatures([shared]), other],
    );
    addTearDown(provider.dispose);

    final result = await provider.updateOpeningGeometry(
      roomId: 'room-1',
      featureId: 'shared',
      widthMeters: 0.8,
      distanceFromWallStartMeters: 2,
      openingHeightMeters: 2.2,
      sillHeightMeters: 0.1,
    );

    expect(result.isSuccess, isTrue);
    final first = provider.completedRooms[0].features.single;
    final second = provider.completedRooms[1].features.single;
    expect(first.start.x, closeTo(2, 1e-6));
    expect(first.end.x, closeTo(2.8, 1e-6));
    expect(second.start.x, closeTo(2.8, 1e-6));
    expect(second.end.x, closeTo(2, 1e-6));
    expect(second.openingHeightMeters, closeTo(2.2, 1e-6));
    expect(second.sillHeightMeters, closeTo(0.1, 1e-6));
  });

  test('placement follows a diagonal wall instead of the horizontal axis', () async {
    final provider = FloorPlanProvider()..loadProject(
      uuid: 'p', name: 'Plan', rooms: [RoomModel(
        id: 'diagonal', name: 'Room', type: RoomType.living, isClosed: true,
        points: [point(0, 0), point(4, 3), point(0, 4)],
      )],
    );
    addTearDown(provider.dispose);
    final result = await provider.placeOpeningOnWall(
      roomId: 'diagonal', type: FeatureType.window, wallIndex: 0,
      location: point(2, 1.5), widthMeters: 1,
      openingHeightMeters: 1.2, sillHeightMeters: 0.9,
    );
    expect(result.isSuccess, isTrue);
    final f = provider.completedRooms.single.features.single;
    expect(f.end.x - f.start.x, closeTo(0.8, 1e-8));
    expect(f.end.z - f.start.z, closeTo(0.6, 1e-8));
  });

  group('Edición geométrica de aberturas', () {
    test('informa ancho, posición y longitud de pared', () {
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project',
          name: 'Plano',
          rooms: [
            roomWithFeatures([
              opening(id: 'door', start: 1, end: 2),
            ]),
          ],
        );

      final placement = provider.getOpeningPlacement(
        roomId: 'room-1',
        featureId: 'door',
      );

      expect(placement, isNotNull);
      expect(placement!.widthMeters, closeTo(1, 0.000001));
      expect(
        placement.distanceFromWallStartMeters,
        closeTo(1, 0.000001),
      );
      expect(placement.wallLengthMeters, closeTo(4, 0.000001));
      expect(placement.openingHeightMeters, closeTo(2.10, 0.000001));
      expect(placement.sillHeightMeters, closeTo(0, 0.000001));
    });

    test('actualiza ancho y posición sobre la misma pared', () async {
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project',
          name: 'Plano',
          rooms: [
            roomWithFeatures([
              opening(id: 'door', start: 1, end: 2),
            ]),
          ],
        );

      final result = await provider.updateOpeningGeometry(
        roomId: 'room-1',
        featureId: 'door',
        widthMeters: 0.8,
        distanceFromWallStartMeters: 2,
        openingHeightMeters: 2.20,
        sillHeightMeters: 0.10,
      );
      final updated = provider.findFeature(
        roomId: 'room-1',
        featureId: 'door',
      );

      expect(result.isSuccess, isTrue);
      expect(updated!.start.x, closeTo(2, 0.000001));
      expect(updated.end.x, closeTo(2.8, 0.000001));
      expect(updated.start.z, closeTo(0, 0.000001));
      expect(updated.end.z, closeTo(0, 0.000001));
      expect(updated.openingHeightMeters, closeTo(2.20, 0.000001));
      expect(updated.sillHeightMeters, closeTo(0.10, 0.000001));
    });

    test('rechaza límites de pared y superposiciones', () async {
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project',
          name: 'Plano',
          rooms: [
            roomWithFeatures([
              opening(id: 'door', start: 1, end: 2),
              opening(
                id: 'window',
                start: 2.5,
                end: 3.2,
                type: FeatureType.window,
              ),
            ]),
          ],
        );

      final outside = await provider.updateOpeningGeometry(
        roomId: 'room-1',
        featureId: 'door',
        widthMeters: 1,
        distanceFromWallStartMeters: 3.5,
      );
      final overlap = await provider.updateOpeningGeometry(
        roomId: 'room-1',
        featureId: 'door',
        widthMeters: 1,
        distanceFromWallStartMeters: 2,
      );

      expect(outside.isSuccess, isFalse);
      expect(overlap.isSuccess, isFalse);
    });
  });
}
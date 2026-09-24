import 'package:test/test.dart';

import 'package:room_scanner_core/room_scanner_core.dart';

void main() {
  RoomModel roomWithOpening() => RoomModel(
    id: 'room-1',
    name: 'Living',
    type: RoomType.living,
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
        end: ARPoint(x: 1.8, y: 0, z: 0),
      ),
    ],
  );

  test('creates opening, wall and total dimensions without mutating room', () {
    final room = roomWithOpening();
    final originalPoints = room.points.toList();
    final originalFeatures = room.features.toList();

    final dimensions = TechnicalDimensionLayout.forRoom(
      room: room,
      x: (point) => point.x,
      y: (point) => point.z,
    );

    expect(dimensions, hasLength(7));
    expect(
      dimensions.where((d) => d.kind == DimensionKind.opening),
      hasLength(1),
    );
    expect(dimensions.where((d) => d.kind == DimensionKind.wall), hasLength(4));
    expect(
      dimensions.where((d) => d.kind == DimensionKind.total),
      hasLength(2),
    );
    expect(dimensions.first.kind, DimensionKind.opening);
    expect(dimensions.last.kind, DimensionKind.total);
    expect(room.points, orderedEquals(originalPoints));
    expect(room.features, orderedEquals(originalFeatures));
  });

  test('can suppress hidden walls while preserving openings and totals', () {
    final dimensions = TechnicalDimensionLayout.forRoom(
      room: roomWithOpening(),
      x: (point) => point.x,
      y: (point) => point.z,
      hiddenWallIndexes: const {0},
    );

    expect(dimensions.where((d) => d.kind == DimensionKind.wall), hasLength(3));
    expect(
      dimensions.where((d) => d.kind == DimensionKind.opening),
      hasLength(1),
    );
    expect(
      dimensions.where((d) => d.kind == DimensionKind.total),
      hasLength(2),
    );
  });

  test('places opening dimensions with the interior normal direction', () {
    final dimensions = TechnicalDimensionLayout.forRoom(
      room: roomWithOpening(),
      x: (point) => point.x,
      y: (point) => point.z,
      includeTotals: false,
    );

    final opening = dimensions.singleWhere(
      (dimension) => dimension.kind == DimensionKind.opening,
    );
    expect(opening.normalDirection, -1.0);
  });
  test('does not dimension a wall fragment that contains a door', () {
    final room = RoomModel(
      id: 'door-room',
      name: 'Living',
      type: RoomType.living,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 3),
        ARPoint(x: 0, y: 0, z: 3),
      ],
      isClosed: true,
      features: [
        WallFeature(
          id: 'door',
          type: FeatureType.door,
          start: ARPoint(x: 1, y: 0, z: 0),
          end: ARPoint(x: 1.8, y: 0, z: 0),
        ),
      ],
    );

    final dimensions = TechnicalDimensionLayout.forRoom(
      room: room,
      x: (point) => point.x,
      y: (point) => point.z,
    );

    expect(
      dimensions.where((dimension) => dimension.kind == DimensionKind.wall),
      hasLength(3),
    );
    expect(
      dimensions.where((dimension) => dimension.kind == DimensionKind.opening),
      hasLength(1),
    );
  });


}

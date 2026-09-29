import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/providers/floor_plan_room_placement.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

ARPoint p(double x, double z) => ARPoint(x: x, y: 0, z: z);

RoomModel room(String id, {double x = 0, double z = 0}) => RoomModel(
  id: id,
  name: id,
  type: RoomType.other,
  points: [p(x, z), p(x + 2, z), p(x + 2, z + 3)],
  features: [
    WallFeature(
      id: 'door-$id',
      type: FeatureType.door,
      start: p(x + 0.5, z),
      end: p(x + 1.0, z),
    ),
  ],
  isClosed: false,
);

void main() {
  test('translate moves points and openings without changing shape', () {
    final original = room('a');
    final translated = FloorPlanRoomPlacement.translate(
      original,
      offsetX: 4,
      offsetZ: -2,
    );

    expect(translated.points.first.x, 4);
    expect(translated.points.first.z, -2);
    expect(translated.features.single.start.x, 4.5);
    expect(translated.features.single.start.z, -2);
    expect(
      translated.points[1].x - translated.points[0].x,
      original.points[1].x - original.points[0].x,
    );
  });

  test('placeAfterExisting keeps one metre spacing on the X axis', () {
    final existing = room('existing');
    final candidate = room('candidate', x: -10, z: 8);

    final placed = FloorPlanRoomPlacement.placeAfterExisting(
      candidate,
      [existing],
    );

    expect(placed.points.map((p) => p.x).reduce((a, b) => a > b ? a : b), 5);
    expect(placed.points.map((p) => p.z).reduce((a, b) => a < b ? a : b), 0);
    expect(placed.features.single.start.x, 3.5);
  });

  test('empty existing rooms leave candidate unchanged', () {
    final candidate = room('candidate', x: 5, z: 7);
    final placed = FloorPlanRoomPlacement.placeAfterExisting(candidate, const []);

    expect(placed.points, candidate.points);
    expect(placed.features, candidate.features);
  });
}

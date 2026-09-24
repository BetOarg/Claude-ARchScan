import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

ARPoint p(double x, double z) => ARPoint(x: x, y: 0, z: z);
RoomModel room(
  String id,
  List<ARPoint> points, {
  bool closed = true,
  List<WallFeature> features = const [],
}) => RoomModel(
  id: id,
  name: id,
  type: RoomType.other,
  points: points,
  isClosed: closed,
  features: features,
);

void main() {
  test('corner snapping respects real walls, range and vertical metadata', () {
    final neighbour = room('n', [p(0, 0), p(4, 0), p(4, 3)], closed: false);
    final snap = PlanEditGeometry.snapPoint(ARPoint(x: 4.08, y: 1.2, z: 1), [
      neighbour,
    ], 0.1);
    expect(snap.x, 4);
    expect(snap.z, 1);
    expect(snap.y, 1.2);
    final far = p(2, 1.5); // On the absent diagonal closing edge.
    expect(PlanEditGeometry.snapPoint(far, [neighbour], 0.1), same(far));
  });
  test('coincident subdivided boundaries overlap but shared walls do not', () {
    final a = room('a', [p(0, 0), p(4, 0), p(4, 3), p(0, 3)]);
    final b = room('b', [p(0, 0), p(2, 0), p(4, 0), p(4, 3), p(0, 3)]);
    final c = room('c', [p(4, 0), p(6, 0), p(6, 3), p(4, 3)]);
    expect(PlanEditGeometry.overlaps(a, b), isTrue);
    expect(PlanEditGeometry.overlaps(a, c), isFalse);
  });
  test(
    'deleting any closed wall opens the path without inventing another edge',
    () {
      final original = room('r', [p(0, 0), p(4, 0), p(4, 3), p(0, 3)]);
      for (var i = 0; i < 4; i++) {
        final result = PlanEditGeometry.deleteWall(original, i).single;
        expect(result.isClosed, isFalse);
        expect(PlanEditGeometry.wallCount(result), 3);
        expect(result.points.first, original.points[(i + 1) % 4]);
        expect(result.points.last, original.points[i]);
      }
      expect(original.isClosed, isTrue);
    },
  );
  test('cutting an internal open wall preserves both fragments and removes its opening', () {
    final door = WallFeature(
      id: 'd',
      type: FeatureType.door,
      start: p(4, 1),
      end: p(4, 2),
    );
    final original = room(
      'r',
      [p(0, 0), p(4, 0), p(4, 3), p(0, 3)],
      closed: false,
      features: [door],
    );
    final parts = PlanEditGeometry.deleteWall(original, 1);
    expect(parts, hasLength(2));
    expect(parts.map(PlanEditGeometry.wallCount), [1, 1]);
    expect(parts.expand((r) => r.features), isEmpty);
  });
  test('wall drag is parallel and carries its door without changing width', () {
    final door = WallFeature(
      id: 'd',
      type: FeatureType.door,
      start: p(1, 0),
      end: p(2, 0),
    );
    final original = room(
      'r',
      [p(0, 0), p(4, 0), p(4, 3), p(0, 3)],
      features: [door],
    );
    final points = PlanEditGeometry.moveWall(original, 0, 2, -1);
    final updated = PlanEditGeometry.reshape(original, points)!;
    expect(updated.points.first.x, 0);
    expect(updated.points[1].x, 4);
    expect(updated.points.first.z, -1);
    expect(updated.features.single.start.z, -1);
    expect(
      PlanEditGeometry.distance(
        updated.features.single.start,
        updated.features.single.end,
      ),
      1,
    );
    expect(original.features.single.start.z, 0);
  });
  test('rejects self intersections and openings wider than their wall', () {
    final original = room(
      'r',
      [p(0, 0), p(4, 0), p(4, 3), p(0, 3)],
      features: [
        WallFeature(
          id: 'w',
          type: FeatureType.window,
          start: p(0.5, 0),
          end: p(3.5, 0),
        ),
      ],
    );
    expect(
      PlanEditGeometry.reshape(original, [p(0, 0), p(3, 4), p(4, 3), p(0, 3)]),
      isNull,
    );
    expect(
      PlanEditGeometry.reshape(
        original,
        PlanEditGeometry.resizeWall(original, 0, 2)!,
      ),
      isNull,
    );
  });
  test('nearest closure projects onto a neighbouring wall and uses its return path', () {
    final neighbour = room('n', [p(0, 0), p(4, 0), p(4, 3), p(0, 3)]);
    final open = room('r', [
      p(4, 1),
      p(6, 1),
      p(6, 2.5),
      p(4.3, 2.5),
    ], closed: false);
    final closure = PlanClosure.nearest(open, [neighbour])!;
    expect(closure.distanceToTarget, closeTo(0.3, 1e-8));
    expect(closure.returnPath[1].x, 4);
    expect(closure.returnPath[1].z, 2.5);
    expect(closure.returnPath.last.z, 1);
    expect(closure.room.points, hasLength(5));
    expect(closure.room.isClosed, isTrue);
    expect(PlanEditGeometry.overlaps(closure.room, neighbour), isFalse);
    expect(open.isClosed, isFalse);
  });
  test(
    'closure never invents a bridge along a disconnected neighbouring wall',
    () {
      final neighbour = room('n', [p(0, 0), p(4, 0), p(4, 3), p(0, 3)]);
      final open = room('r', [
        p(5, 1),
        p(6, 1),
        p(6, 2.5),
        p(4.3, 2.5),
      ], closed: false);
      final closure = PlanClosure.nearest(open, [neighbour])!;
      expect(closure.returnPath, hasLength(2));
      expect(closure.returnPath.last, open.points.first);
    },
  );
  test('rejects overlapping closures and closes a normal open rectangle', () {
    final open = room('r', [p(0, 0), p(4, 0), p(4, 3), p(0, 3)], closed: false);
    expect(PlanClosure.nearest(open, [])!.room.isClosed, isTrue);
    expect(
      PlanClosure.nearest(open, [
        room('n', [p(-1, -1), p(5, -1), p(5, 4), p(-1, 4)]),
      ]),
      isNull,
    );
  });
}

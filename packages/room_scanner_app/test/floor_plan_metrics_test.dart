import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/providers/floor_plan_metrics.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

ARPoint point(double x, double z) => ARPoint(x: x, y: 0, z: z);

RoomModel room({required String id, required bool closed, List<ARPoint>? points}) {
  return RoomModel(
    id: id,
    name: id,
    type: RoomType.living,
    points: points ?? [point(0, 0), point(3, 0), point(3, 4), point(0, 4)],
    isClosed: closed,
  );
}

void main() {
  test('calculates a wall length independently of provider state', () {
    final value = FloorPlanMetrics.wallLength(room(id: 'r1', closed: true), 1);
    expect(value, closeTo(4, 0.000001));
    expect(FloorPlanMetrics.wallLength(room(id: 'r1', closed: true), -1), 0);
  });

  test('area totals include only closed rooms', () {
    final rooms = [
      room(id: 'closed', closed: true),
      room(id: 'open', closed: false),
    ];
    expect(FloorPlanMetrics.totalProjectArea(rooms), closeTo(12, 0.000001));
  });

  test('room summaries preserve identity and derived values', () {
    final summaries = FloorPlanMetrics.roomSummaries([
      room(id: 'r1', closed: true),
    ]);
    expect(summaries, hasLength(1));
    expect(summaries.single['id'], 'r1');
    expect(summaries.single['name'], 'r1');
    expect(summaries.single['area'], '12.00');
    expect(summaries.single['perimeter'], '14.00');
    expect(summaries.single['pointsCount'], 4);
  });
}

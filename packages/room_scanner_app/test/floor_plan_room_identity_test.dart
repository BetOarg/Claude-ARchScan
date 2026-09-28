import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/providers/floor_plan_room_identity.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

ARPoint point(double x, double z) => ARPoint(x: x, y: 0, z: z);

RoomModel room(String id) => RoomModel(
  id: id,
  name: 'Room',
  type: RoomType.other,
  points: [point(0, 0), point(1, 0), point(1, 1)],
  isClosed: false,
);

void main() {
  test('preserves unique room IDs without mutation', () {
    final result = FloorPlanRoomIdentity.normalizeIds([room('a'), room('b')]);

    expect(result.changed, isFalse);
    expect(result.rooms.map((r) => r.id), ['a', 'b']);
  });

  test('repairs empty and duplicate room IDs', () {
    final result = FloorPlanRoomIdentity.normalizeIds([
      room('same'),
      room(''),
      room('same'),
    ]);

    expect(result.changed, isTrue);
    final ids = result.rooms.map((r) => r.id).toList();
    expect(ids[0], 'same');
    expect(ids[1], isNotEmpty);
    expect(ids[2], isNotEmpty);
    expect(ids.toSet().length, 3);
  });

  test('generated IDs are unique across consecutive calls', () {
    final first = FloorPlanRoomIdentity.nextUniqueId();
    final second = FloorPlanRoomIdentity.nextUniqueId();

    expect(first, isNot(second));
  });
}

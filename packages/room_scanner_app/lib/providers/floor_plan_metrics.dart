import 'package:room_scanner_core/room_scanner_core.dart';

/// Pure read-only calculations used by [FloorPlanProvider].
///
/// The provider remains responsible for state changes; this class owns
/// derived floor-plan metrics so they can be tested independently.
class FloorPlanMetrics {
  const FloorPlanMetrics._();

  static double wallLength(RoomModel room, int wallIndex) {
    final points = room.points;
    if (points.length < 2 || wallIndex < 0 || wallIndex >= points.length) {
      return 0.0;
    }
    final start = points[wallIndex];
    final end = points[(wallIndex + 1) % points.length];
    return GeometryService.calculateDistance(start, end);
  }

  static double totalProjectArea(List<RoomModel> rooms) {
    var total = 0.0;
    for (final room in rooms) {
      if (!room.isClosed) continue;
      total += GeometryService.calculateArea(room.points);
    }
    return total;
  }

  static List<Map<String, dynamic>> roomSummaries(List<RoomModel> rooms) {
    return rooms
        .map(
          (room) => <String, dynamic>{
            'id': room.id,
            'name': room.name,
            'type': room.type.name,
            'area': PlanEditGeometry.area(room).toStringAsFixed(2),
            'perimeter': PlanEditGeometry.perimeter(room).toStringAsFixed(2),
            'pointsCount': room.points.length,
          },
        )
        .toList(growable: false);
  }
}

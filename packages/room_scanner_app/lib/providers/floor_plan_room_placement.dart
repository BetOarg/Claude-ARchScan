import 'package:room_scanner_core/room_scanner_core.dart';

/// Pure room placement operations used by FloorPlanProvider.
///
/// This service deliberately has no provider state, persistence, or UI
/// concerns, making global room positioning independently testable.
class FloorPlanRoomPlacement {
  const FloorPlanRoomPlacement._();

  static RoomModel translate(
    RoomModel room, {
    required double offsetX,
    required double offsetZ,
  }) {
    final translatedPoints = room.points
        .map(
          (point) => ARPoint(
            x: point.x + offsetX,
            y: point.y,
            z: point.z + offsetZ,
          ),
        )
        .toList();

    final translatedFeatures = room.features
        .map(
          (feature) => feature.copyWith(
            start: ARPoint(
              x: feature.start.x + offsetX,
              y: feature.start.y,
              z: feature.start.z + offsetZ,
            ),
            end: ARPoint(
              x: feature.end.x + offsetX,
              y: feature.end.y,
              z: feature.end.z + offsetZ,
            ),
          ),
        )
        .toList();

    return room.copyWith(
      points: translatedPoints,
      features: translatedFeatures,
    );
  }

  static RoomModel placeAfterExisting(
    RoomModel room,
    List<RoomModel> existingRooms, {
    double spacing = 1.0,
  }) {
    if (existingRooms.isEmpty || room.points.isEmpty) return room;

    var projectMaxX = double.negativeInfinity;
    var projectMinZ = double.infinity;
    for (final existing in existingRooms) {
      for (final point in existing.points) {
        if (point.x > projectMaxX) projectMaxX = point.x;
        if (point.z < projectMinZ) projectMinZ = point.z;
      }
    }

    if (!projectMaxX.isFinite) projectMaxX = 0.0;
    if (!projectMinZ.isFinite) projectMinZ = 0.0;

    var roomMinX = double.infinity;
    var roomMinZ = double.infinity;
    for (final point in room.points) {
      if (point.x < roomMinX) roomMinX = point.x;
      if (point.z < roomMinZ) roomMinZ = point.z;
    }

    if (!roomMinX.isFinite) roomMinX = 0.0;
    if (!roomMinZ.isFinite) roomMinZ = 0.0;

    return translate(
      room,
      offsetX: projectMaxX + spacing - roomMinX,
      offsetZ: projectMinZ - roomMinZ,
    );
  }
}

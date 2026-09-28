import 'package:room_scanner_core/room_scanner_core.dart';

/// Owns room identifier generation and legacy room-ID normalization.
///
/// Keeping this concern outside FloorPlanProvider makes identity repair
/// independently testable without changing provider behavior.
class FloorPlanRoomIdentity {
  static int _lastGeneratedId = 0;

  const FloorPlanRoomIdentity._();

  static String nextUniqueId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now > _lastGeneratedId) {
      _lastGeneratedId = now;
    } else {
      _lastGeneratedId++;
    }
    return _lastGeneratedId.toString();
  }

  static RoomNormalizationResult normalizeIds(List<RoomModel> rooms) {
    final usedIds = <String>{};
    final normalized = <RoomModel>[];
    var changed = false;

    for (final room in rooms) {
      var id = room.id.trim();
      if (id.isEmpty || usedIds.contains(id)) {
        id = nextUniqueId();
        changed = true;
      }
      usedIds.add(id);
      normalized.add(id == room.id ? room : room.copyWith(id: id));
    }

    return RoomNormalizationResult(
      rooms: normalized,
      changed: changed,
    );
  }
}

class RoomNormalizationResult {
  final List<RoomModel> rooms;
  final bool changed;

  const RoomNormalizationResult({
    required this.rooms,
    required this.changed,
  });
}

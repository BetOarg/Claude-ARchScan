import 'package:room_scanner_core/room_scanner_core.dart';

import '../providers/floor_plan_provider.dart';
import 'room_plan_service.dart';

typedef RoomPlanCapture = Future<RoomModel?> Function({
  required String roomId,
  required String roomName,
  required RoomType roomType,
});

/// Connects RoomPlan capture to the existing project persistence path.
///
/// Keeping this coordinator independent from navigation lets RoomPlan reuse the
/// same [FloorPlanProvider] and Isar persistence contract as every other mode.
class RoomPlanCaptureCoordinator {
  final RoomPlanCapture _capture;

  const RoomPlanCaptureCoordinator({
    RoomPlanCapture capture = RoomPlanService.scanRoom,
  }) : _capture = capture;

  Future<RoomModel?> captureAndPersist({
    required FloorPlanProvider floorPlanProvider,
    required String roomName,
    RoomType roomType = RoomType.other,
  }) async {
    final room = await _capture(
      roomId: _nextRoomId(),
      roomName: roomName,
      roomType: roomType,
    );
    if (room == null) return null;
    if (!await floorPlanProvider.addCompletedRoom(room)) {
      throw StateError('RoomPlan project could not be saved.');
    }
    return room;
  }

  String _nextRoomId() =>
      'roomplan-${DateTime.now().microsecondsSinceEpoch}';
}

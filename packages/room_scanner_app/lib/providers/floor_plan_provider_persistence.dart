part of 'floor_plan_provider.dart';

/// Persistence/project coordination extracted from [FloorPlanProvider].
///
/// This mixin keeps project loading, queued persistence and project naming
/// outside the geometry/editing implementation while preserving the existing
/// state and observable behavior.
mixin FloorPlanProviderPersistenceMixin on FloorPlanProvider {
  // ===========================================================================

  void loadProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) {
    _projectUuid = uuid;

    _projectName = name;

    final normalized =
        _normalizeRoomIds(
      rooms,
    );

    _completedRooms
      ..clear()
      ..addAll(
        normalized.rooms,
      );

    _clearTransformHistory();

    notifyListeners();

    if (normalized.changed) {
      Future<void>.microtask(
        () async { await _persist(); },
      );
    }
  }

  Future<bool> _saveQueue = Future<bool>.value(true);

  Future<bool> _persist() {
    final uuid = _projectUuid;
    final save = persister;
    final name = _projectName;
    final rooms = List<RoomModel>.unmodifiable(_completedRooms);

    if (uuid == null ||
        save == null) {
      return Future<bool>.value(true);
    }

    // Capture identity and data now; execute writes in request order.
    final operation = _saveQueue.then((_) async {
      try {
        await save(uuid: uuid, name: name, rooms: rooms);
        return true;
      } catch (e) {
        debugPrint('No se pudo guardar el proyecto "$name": $e');
        return false;
      }
    });
    _saveQueue = operation;
    return operation;
  }

  /// A failed scan save must not leave an apparently completed room in memory.
  Future<bool> _persistRoomChange(List<RoomModel> before) async {
    final uuid = _projectUuid;
    final attempted = List<RoomModel>.from(_completedRooms);
    if (await _persist()) return true;
    // Never erase a later edit or a different project after an older failure.
    if (_projectUuid == uuid && _sameRoomSnapshot(attempted, _completedRooms)) {
      _completedRooms..clear()..addAll(before);
      notifyListeners();
    }
    return false;
  }

  bool canPlaceScannedRoom(RoomModel room) => !_completedRooms.any(
    (existing) => existing.id != room.id &&
        PlanEditGeometry.overlaps(room, existing),
  );

  Future<bool> _saveTransform(List<RoomModel> before) async {
    final uuid = _projectUuid;
    final after = List<RoomModel>.from(_completedRooms);
    notifyListeners();
    if (!await _persistRoomChange(before)) return false;
    if (_projectUuid == uuid && _sameRoomSnapshot(after, _completedRooms)) {
      _recordTransform(before);
      notifyListeners();
    }
    return true;
  }

  Future<void> setProjectName(
    String name,
  ) async {
    final normalized =
        name.trim();

    if (normalized.isEmpty) {
      return;
    }

    _projectName = normalized;

    notifyListeners();

    await _persist();
  }


}

import 'package:room_scanner_core/room_scanner_core.dart';

/// Pure undo/redo history for completed floor-plan transformations.
///
/// Persistence and notifications remain owned by [FloorPlanProvider]. This
/// class only manages immutable room snapshots and their ordering.
class FloorPlanTransformHistoryEntry {
  final List<RoomModel> before;
  final List<RoomModel> after;

  FloorPlanTransformHistoryEntry({
    required List<RoomModel> before,
    required List<RoomModel> after,
  })  : before = List<RoomModel>.unmodifiable(before),
        after = List<RoomModel>.unmodifiable(after);
}

class FloorPlanTransformHistory {
  static const int maximumEntries = 50;

  final List<FloorPlanTransformHistoryEntry> _undo = [];
  final List<FloorPlanTransformHistoryEntry> _redo = [];

  bool canUndo(List<RoomModel> current) =>
      _undo.isNotEmpty && sameSnapshot(_undo.last.after, current);

  bool canRedo(List<RoomModel> current) =>
      _redo.isNotEmpty && sameSnapshot(_redo.last.before, current);

  FloorPlanTransformHistoryEntry? peekUndo(List<RoomModel> current) {
    return canUndo(current) ? _undo.last : null;
  }

  FloorPlanTransformHistoryEntry? peekRedo(List<RoomModel> current) {
    return canRedo(current) ? _redo.last : null;
  }

  void record(List<RoomModel> before, List<RoomModel> after) {
    if (sameSnapshot(before, after)) return;

    _undo.add(
      FloorPlanTransformHistoryEntry(
        before: before,
        after: after,
      ),
    );
    if (_undo.length > maximumEntries) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  bool moveUndoToRedo(FloorPlanTransformHistoryEntry entry) {
    if (_undo.isEmpty || !identical(_undo.last, entry)) return false;
    _undo.removeLast();
    _redo.add(entry);
    return true;
  }

  bool moveRedoToUndo(FloorPlanTransformHistoryEntry entry) {
    if (_redo.isEmpty || !identical(_redo.last, entry)) return false;
    _redo.removeLast();
    _undo.add(entry);
    return true;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  static bool sameSnapshot(
    List<RoomModel> first,
    List<RoomModel> second,
  ) {
    if (first.length != second.length) return false;

    for (var index = 0; index < first.length; index++) {
      if (!identical(first[index], second[index])) return false;
    }
    return true;
  }
}

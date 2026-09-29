import 'package:room_scanner_ar/providers/floor_plan_transform_history.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

RoomModel room(String id, double x) {
  return RoomModel(
    id: id,
    name: id,
    type: RoomType.living,
    points: [
      ARPoint(x: x, y: 0, z: 0),
      ARPoint(x: x + 2, y: 0, z: 0),
      ARPoint(x: x + 2, y: 0, z: 2),
    ],
  );
}

void main() {
  test('records undo and redo entries against the current snapshot', () {
    final history = FloorPlanTransformHistory();
    final before = [room('room', 0)];
    final after = [room('room', 1)];

    history.record(before, after);

    expect(history.canUndo(after), isTrue);
    final undo = history.peekUndo(after);
    expect(undo, isNotNull);
    expect(undo!.before.single.points.first.x, 0);

    expect(history.moveUndoToRedo(undo), isTrue);
    expect(history.canRedo(before), isTrue);

    final redo = history.peekRedo(before);
    expect(redo, same(undo));
    expect(history.moveRedoToUndo(redo!), isTrue);
    expect(history.canUndo(after), isTrue);
  });

  test('does not record identical snapshots and clears redo on a new transform', () {
    final history = FloorPlanTransformHistory();
    final first = [room('room', 0)];
    final second = [room('room', 1)];
    final third = [room('room', 2)];

    history.record(first, first);
    expect(history.canUndo(first), isFalse);

    history.record(first, second);
    final entry = history.peekUndo(second)!;
    history.moveUndoToRedo(entry);
    expect(history.canRedo(first), isTrue);

    history.record(first, third);
    expect(history.canRedo(first), isFalse);
    expect(history.canUndo(third), isTrue);
  });

  test('keeps at most the configured history depth', () {
    final history = FloorPlanTransformHistory();
    var current = [room('room', 0)];

    for (var i = 1; i <= FloorPlanTransformHistory.maximumEntries + 5; i++) {
      final next = [room('room', i.toDouble())];
      history.record(current, next);
      current = next;
    }

    expect(history.canUndo(current), isTrue);
    var count = 0;
    while (history.canUndo(current)) {
      final entry = history.peekUndo(current)!;
      current = entry.before;
      history.moveUndoToRedo(entry);
      count++;
    }

    expect(count, FloorPlanTransformHistory.maximumEntries);
  });

  test('clear removes both undo and redo history', () {
    final history = FloorPlanTransformHistory();
    final before = [room('room', 0)];
    final after = [room('room', 1)];

    history.record(before, after);
    final entry = history.peekUndo(after)!;
    history.moveUndoToRedo(entry);
    history.clear();

    expect(history.canUndo(after), isFalse);
    expect(history.canRedo(before), isFalse);
  });
}

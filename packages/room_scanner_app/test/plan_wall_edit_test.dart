import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:room_scanner_ar/providers/floor_plan_provider.dart';

ARPoint p(double x, double z) => ARPoint(x: x, y: 0, z: z);
RoomModel room(String id, List<ARPoint> points,
        {bool closed = true, List<WallFeature> features = const []}) =>
    RoomModel(
        id: id,
        name: id,
        type: RoomType.other,
        points: points,
        isClosed: closed,
        features: features);
FloorPlanProvider provider(List<RoomModel> rooms) =>
    FloorPlanProvider()..loadProject(uuid: 'p', name: 'Plan', rooms: rooms);

void main() {
  test('failed room deletion preserves room and history', () async {
    final source = room('source', [p(0, 0), p(1, 0), p(1, 1)]);
    final plan = provider([source]);
    addTearDown(plan.dispose);
    plan.persister = ({required String uuid, required String name, required List<RoomModel> rooms}) async {
      throw StateError('Save failed');
    };
    expect(await plan.removeRoom(source.id), isFalse);
    expect(plan.completedRooms, [source]);
    expect(plan.canUndoTransform, isFalse);
  });

  test('failed undo and redo retain geometry and retryable history', () async {
    final source = room('source', [p(0, 0), p(1, 0), p(1, 1)]);
    final plan = provider([source]);
    addTearDown(plan.dispose);
    expect(await plan.removeRoom(source.id), isTrue);
    Future<void> fail({required String uuid, required String name, required List<RoomModel> rooms}) async {
      throw StateError('Save failed');
    }
    plan.persister = fail;
    expect(await plan.undoTransform(), isFalse);
    expect(plan.completedRooms, isEmpty);
    expect(plan.canUndoTransform, isTrue);
    plan.persister = null;
    expect(await plan.undoTransform(), isTrue);
    plan.persister = fail;
    expect(await plan.redoTransform(), isFalse);
    expect(plan.completedRooms, [source]);
    expect(plan.canRedoTransform, isTrue);
  });
  test('queued saves preserve snapshots and continue after a failure', () async {
    final plan = provider([]);
    addTearDown(plan.dispose);
    final entered = Completer<void>();
    final release = Completer<void>();
    final snapshots = <List<String>>[];
    plan.persister = ({required String uuid, required String name, required List<RoomModel> rooms}) async {
      snapshots.add(rooms.map((r) => r.id).toList());
      if (snapshots.length == 1) {
        entered.complete();
        await release.future;
        throw StateError('First save failed');
      }
    };
    final a = room('a', [p(0, 0), p(1, 0), p(1, 1), p(0, 1)]);
    final b = room('b', [p(0, 0), p(1, 0), p(1, 1), p(0, 1)]);
    final first = plan.addCompletedRoom(a);
    await entered.future;
    final second = plan.addCompletedRoom(b);
    expect(snapshots, [['a']]);
    release.complete();
    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(snapshots, [['a'], ['a', 'b']]);
    expect(plan.completedRooms.map((r) => r.id), ['a', 'b']);
  });

  test('failed save does not restore a previous project into the current one', () async {
    final plan = provider([]);
    addTearDown(plan.dispose);
    final entered = Completer<void>();
    final release = Completer<void>();
    plan.persister = ({required String uuid, required String name, required List<RoomModel> rooms}) async {
      entered.complete();
      await release.future;
      throw StateError('Save failed');
    };
    final save = plan.addCompletedRoom(room('a', [p(0, 0), p(1, 0), p(1, 1)]));
    await entered.future;
    final other = room('other', [p(3, 0), p(4, 0), p(4, 1)]);
    plan.loadProject(uuid: 'other-project', name: 'Other', rooms: [other]);
    release.complete();
    expect(await save, isFalse);
    expect(plan.projectUuid, 'other-project');
    expect(plan.completedRooms, [other]);
  });

  test('failed import restores rooms and name', () async {
    final source = room('source', [p(0, 0), p(1, 0), p(1, 1)]);
    final plan = provider([source]);
    addTearDown(plan.dispose);
    plan.persister = ({required String uuid, required String name, required List<RoomModel> rooms}) async {
      throw StateError('Save failed');
    };
    expect(await plan.loadExistingRooms([], 'Imported'), isFalse);
    expect(plan.projectName, 'Plan');
    expect(plan.completedRooms, [source]);
  });

  test('failed plan edit restores geometry without adding undo history', () async {
    final source = room('source', [p(0, 0), p(1, 0), p(1, 1), p(0, 1)]);
    final plan = provider([source]);
    addTearDown(plan.dispose);
    plan.persister = ({required String uuid, required String name, required List<RoomModel> rooms}) async {
      throw StateError('Save failed');
    };
    final proposal = plan.previewGeometry(source, [p(0, 0), p(2, 0), p(2, 1), p(0, 1)]);
    expect(await plan.applyPlanEdit(proposal), isFalse);
    expect(plan.completedRooms, [source]);
    expect(plan.canUndoTransform, isFalse);
  });
  test(
      'delete complete room preserves neighbour and restores connections with undo',
      () async {
    final door = WallFeature(
        id: 'd',
        type: FeatureType.door,
        start: p(4, 1),
        end: p(4, 2),
        connectedRoomId: 'b');
    final a = room('a', [p(0, 0), p(4, 0), p(4, 3), p(0, 3)], features: [door]);
    final b = room('b', [p(4, 0), p(6, 0), p(6, 3), p(4, 3)],
        features: [door.copyWith(connectedRoomId: 'a')]);
    final plan = provider([a, b]);
    addTearDown(plan.dispose);
    final before = plan.completedRooms.map((r) => r.toJson()).toList();
    await plan.removeRoom('a');
    expect(plan.completedRooms.single.id, 'b');
    expect(plan.completedRooms.single.points, b.points);
    expect(plan.completedRooms.single.features.single.isConnected, isFalse);
    expect(await plan.undoTransform(), isTrue);
    expect(plan.completedRooms.map((r) => r.toJson()).toList(), before);
    expect(await plan.redoTransform(), isTrue);
    expect(plan.completedRooms.single.id, 'b');
    expect(plan.completedRooms.single.features.single.isConnected, isFalse);
  });
  test(
      'delete removes dependent opening and disconnects neighbour; undo restores both',
      () async {
    final d = WallFeature(
        id: 'd',
        type: FeatureType.door,
        start: p(4, 1),
        end: p(4, 2),
        connectedRoomId: 'b');
    final a = room('a', [p(0, 0), p(4, 0), p(4, 3), p(0, 3)], features: [d]);
    final b = room('b', [p(4, 0), p(6, 0), p(6, 3), p(4, 3)],
        features: [d.copyWith(connectedRoomId: 'a')]);
    final plan = provider([a, b]);
    addTearDown(plan.dispose);
    final before = plan.completedRooms.map((r) => r.toJson()).toList();
    final proposal = plan.previewDeleteWall(plan.completedRooms.first, 1);
    expect(plan.completedRooms.first.isClosed, isTrue);
    expect(await plan.applyPlanEdit(proposal), isTrue);
    expect(plan.completedRooms.first.features, isEmpty);
    expect(plan.completedRooms.last.features.single.isConnected, isFalse);
    expect(plan.totalProjectArea, 6);
    expect(await plan.undoTransform(), isTrue);
    expect(plan.completedRooms.map((r) => r.toJson()).toList(), before);
    expect(await plan.redoTransform(), isTrue);
    expect(plan.completedRooms.first.isClosed, isFalse);
  });
  test('wall length changes are undoable and reject stale previews', () async {
    final plan = provider([
      room('r', [p(0, 0), p(4, 0), p(4, 3), p(0, 3)])
    ]);
    addTearDown(plan.dispose);
    final original = plan.completedRooms.single;
    final proposal = plan.previewGeometry(
        original, PlanEditGeometry.resizeWall(original, 0, 5)!);
    expect(await plan.applyPlanEdit(proposal), isTrue);
    expect(await plan.applyPlanEdit(proposal), isFalse);
    expect(plan.completedRooms.single.points[1].x, 5);
    expect(await plan.undoTransform(), isTrue);
    expect(plan.completedRooms.single.points[1].x, 4);
    expect(
        (await plan.updateWallLength(
                roomId: 'r', wallIndex: 0, lengthMeters: 6))
            .isValid,
        isTrue);
    expect(plan.canRedoTransform, isFalse);
    expect(await plan.undoTransform(), isTrue);
    expect(plan.completedRooms.single.points[1].x, 4);
  });
  test('connected door is protected from a wall drag', () {
    final d = WallFeature(
        id: 'd',
        type: FeatureType.door,
        start: p(1, 0),
        end: p(2, 0),
        connectedRoomId: 'other');
    final plan = provider([
      room('r', [p(0, 0), p(4, 0), p(4, 3), p(0, 3)], features: [d])
    ]);
    addTearDown(plan.dispose);
    final original = plan.completedRooms.single;
    expect(
        plan
            .previewGeometry(
                original, PlanEditGeometry.moveWall(original, 0, 0, -1))
            .error,
        PlanEditError.connection);
    expect(plan.canUndoTransform, isFalse);
  });
  test(
      'closure preview is reversible and a phantom closing wall cannot hold an opening',
      () async {
    final plan = provider([
      room('r', [p(0, 0), p(4, 0), p(4, 3), p(0, 3)], closed: false)
    ]);
    addTearDown(plan.dispose);
    expect(plan.totalProjectArea, 0);
    final placement = await plan.placeOpeningOnWall(
        roomId: 'r',
        type: FeatureType.door,
        wallIndex: 3,
        location: p(0, 1),
        widthMeters: 0.8,
        openingHeightMeters: 2.1,
        sillHeightMeters: 0);
    expect(placement.isSuccess, isFalse);
    final proposal = plan.previewCloseRoom(plan.completedRooms.single);
    expect(proposal.error, isNull);
    expect(plan.completedRooms.single.isClosed, isFalse);
    expect(await plan.applyPlanEdit(proposal), isTrue);
    expect(plan.totalProjectArea, 12);
    expect(await plan.undoTransform(), isTrue);
    expect(plan.completedRooms.single.isClosed, isFalse);
  });
  test('continued open room replaces the original without duplication', () async {
    final open = room(
      'r',
      [p(0, 0), p(3, 0), p(3, 2)],
      closed: false,
    );
    final plan = provider([open]);
    addTearDown(plan.dispose);

    final closed = open.copyWith(
      points: [...open.points, p(0, 2)],
      isClosed: true,
    );
    expect(await plan.replaceCompletedRoom(closed), isTrue);
    expect(plan.completedRooms, hasLength(1));
    expect(plan.completedRooms.single.id, 'r');
    expect(plan.completedRooms.single.isClosed, isTrue);
    expect(plan.completedRooms.single.points, hasLength(4));
    expect(
      await plan.replaceCompletedRoom(closed.copyWith(id: 'missing')),
      isFalse,
    );
    expect(plan.completedRooms, hasLength(1));
  });

  test('open room can continue from either endpoint preserving its identity', () {
    final open = room(
      'angled',
      [p(0, 0), p(2.4, 1.1), p(4, 0.3)],
      closed: false,
    );
    final plan = provider([open]);
    addTearDown(plan.dispose);

    final fromLast = plan.prepareOpenRoomContinuation(
      roomId: 'angled',
      vertexIndex: 2,
    );
    expect(fromLast, same(plan.completedRooms.single));

    final fromFirst = plan.prepareOpenRoomContinuation(
      roomId: 'angled',
      vertexIndex: 0,
    );
    expect(fromFirst, isNotNull);
    expect(fromFirst!.id, 'angled');
    expect(fromFirst.points, open.points.reversed.toList());
    expect(fromFirst.points.last, open.points.first);

    expect(
      plan.prepareOpenRoomContinuation(
        roomId: 'angled',
        vertexIndex: 1,
      ),
      isNull,
    );
  });

  test('closed room can continue and close at any other corner', () {
    final closed = room(
      'closed',
      [p(0, 0), p(3, 0), p(3, 2), p(0, 2)],
    );
    final plan = provider([closed]);
    addTearDown(plan.dispose);

    for (var start = 0; start < closed.points.length; start++) {
      expect(
        plan.prepareOpenRoomContinuation(
          roomId: 'closed',
          vertexIndex: start,
        ),
        isNull,
      );
      for (var target = 0; target < closed.points.length; target++) {
        if (target == start) continue;
        final prepared = plan.prepareOpenRoomContinuation(
          roomId: 'closed',
          vertexIndex: start,
          closingVertexIndex: target,
        );
        expect(prepared, isNotNull);
        expect(prepared!.isClosed, isFalse);
        expect(prepared.id, isNot(closed.id));
        expect(prepared.points.first, closed.points[target]);
        expect(prepared.points.last, closed.points[start]);
        expect(prepared.points.toSet(), hasLength(prepared.points.length));
        expect(plan.completedRooms.single, same(closed));
      }
    }
  });

  test('saved continuation preserves its closed source and shared wall',
      () async {
    final closed = room(
      'closed-save',
      [p(0, 0), p(3, 0), p(3, 2), p(0, 2)],
    );
    final plan = provider([closed]);
    addTearDown(plan.dispose);
    final prepared = plan.prepareOpenRoomContinuation(
      roomId: 'closed-save',
      vertexIndex: 2,
      closingVertexIndex: 1,
    )!;
    expect(prepared.points, hasLength(2));
    final extended = prepared.copyWith(
      points: [...prepared.points, p(4, 2), p(4, 0)],
      isClosed: true,
    );

    await plan.addCompletedRoom(extended, preservePlacement: true);
    expect(plan.completedRooms, hasLength(2));
    expect(plan.completedRooms.first, same(closed));
    expect(plan.completedRooms.first.points, closed.points);
    expect(plan.completedRooms.last.points.first, closed.points[1]);
    expect(
      plan.completedRooms.last.points[prepared.points.length - 1],
      closed.points[2],
    );
  });

  test('adjacent corner continuation uses the short shared wall in both directions', () {
    final source = room('source', [p(0, 0), p(3, 0), p(3, 3), p(0, 3)]);
    final plan = provider([source]);
    addTearDown(plan.dispose);
    for (final pair in [[0, 1], [1, 0]]) {
      final prepared = plan.prepareOpenRoomContinuation(
        roomId: source.id, vertexIndex: pair[0], closingVertexIndex: pair[1])!;
      expect(prepared.points, [source.points[pair[1]], source.points[pair[0]]]);
    }
  });

  test('preserved-placement scan rejects source overlap without changing plan', () async {
    final source = room('source', [p(0, 0), p(3, 0), p(3, 3), p(0, 3)]);
    final plan = provider([source]);
    addTearDown(plan.dispose);
    final overlapping = room('new', [p(3, 0), p(3, 3), p(0, 3), p(0, 0), p(0, -2), p(3, -2)]);
    expect(await plan.addCompletedRoom(overlapping, preservePlacement: true), isFalse);
    expect(plan.completedRooms, [source]);
  });

  test('failed scan persistence rolls back and allows retry', () async {
    final plan = provider([]);
    addTearDown(plan.dispose);
    final scanned = room('new', [p(0, 0), p(3, 0), p(3, 3), p(0, 3)]);
    plan.persister = ({required String uuid, required String name, required List<RoomModel> rooms}) async {
      throw StateError('Disk unavailable');
    };
    expect(await plan.addCompletedRoom(scanned), isFalse);
    expect(plan.completedRooms, isEmpty);
    plan.persister = ({required String uuid, required String name, required List<RoomModel> rooms}) async {};
    expect(await plan.addCompletedRoom(scanned), isTrue);
    expect(plan.completedRooms, [scanned]);
  });

}

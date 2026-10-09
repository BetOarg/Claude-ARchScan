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
  test('WallFeature copyWith can explicitly clear shared-opening references', () {
    final feature = WallFeature(
      id: 'shared',
      type: FeatureType.door,
      start: p(0, 0),
      end: p(1, 0),
      connectedRoomId: 'other',
      connectionSide: OpeningConnectionSide.right,
    );

    final disconnected = feature.copyWith(
      connectedRoomId: null,
      connectionSide: null,
    );

    expect(disconnected.connectedRoomId, isNull);
    expect(disconnected.connectionSide, isNull);
    expect(disconnected.id, feature.id);
    expect(disconnected.type, feature.type);
    expect(disconnected.start.toJson(), feature.start.toJson());
    expect(disconnected.end.toJson(), feature.end.toJson());
  });

  test('duplicate room IDs disconnect ambiguous shared-opening references', () {
    final first = room(
      'duplicate',
      [p(0, 0), p(2, 0), p(2, 2), p(0, 2)],
      features: [
        WallFeature(
          id: 'opening-a',
          type: FeatureType.door,
          start: p(2, 0.5),
          end: p(2, 1.5),
          connectedRoomId: 'duplicate',
          connectionSide: OpeningConnectionSide.right,
        ),
      ],
    );
    final second = room(
      'duplicate',
      [p(2, 0), p(4, 0), p(4, 2), p(2, 2)],
      features: [
        WallFeature(
          id: 'opening-b',
          type: FeatureType.door,
          start: p(2, 0.5),
          end: p(2, 1.5),
          connectedRoomId: 'duplicate',
          connectionSide: OpeningConnectionSide.left,
        ),
      ],
    );

    final plan = provider([first, second]);
    addTearDown(plan.dispose);

    expect(plan.completedRooms, hasLength(2));
    expect(
      plan.completedRooms.map((room) => room.id).toSet(),
      hasLength(2),
    );
    expect(
      plan.completedRooms.every(
        (room) => room.features.every(
          (feature) => !feature.isConnected && feature.connectionSide == null,
        ),
      ),
      isTrue,
    );
  });

  test('orphaned shared-opening references are disconnected', () {
    final roomA = room(
      'room-a',
      [p(0, 0), p(2, 0), p(2, 2)],
      features: [
        WallFeature(
          id: 'missing-target',
          type: FeatureType.door,
          start: p(2, 0.5),
          end: p(2, 1.5),
          connectedRoomId: 'deleted-room',
          connectionSide: OpeningConnectionSide.right,
        ),
        WallFeature(
          id: 'self-target',
          type: FeatureType.window,
          start: p(0.5, 0),
          end: p(1.5, 0),
          connectedRoomId: 'room-a',
          connectionSide: OpeningConnectionSide.left,
        ),
        WallFeature(
          id: 'side-only',
          type: FeatureType.window,
          start: p(0.5, 2),
          end: p(1.5, 2),
          connectionSide: OpeningConnectionSide.left,
        ),
      ],
    );
    final plan = provider([roomA]);
    addTearDown(plan.dispose);

    for (final feature in plan.completedRooms.single.features) {
      expect(feature.connectedRoomId, isNull);
      expect(feature.connectionSide, isNull);
      expect(feature.isConnected, isFalse);
    }
  });

  test('duplicate opening IDs are normalized only within each room', () {
    final sharedA = WallFeature(
      id: 'shared-opening',
      type: FeatureType.door,
      start: p(2, 0.5),
      end: p(2, 1.5),
      connectedRoomId: 'room-b',
      connectionSide: OpeningConnectionSide.right,
    );
    final sharedB = sharedA.copyWith(
      connectedRoomId: 'room-a',
      connectionSide: OpeningConnectionSide.left,
      start: p(2, 1.5),
      end: p(2, 0.5),
    );
    final first = room('room-a', [p(0, 0), p(2, 0), p(2, 2)], features: [
      sharedA,
      sharedA.copyWith(start: p(1, 0.2), end: p(1, 0.8)),
    ]);
    final second = room('room-b', [p(2, 0), p(4, 0), p(4, 2)], features: [
      sharedB,
    ]);

    final plan = provider([first, second]);
    addTearDown(plan.dispose);

    final roomA = plan.completedRooms.firstWhere((room) => room.id == 'room-a');
    final roomB = plan.completedRooms.firstWhere((room) => room.id == 'room-b');
    expect(roomA.features.map((feature) => feature.id).toSet(), hasLength(2));
    expect(roomA.features.first.id, 'shared-opening');
    expect(roomB.features.single.id, 'shared-opening');
  });

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
  test('failed wall length update restores geometry and reports persistence failure', () async {
    final source = room('source', [p(0, 0), p(2, 0), p(2, 1), p(0, 1)]);
    final plan = provider([source]);
    addTearDown(plan.dispose);
    plan.persister = ({required String uuid, required String name, required List<RoomModel> rooms}) async {
      throw StateError('Save failed');
    };

    final result = await plan.updateWallLength(
      roomId: 'source',
      wallIndex: 0,
      lengthMeters: 3,
    );

    expect(result.isValid, isFalse);
    expect(plan.completedRooms.single.points[1].x, 2);
    expect(plan.canUndoTransform, isFalse);
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

  test('new-project import switches state only after successful persistence', () async {
    final source = room('source', [p(0, 0), p(1, 0), p(1, 1)]);
    final imported = room('imported-room', [p(4, 0), p(5, 0), p(5, 1)]);
    final plan = provider([source]);
    addTearDown(plan.dispose);
    String? savedUuid;
    String? savedName;
    List<RoomModel>? savedRooms;
    plan.persister = ({required String uuid, required String name, required List<RoomModel> rooms}) async {
      savedUuid = uuid;
      savedName = name;
      savedRooms = List<RoomModel>.from(rooms);
    };

    expect(
      await plan.loadImportedProject(
        uuid: 'new-project',
        name: 'Imported',
        rooms: [imported],
      ),
      isTrue,
    );
    expect(savedUuid, 'new-project');
    expect(savedName, 'Imported');
    expect(savedRooms?.single.id, 'imported-room');
    expect(plan.projectUuid, 'new-project');
    expect(plan.projectName, 'Imported');
    expect(plan.completedRooms, [imported]);
  });

  test('failed new-project import preserves active project and rooms', () async {
    final source = room('source', [p(0, 0), p(1, 0), p(1, 1)]);
    final plan = provider([source]);
    addTearDown(plan.dispose);
    plan.persister = ({required String uuid, required String name, required List<RoomModel> rooms}) async {
      expect(uuid, 'new-project');
      expect(name, 'Imported');
      expect(rooms, isEmpty);
      throw StateError('Save failed');
    };

    expect(
      await plan.loadImportedProject(
        uuid: 'new-project',
        name: 'Imported',
        rooms: const [],
      ),
      isFalse,
    );
    expect(plan.projectUuid, 'p');
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
  test('removing an unknown room is a no-op and does not create undo history', () async {
    final opening = WallFeature(
      id: 'shared',
      type: FeatureType.door,
      start: p(2, 0.5),
      end: p(2, 1.5),
      connectedRoomId: 'b',
      connectionSide: OpeningConnectionSide.right,
    );
    final a = room(
      'a',
      [p(0, 0), p(2, 0), p(2, 2), p(0, 2)],
      features: [opening],
    );
    final b = room(
      'b',
      [p(2, 0), p(4, 0), p(4, 2), p(2, 2)],
      features: [
        opening.copyWith(
          connectedRoomId: 'a',
          connectionSide: OpeningConnectionSide.left,
        ),
      ],
    );
    final plan = provider([a, b]);
    addTearDown(plan.dispose);
    final before = plan.completedRooms.map((r) => r.toJson()).toList();

    expect(await plan.removeRoom('missing-room'), isFalse);
    expect(plan.completedRooms.map((r) => r.toJson()).toList(), before);
    expect(plan.canUndoTransform, isFalse);
    expect(plan.canRedoTransform, isFalse);
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
    expect(plan.completedRooms.single.features.single.connectedRoomId, isNull);
    expect(plan.completedRooms.single.features.single.connectionSide, isNull);
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
  test('open wall deletion reassigns shared opening to retained fragment', () async {
    final opening = WallFeature(
      id: 'shared-opening',
      type: FeatureType.door,
      start: p(1, 2),
      end: p(1.8, 2),
      connectedRoomId: 'neighbour',
      connectionSide: OpeningConnectionSide.left,
    );
    final source = room(
      'source',
      [p(0, 0), p(2, 0), p(2, 2), p(0, 2)],
      closed: false,
      features: [opening],
    );
    final neighbour = room(
      'neighbour',
      [p(0, 2), p(-2, 2), p(-2, 4), p(0, 4)],
      features: [
        opening.copyWith(
          connectedRoomId: 'source',
          connectionSide: OpeningConnectionSide.right,
        ),
      ],
    );
    final plan = provider([source, neighbour]);
    addTearDown(plan.dispose);

    final proposal = plan.previewDeleteWall(plan.completedRooms.first, 1);
    expect(await plan.applyPlanEdit(proposal), isTrue);

    final fragments = plan.completedRooms.where((r) => r.id != 'neighbour').toList();
    expect(fragments, hasLength(2));
    final retained = fragments
        .where((r) => r.features.any((f) => f.id == 'shared-opening'))
        .single;
    final counterpart = plan.completedRooms
        .singleWhere((r) => r.id == 'neighbour')
        .features
        .single;
    expect(counterpart.connectedRoomId, retained.id);
    expect(counterpart.connectionSide, OpeningConnectionSide.right);

    expect(await plan.undoTransform(), isTrue);
    expect(plan.completedRooms.singleWhere((r) => r.id == 'source').id, 'source');
    expect(await plan.redoTransform(), isTrue);
    expect(
      plan.completedRooms.singleWhere((r) => r.id == 'neighbour')
          .features.single.connectedRoomId,
      retained.id,
    );
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
      room('r', [p(0, 0), p(4, 0), p(4, 3), p(0, 3)], features: [d]),
      room('other', [p(10, 0), p(12, 0), p(12, 3), p(10, 3)]),
    ]);
    addTearDown(plan.dispose);
    final original = plan.completedRooms.firstWhere((room) => room.id == 'r');
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

  test('closed continuation can target a corner from another room', () async {
    final source = room(
      'source-cross',
      [p(0, 0), p(3, 0), p(3, 3), p(0, 3)],
    );
    final target = room(
      'target-cross',
      [p(6, 0), p(8, 0), p(8, 2), p(6, 2)],
    );
    final plan = provider([source, target]);
    addTearDown(plan.dispose);

    final prepared = plan.prepareOpenRoomContinuation(
      roomId: source.id,
      vertexIndex: 1,
      closingRoomId: target.id,
      closingVertexIndex: 3,
    );

    expect(prepared, isNotNull);
    expect(prepared!.isClosed, isFalse);
    expect(prepared.points, [target.points[3], source.points[1]]);
    expect(prepared.id, isNot(source.id));
    expect(prepared.id, isNot(target.id));
    final reference = ScanContinuationReference.fromCorners(
      sourceRoomId: source.id,
      sourcePoint: source.points[1],
      targetRoomId: target.id,
      targetPoint: target.points[3],
    );
    final scanned = RoomModel(
      id: 'new',
      name: 'new',
      type: RoomType.other,
      points: [source.points[1], p(4.5, 0), target.points[3]],
      isClosed: true,
    );
    expect(
      await plan.addCompletedRoomFromContinuation(
        room: scanned,
        reference: reference,
      ),
      isTrue,
    );
    expect(plan.completedRooms, hasLength(3));
    expect(plan.completedRooms.first.id, source.id);
    expect(plan.completedRooms[1].id, target.id);
    expect(plan.completedRooms[2].id, 'new');
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

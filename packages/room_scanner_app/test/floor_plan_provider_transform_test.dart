import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/providers/floor_plan_provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

void main() {

  group('ajuste táctil de aberturas fuera del centro', () {
    for (final angle in [0.0, 5.0]) {
      test('conserva la posición longitudinal al ajustar $angle grados', () async {
        final rooms = _connectedRooms().map((room) => room.copyWith(
          points: room.points.map((p) =>
              ARPoint(x: p.x, y: p.y, z: p.z == 2 ? 6 : p.z)).toList(),
        )).toList();
        final provider = FloorPlanProvider()..loadProject(
          uuid: 'off-centre', name: 'Plan', rooms: rooms,
        );
        addTearDown(provider.dispose);
        final before = provider.completedRooms.map((r) => r.toJson()).toList();
        expect(provider.beginTouchRoomTransform('room-b'), isTrue);
        expect(provider.updateTouchRoomTransform(
          roomId: 'room-b', offsetX: 0.3, offsetZ: 0.2,
          angleDegrees: angle,
        ), isTrue);
        expect(await provider.endTouchRoomTransform(roomId: 'room-b'), isTrue);
        final moved = provider.completedRooms[1];
        expect(provider.completedRooms[0].toJson(), before[0]);
        expect(moved.points.first.x, closeTo(2, 1e-8));
        expect(moved.points.last.x, closeTo(2, 1e-8));
        expect(moved.points.last.z - moved.points.first.z, closeTo(6, 1e-8));
        // The door remains near the first corner, never centred on a 6m wall.
        expect(moved.points.first.z, inExclusiveRange(-0.5, 0.5));
        if (angle == 0) {
          expect(moved.points.first.z, closeTo(0.2, 1e-8));
        }
        _expectSameFeatureGeometry(rooms[1].features.single, moved.features.single);
        final after = provider.completedRooms.map((r) => r.toJson()).toList();
        expect(await provider.undoTransform(), isTrue);
        expect(provider.completedRooms.map((r) => r.toJson()).toList(), before);
        expect(await provider.redoTransform(), isTrue);
        expect(provider.completedRooms.map((r) => r.toJson()).toList(), after);
      });
    }
  });

  group('organización conserva el plano ensamblado', () {
    test('un único grupo conectado no cambia ni crea historial', () async {
      final provider = FloorPlanProvider()..loadProject(
        uuid: 'arrange', name: 'Plan', rooms: _connectedRooms(),
      );
      addTearDown(provider.dispose);
      final original = provider.completedRooms.map((r) => r.toJson()).toList();
      expect(await provider.autoArrangeRooms(), isFalse);
      expect(provider.completedRooms.map((r) => r.toJson()).toList(), original);
      expect(provider.canUndoTransform, isFalse);
    });

    test('mueve el grupo completo y deshace toda la organización', () async {
      final provider = FloorPlanProvider()..loadProject(
        uuid: 'arrange', name: 'Plan',
        rooms: [_independentRoom(offsetX: 10), ..._connectedRooms()],
      );
      addTearDown(provider.dispose);
      final original = provider.completedRooms.map((r) => r.toJson()).toList();
      expect(await provider.autoArrangeRooms(spacing: 1), isTrue);
      final arranged = provider.completedRooms.map((r) => r.toJson()).toList();
      expect(provider.completedRooms[0].points.first.x, 10);
      expect(provider.completedRooms[1].points.first.x, 13);
      expect(provider.completedRooms[2].points.first.x, 15);
      _expectSameFeatureGeometry(provider.completedRooms[1].features.single,
          provider.completedRooms[2].features.single);
      expect(SharedWallService.detect(rooms: provider.completedRooms), hasLength(1));
      expect(await provider.autoArrangeRooms(spacing: 1), isFalse);
      expect(await provider.undoTransform(), isTrue);
      expect(provider.completedRooms.map((r) => r.toJson()).toList(), original);
      expect(await provider.redoTransform(), isTrue);
      expect(provider.completedRooms.map((r) => r.toJson()).toList(), arranged);
    });

    test('preserva paredes completas y parciales sin conexiones explícitas', () async {
      final rooms = _connectedRooms().map((r) =>
          r.copyWith(features: const [])).toList();
      rooms.add(RoomModel(
        id: 'partial', name: 'Partial', type: RoomType.living, isClosed: true,
        points: [
          ARPoint(x: 4, y: 0, z: 1), ARPoint(x: 6, y: 0, z: 1),
          ARPoint(x: 6, y: 0, z: 3), ARPoint(x: 4, y: 0, z: 3),
        ],
      ));
      final provider = FloorPlanProvider()..loadProject(
        uuid: 'arrange', name: 'Plan',
        rooms: [_independentRoom(offsetX: 10), ...rooms],
      );
      addTearDown(provider.dispose);
      expect(await provider.autoArrangeRooms(spacing: 1), isTrue);
      for (var i = 0; i < rooms.length; i++) {
        final moved = provider.completedRooms[i + 1];
        for (var j = 0; j < rooms[i].points.length; j++) {
          expect(moved.points[j].x, closeTo(rooms[i].points[j].x + 13, 1e-8));
          expect(moved.points[j].z, rooms[i].points[j].z);
        }
      }
      final shared = SharedWallService.detect(rooms: provider.completedRooms);
      expect(shared, hasLength(2));
      expect(shared.any((w) => w.coverage == SharedWallCoverage.partial), isTrue);
    });

    test('no separa ambientes acomodados con una junta pequeña', () async {
      final first = _connectedRooms().first.copyWith(features: const []);
      final second = _independentRoom(offsetX: 2.08);
      final provider = FloorPlanProvider()..loadProject(
        uuid: 'arrange-small-gap', name: 'Plan', rooms: [first, second],
      );
      addTearDown(provider.dispose);
      final original = provider.completedRooms.map((r) => r.toJson()).toList();

      expect(await provider.autoArrangeRooms(spacing: 1), isFalse);
      expect(provider.completedRooms.map((r) => r.toJson()).toList(), original);
      expect(provider.canUndoTransform, isFalse);
    });

    test('separa escaneos históricos superpuestos sin conexión', () async {
      final first = _connectedRooms().first.copyWith(features: const []);
      final provider = FloorPlanProvider()..loadProject(
        uuid: 'arrange', name: 'Plan',
        rooms: [first, first.copyWith(id: 'duplicate')],
      );
      addTearDown(provider.dispose);
      expect(await provider.autoArrangeRooms(spacing: 1), isTrue);
      expect(provider.completedRooms.first.points.first.x, 0);
      expect(provider.completedRooms.last.points.first.x, 3);
    });

    test('un espaciado inválido no modifica el proyecto', () async {
      final provider = FloorPlanProvider()..loadProject(
        uuid: 'arrange', name: 'Plan',
        rooms: [_independentRoom(offsetX: 10), ..._connectedRooms()],
      );
      addTearDown(provider.dispose);
      final original = provider.completedRooms.map((r) => r.toJson()).toList();
      for (final spacing in [-1.0, double.nan, double.infinity]) {
        expect(await provider.autoArrangeRooms(spacing: spacing), isFalse);
      }
      expect(provider.completedRooms.map((r) => r.toJson()).toList(), original);
      expect(provider.canUndoTransform, isFalse);
    });
  });

  group('transformación rígida de ambientes', () {
    test('traslada como una unidad dos ambientes conectados', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-transform',
        name: 'Casa conectada',
        rooms: _connectedRooms(),
      );

      await provider.translateRoom(
        roomId: 'room-a',
        offsetX: 5,
        offsetZ: -2,
      );

      final roomA = provider.completedRooms
          .firstWhere((room) => room.id == 'room-a');
      final roomB = provider.completedRooms
          .firstWhere((room) => room.id == 'room-b');
      final featureA = roomA.features.single;
      final featureB = roomB.features.single;

      expect(roomA.points.first.x, closeTo(5, 0.000001));
      expect(roomA.points.first.z, closeTo(-2, 0.000001));
      expect(roomB.points.first.x, closeTo(7, 0.000001));
      expect(roomB.points.first.z, closeTo(-2, 0.000001));
      _expectSameFeatureGeometry(featureA, featureB);
    });

    test('rota el grupo y conserva longitudes y abertura compartida', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-rotation',
        name: 'Casa conectada',
        rooms: _connectedRooms(),
      );
      final before = provider.completedRooms;
      final wallLengthBefore = GeometryService.calculateDistance(
        before.first.points[0],
        before.first.points[1],
      );

      await provider.rotateRoom(
        roomId: 'room-a',
        angleDegrees: 90,
      );

      final roomA = provider.completedRooms
          .firstWhere((room) => room.id == 'room-a');
      final roomB = provider.completedRooms
          .firstWhere((room) => room.id == 'room-b');
      final wallLengthAfter = GeometryService.calculateDistance(
        roomA.points[0],
        roomA.points[1],
      );

      expect(wallLengthAfter, closeTo(wallLengthBefore, 0.000001));
      expect(
        GeometryService.calculateArea(roomA.points),
        closeTo(4, 0.000001),
      );
      expect(
        GeometryService.calculateArea(roomB.points),
        closeTo(4, 0.000001),
      );
      _expectSameFeatureGeometry(
        roomA.features.single,
        roomB.features.single,
      );
    });

    test('no transforma ambientes que no pertenecen al grupo', () async {
      final provider = FloorPlanProvider();
      final rooms = _connectedRooms()
        ..add(
          RoomModel(
            id: 'room-c',
            name: 'Independiente',
            type: RoomType.dormitorio,
            points: [
              ARPoint(x: 10, y: 0, z: 10),
              ARPoint(x: 12, y: 0, z: 10),
              ARPoint(x: 12, y: 0, z: 12),
              ARPoint(x: 10, y: 0, z: 12),
            ],
            isClosed: true,
          ),
        );
      provider.loadProject(
        uuid: 'project-independent',
        name: 'Tres ambientes',
        rooms: rooms,
      );

      await provider.translateRoom(
        roomId: 'room-a',
        offsetX: 3,
        offsetZ: 4,
      );

      final roomC = provider.completedRooms
          .firstWhere((room) => room.id == 'room-c');
      expect(roomC.points.first.x, closeTo(10, 0.000001));
      expect(roomC.points.first.z, closeTo(10, 0.000001));
    });

    test('deshace y rehace movimientos y giros en orden', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-history',
        name: 'Casa conectada',
        rooms: _connectedRooms(),
      );
      final originalFirstPoint = provider.completedRooms.first.points.first;

      await provider.translateRoom(
        roomId: 'room-a',
        offsetX: 3,
        offsetZ: -1,
      );
      final translatedFirstPoint =
          provider.completedRooms.first.points.first;
      await provider.rotateRoom(
        roomId: 'room-a',
        angleDegrees: 90,
      );
      final rotatedFirstPoint = provider.completedRooms.first.points.first;

      expect(provider.canUndoTransform, isTrue);
      expect(await provider.undoTransform(), isTrue);
      expect(
        provider.completedRooms.first.points.first.x,
        closeTo(translatedFirstPoint.x, 0.000001),
      );
      expect(
        provider.completedRooms.first.points.first.z,
        closeTo(translatedFirstPoint.z, 0.000001),
      );

      expect(await provider.undoTransform(), isTrue);
      expect(
        provider.completedRooms.first.points.first.x,
        closeTo(originalFirstPoint.x, 0.000001),
      );
      expect(
        provider.completedRooms.first.points.first.z,
        closeTo(originalFirstPoint.z, 0.000001),
      );
      expect(provider.canUndoTransform, isFalse);
      expect(provider.canRedoTransform, isTrue);

      expect(await provider.redoTransform(), isTrue);
      expect(await provider.redoTransform(), isTrue);
      expect(
        provider.completedRooms.first.points.first.x,
        closeTo(rotatedFirstPoint.x, 0.000001),
      );
      expect(
        provider.completedRooms.first.points.first.z,
        closeTo(rotatedFirstPoint.z, 0.000001),
      );
      _expectSameFeatureGeometry(
        provider.completedRooms[0].features.single,
        provider.completedRooms[1].features.single,
      );
    });

    test('integra el cambio de nombre en el historial sin perder el movimiento', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-safe-history',
        name: 'Casa conectada',
        rooms: _connectedRooms(),
      );

      await provider.translateRoom(
        roomId: 'room-a',
        offsetX: 1,
        offsetZ: 0,
      );
      await provider.updateRoomName('room-a', 'Living principal');

      expect(provider.canUndoTransform, isTrue);
      expect(provider.completedRooms.first.name, 'Living principal');
      final movedX = provider.completedRooms.first.points.first.x;
      expect(await provider.undoTransform(), isTrue);
      expect(provider.completedRooms.first.name, _connectedRooms().first.name);
      expect(provider.completedRooms.first.points.first.x, movedX);
      expect(await provider.undoTransform(), isTrue);
      expect(provider.completedRooms.first.points.first.x, closeTo(movedX - 1, 0.000001));
      expect(await provider.redoTransform(), isTrue);
      expect(await provider.redoTransform(), isTrue);
      expect(provider.completedRooms.first.name, 'Living principal');
    });

    test('alinea paredes cercanas sin separar el grupo conectado', () async {
      final provider = FloorPlanProvider();
      final rooms = _connectedRooms()
        ..add(_independentRoom(offsetX: 4.2));
      provider.loadProject(
        uuid: 'project-alignment',
        name: 'Casa para alinear',
        rooms: rooms,
      );

      final aligned = await provider.alignRoomToNearestWall(
        roomId: 'room-b',
      );

      expect(aligned, isTrue);
      expect(provider.completedRooms[0].points.first.x, closeTo(0.2, 0.000001));
      expect(provider.completedRooms[1].points[1].x, closeTo(4.2, 0.000001));
      expect(provider.completedRooms[2].points.first.x, closeTo(4.2, 0.000001));
      _expectSameFeatureGeometry(
        provider.completedRooms[0].features.single,
        provider.completedRooms[1].features.single,
      );

      expect(provider.canUndoTransform, isTrue);
      expect(await provider.undoTransform(), isTrue);
      expect(provider.completedRooms[0].points.first.x, closeTo(0, 0.000001));
      expect(provider.completedRooms[1].points[1].x, closeTo(4, 0.000001));
    });

    test('rechaza la alineación cuando no hay paredes cercanas', () async {
      final provider = FloorPlanProvider();
      final rooms = _connectedRooms()
        ..add(_independentRoom(offsetX: 10));
      provider.loadProject(
        uuid: 'project-no-alignment',
        name: 'Casa separada',
        rooms: rooms,
      );

      final aligned = await provider.alignRoomToNearestWall(
        roomId: 'room-b',
      );

      expect(aligned, isFalse);
      expect(provider.canUndoTransform, isFalse);
      expect(provider.completedRooms[1].points[1].x, closeTo(4, 0.000001));
    });

    test('rechaza una alineación que solaparía otro ambiente', () async {
      final provider = FloorPlanProvider();
      final rooms = _connectedRooms()
        ..add(_independentRoom(offsetX: 4.2))
        ..add(_diamondObstacle());
      provider.loadProject(
        uuid: 'project-overlap-safe-alignment',
        name: 'Casa con obstáculo',
        rooms: rooms,
      );

      final aligned = await provider.alignRoomToNearestWall(
        roomId: 'room-b',
      );

      expect(aligned, isFalse);
      expect(provider.canUndoTransform, isFalse);
      expect(provider.completedRooms[0].points.first.x, closeTo(0, 0.000001));
      expect(provider.completedRooms[1].points[1].x, closeTo(4, 0.000001));
    });

    test('corrige un hueco pequeño entre paredes candidatas', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-small-gap',
        name: 'Casa con hueco pequeño',
        rooms: _connectedRooms()
          ..add(_independentRoom(offsetX: 4.05)),
      );

      final result = await provider.correctSmallWallGap(
        roomId: 'room-b',
      );

      expect(result, WallAlignmentResult.aligned);
      expect(
        provider.completedRooms[0].points.first.x,
        closeTo(0.05, 0.000001),
      );
      expect(
        provider.completedRooms[1].points[1].x,
        closeTo(4.05, 0.000001),
      );
      expect(
        provider.completedRooms[2].points.first.x,
        closeTo(4.05, 0.000001),
      );
      expect(provider.canUndoTransform, isTrue);
    });

    test('ignora una separación mayor que el límite de hueco pequeño', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-large-gap',
        name: 'Casa con separación amplia',
        rooms: _connectedRooms()
          ..add(_independentRoom(offsetX: 4.15)),
      );

      final result = await provider.correctSmallWallGap(
        roomId: 'room-b',
      );

      expect(result, WallAlignmentResult.noCandidate);
      expect(provider.completedRooms[1].points[1].x, closeTo(4, 0.000001));
      expect(provider.canUndoTransform, isFalse);
    });

    test(
      'informa cuando evita una corrección que produciría solapamiento',
      () async {
        final provider = FloorPlanProvider();
        provider.loadProject(
          uuid: 'project-small-gap-overlap',
          name: 'Casa con corrección bloqueada',
          rooms: _connectedRooms()
            ..add(_independentRoom(offsetX: 4.05))
            ..add(_diamondObstacle()),
        );

        final result = await provider.correctSmallWallGap(
          roomId: 'room-b',
        );

        expect(result, WallAlignmentResult.overlapPrevented);
        expect(
          provider.completedRooms[0].points.first.x,
          closeTo(0, 0.000001),
        );
        expect(
          provider.completedRooms[1].points[1].x,
          closeTo(4, 0.000001),
        );
        expect(provider.canUndoTransform, isFalse);
      },
    );

    test('mueve y ajusta automáticamente como una sola operación', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-automatic-adjustment',
        name: 'Casa con ajuste automático',
        rooms: _connectedRooms()
          ..add(_independentRoom(offsetX: 4.15)),
      );

      final result = await provider.translateRoomAutomatically(
        roomId: 'room-b',
        offsetX: 0.10,
        offsetZ: 0,
      );

      expect(result, AutomaticRoomMoveResult.movedAndAdjusted);
      expect(
        provider.completedRooms[1].points[1].x,
        closeTo(4.15, 0.000001),
      );
      expect(await provider.undoTransform(), isTrue);
      expect(
        provider.completedRooms[1].points[1].x,
        closeTo(4, 0.000001),
      );
    });

    test('rechaza un movimiento manual que solaparía otro ambiente', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-rejected-movement',
        name: 'Casa con movimiento bloqueado',
        rooms: _connectedRooms()
          ..add(_independentRoom(offsetX: 4.5)),
      );

      final result = await provider.translateRoomAutomatically(
        roomId: 'room-b',
        offsetX: 0.75,
        offsetZ: 0,
      );

      expect(result, AutomaticRoomMoveResult.rejectedOverlap);
      expect(provider.completedRooms.first.points.first.x, closeTo(0, 0.000001));
      expect(provider.completedRooms[1].points[1].x, closeTo(4, 0.000001));
      expect(provider.canUndoTransform, isFalse);
    });

    test('rechaza una rotación manual que solaparía otro ambiente', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-rejected-rotation',
        name: 'Casa con rotación bloqueada',
        rooms: _connectedRooms()..add(_rotationObstacle()),
      );

      final rotated = await provider.rotateRoom(
        roomId: 'room-a',
        angleDegrees: 90,
      );

      expect(rotated, isFalse);
      expect(provider.completedRooms.first.points.first.x, closeTo(0, 0.000001));
      expect(provider.completedRooms.first.points.first.z, closeTo(0, 0.000001));
      expect(provider.canUndoTransform, isFalse);
    });

    test('la vista previa no modifica el plano ni el historial', () {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-alignment-preview',
        name: 'Casa con vista previa',
        rooms: _connectedRooms()
          ..add(_independentRoom(offsetX: 4.2)),
      );
      final before = provider.completedRooms;

      final result = provider.createWallAlignmentPreview(
        roomId: 'room-b',
      );

      expect(result.status, WallAlignmentPreviewStatus.available);
      expect(result.preview, isNotNull);
      expect(provider.canUndoTransform, isFalse);
      expect(provider.canRedoTransform, isFalse);
      expect(
        provider.completedRooms[0].points.first.x,
        closeTo(before[0].points.first.x, 0.000001),
      );
      expect(
        provider.completedRooms[1].points[1].x,
        closeTo(before[1].points[1].x, 0.000001),
      );
      expect(
        result.preview!.proposedRooms[1].points[1].x,
        closeTo(4.2, 0.000001),
      );
    });

    test('rechaza una vista previa si el plano cambió', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-stale-alignment-preview',
        name: 'Casa con vista previa vencida',
        rooms: _connectedRooms()
          ..add(_independentRoom(offsetX: 4.2)),
      );
      final preview = provider
          .createWallAlignmentPreview(roomId: 'room-b')
          .preview!;

      await provider.updateRoomName('room-a', 'Living modificado');
      final result = await provider.applyWallAlignmentPreview(preview);

      expect(result, WallAlignmentResult.stalePreview);
      expect(provider.completedRooms.first.name, 'Living modificado');
      expect(provider.completedRooms[1].points[1].x, closeTo(4, 0.000001));
      // The rejected alignment adds no history; the preceding rename does.
      expect(provider.canUndoTransform, isTrue);
      expect(await provider.undoTransform(), isTrue);
      expect(provider.completedRooms.first.name, _connectedRooms().first.name);
      expect(provider.completedRooms[1].points[1].x, closeTo(4, 0.000001));
      expect(provider.canUndoTransform, isFalse);
    });


    test('aplica un ajuste preciso como una sola operación', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-precise-transform',
        name: 'Casa con ajuste preciso',
        rooms: _connectedRooms(),
      );

      final applied = await provider.transformRoomPrecisely(
        roomId: 'room-a',
        offsetX: 1,
        offsetZ: -1,
        angleDegrees: 90,
      );

      expect(applied, isTrue);
      expect(provider.completedRooms[0].points.first.x, closeTo(4, 0.000001));
      expect(provider.completedRooms[0].points.first.z, closeTo(-2, 0.000001));
      _expectSameFeatureGeometry(
        provider.completedRooms[0].features.single,
        provider.completedRooms[1].features.single,
      );
      expect(provider.canUndoTransform, isTrue);
      expect(await provider.undoTransform(), isTrue);
      expect(provider.completedRooms[0].points.first.x, closeTo(0, 0.000001));
      expect(provider.completedRooms[0].points.first.z, closeTo(0, 0.000001));
      expect(provider.canUndoTransform, isFalse);
    });

    test('el arrastre táctil revierte si Drift rechaza la persistencia', () async {
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project-touch-save-failure',
          name: 'Casa con fallo de guardado',
          rooms: [
            _roomAt('anchor', 0, 0),
            _roomAt('movable', 4, 0),
          ],
        );
      addTearDown(provider.dispose);
      provider.persister = ({
        required String uuid,
        required String name,
        required List<RoomModel> rooms,
      }) async {
        throw StateError('Save failed');
      };

      final before = provider.completedRooms.map((r) => r.toJson()).toList();
      expect(provider.beginTouchRoomTransform('movable'), isTrue);
      expect(
        provider.updateTouchRoomTransform(
          roomId: 'movable',
          offsetX: -1.8,
          offsetZ: 0,
          angleDegrees: 0,
        ),
        isTrue,
      );

      expect(await provider.endTouchRoomTransform(roomId: 'movable'), isFalse);
      expect(
        provider.completedRooms.map((r) => r.toJson()).toList(),
        before,
      );
      expect(provider.canUndoTransform, isFalse);
    });

    test('el imán ajusta una pared durante el arrastre', () async {
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project-live-magnet',
          name: 'Casa con imán',
          rooms: [
            _roomAt('anchor', 0, 0),
            _roomAt('movable', 4, 0),
          ],
        );
      addTearDown(provider.dispose);

      expect(provider.beginTouchRoomTransform('movable'), isTrue);
      expect(
        provider.updateTouchRoomTransform(
          roomId: 'movable',
          offsetX: -1.90,
          offsetZ: 0,
          angleDegrees: 0,
        ),
        isTrue,
      );

      expect(provider.touchTransformSnapCount, 1);
      expect(
        provider.completedRooms.last.points.first.x,
        closeTo(2, 0.000001),
      );
      expect(
        await provider.endTouchRoomTransform(roomId: 'movable'),
        isTrue,
      );
      expect(provider.canUndoTransform, isTrue);
    });

    test('el imán conserva el encaje hasta una separación deliberada', () async {
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project-magnet-release',
          name: 'Casa con liberación del imán',
          rooms: [
            _roomAt('anchor', 0, 0),
            _roomAt('movable', 4, 0),
          ],
        );
      addTearDown(provider.dispose);

      expect(provider.beginTouchRoomTransform('movable'), isTrue);
      provider.updateTouchRoomTransform(
        roomId: 'movable',
        offsetX: -1.86,
        offsetZ: 0,
        angleDegrees: 0,
      );
      expect(provider.touchTransformSnapCount, 1);

      provider.updateTouchRoomTransform(
        roomId: 'movable',
        offsetX: -1.82,
        offsetZ: 0,
        angleDegrees: 0,
      );
      expect(provider.touchTransformSnapCount, 1);
      expect(
        provider.completedRooms.last.points.first.x,
        closeTo(2, 0.000001),
      );

      provider.updateTouchRoomTransform(
        roomId: 'movable',
        offsetX: -1.70,
        offsetZ: 0,
        angleDegrees: 0,
      );
      expect(provider.touchTransformSnapCount, 0);
      expect(
        provider.completedRooms.last.points.first.x,
        closeTo(2.30, 0.000001),
      );
    });

    test('el imán combina tres paredes compatibles', () async {
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project-three-wall-magnet',
          name: 'Casa con tres uniones',
          rooms: [
            _roomAt('left', 0, 0),
            _roomAt('top', 2, -2),
            _roomAt('right', 4, 0),
            _roomAt('movable', 4.1, 0.1),
          ],
        );
      addTearDown(provider.dispose);

      expect(provider.beginTouchRoomTransform('movable'), isTrue);
      expect(
        provider.updateTouchRoomTransform(
          roomId: 'movable',
          offsetX: -2,
          offsetZ: 0,
          angleDegrees: 0,
        ),
        isTrue,
      );

      expect(provider.touchTransformSnapCount, 3);
      final movable = provider.completedRooms.last;
      expect(movable.points.first.x, closeTo(2, 0.000001));
      expect(movable.points.first.z, closeTo(0, 0.000001));
      final shared = SharedWallService.detect(rooms: provider.completedRooms)
          .where(
            (wall) =>
                wall.firstRoomId == 'movable' ||
                wall.secondRoomId == 'movable',
          );
      expect(shared, hasLength(3));
      expect(
        await provider.endTouchRoomTransform(roomId: 'movable'),
        isTrue,
      );
      expect(await provider.undoTransform(), isTrue);
      expect(
        provider.completedRooms.last.points.first.x,
        closeTo(4.1, 0.000001),
      );
      expect(
        provider.completedRooms.last.points.first.z,
        closeTo(0.1, 0.000001),
      );
    });

    test('ajusta y acepta una unión verde con exceso mínimo', () async {
      final anchor = _connectedRooms().first.copyWith(features: const []);
      final movable = _independentRoom(offsetX: 4);
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project-touch-green-join',
          name: 'Casa con unión verde',
          rooms: [anchor, movable],
        );
      addTearDown(provider.dispose);

      expect(provider.beginTouchRoomTransform('room-c'), isTrue);
      expect(
        provider.updateTouchRoomTransform(
          roomId: 'room-c',
          offsetX: -2.02,
          offsetZ: 0,
          angleDegrees: 0,
        ),
        isTrue,
      );
      expect(
        await provider.endTouchRoomTransform(roomId: 'room-c'),
        isTrue,
      );

      final joined = provider.completedRooms.last;
      expect(joined.points.first.x, closeTo(2, 0.000001));
      expect(
        SharedWallService.detect(rooms: provider.completedRooms),
        hasLength(1),
      );
      expect(provider.canUndoTransform, isTrue);
      expect(await provider.undoTransform(), isTrue);
      expect(
        provider.completedRooms.last.points.first.x,
        closeTo(4, 0.000001),
      );
    });

    test('sigue rechazando un solapamiento táctil real', () async {
      final anchor = _connectedRooms().first.copyWith(features: const []);
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project-touch-real-overlap',
          name: 'Casa con solapamiento real',
          rooms: [anchor, _independentRoom(offsetX: 4)],
        );
      addTearDown(provider.dispose);

      expect(provider.beginTouchRoomTransform('room-c'), isTrue);
      expect(
        provider.updateTouchRoomTransform(
          roomId: 'room-c',
          offsetX: -2.30,
          offsetZ: 0,
          angleDegrees: 0,
        ),
        isTrue,
      );
      expect(
        await provider.endTouchRoomTransform(roomId: 'room-c'),
        isFalse,
      );
      expect(
        provider.completedRooms.last.points.first.x,
        closeTo(4, 0.000001),
      );
      expect(provider.canUndoTransform, isFalse);
    });

    test('conserva la última posición válida al atravesar otro ambiente',
        () async {
      final anchor = _connectedRooms().first.copyWith(features: const []);
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project-touch-last-valid',
          name: 'Casa con límite seguro',
          rooms: [anchor, _independentRoom(offsetX: 4)],
        );
      addTearDown(provider.dispose);

      expect(provider.beginTouchRoomTransform('room-c'), isTrue);
      expect(provider.updateTouchRoomTransform(
        roomId: 'room-c', offsetX: -1.7, offsetZ: 0, angleDegrees: 0,
      ), isTrue);
      expect(provider.updateTouchRoomTransform(
        roomId: 'room-c', offsetX: -2.3, offsetZ: 0, angleDegrees: 0,
      ), isTrue);
      expect(await provider.endTouchRoomTransform(roomId: 'room-c'), isTrue);
      expect(provider.completedRooms.last.points.first.x, greaterThanOrEqualTo(2));
      expect(provider.canUndoTransform, isTrue);
    });

    test(
      'la corrección táctil mueve solo el ambiente seleccionado y conserva la abertura anclada',
      () async {
        final provider = FloorPlanProvider();
        provider.loadProject(
          uuid: 'project-touch-transform',
          name: 'Casa con corrección táctil',
          rooms: _connectedRooms(),
        );
        final sourceBefore = provider.completedRooms[0];
        final openingBefore = provider.completedRooms[1].features.single;

        expect(provider.beginTouchRoomTransform('room-b'), isTrue);
        expect(
          provider.updateTouchRoomTransform(
            roomId: 'room-b',
            offsetX: 2,
            offsetZ: 0,
            angleDegrees: 0,
          ),
          isTrue,
        );
        expect(
          await provider.endTouchRoomTransform(
            roomId: 'room-b',
            snapToConnectedOpening: false,
          ),
          isTrue,
        );

        expect(provider.completedRooms[0].points.first.x, sourceBefore.points.first.x);
        expect(provider.completedRooms[1].points.first.x, closeTo(4, 0.000001));
        _expectSameFeatureGeometry(
          openingBefore,
          provider.completedRooms[1].features.single,
        );
        expect(provider.canUndoTransform, isTrue);
        expect(await provider.undoTransform(), isTrue);
        expect(provider.completedRooms[1].points.first.x, closeTo(2, 0.000001));
      },
    );

    test('rechaza un ajuste preciso que produciría solapamiento', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-rejected-precise-transform',
        name: 'Casa con ajuste preciso bloqueado',
        rooms: _connectedRooms()..add(_rotationObstacle()),
      );

      final applied = await provider.transformRoomPrecisely(
        roomId: 'room-a',
        offsetX: 0,
        offsetZ: 0,
        angleDegrees: 90,
      );

      expect(applied, isFalse);
      expect(provider.completedRooms.first.points.first.x, closeTo(0, 0.000001));
      expect(provider.completedRooms.first.points.first.z, closeTo(0, 0.000001));
      expect(provider.canUndoTransform, isFalse);
    });

  });
}

RoomModel _roomAt(
  String id,
  double minX,
  double minZ,
) {
  return RoomModel(
    id: id,
    name: id,
    type: RoomType.other,
    points: [
      ARPoint(x: minX, y: 0, z: minZ),
      ARPoint(x: minX + 2, y: 0, z: minZ),
      ARPoint(x: minX + 2, y: 0, z: minZ + 2),
      ARPoint(x: minX, y: 0, z: minZ + 2),
    ],
    isClosed: true,
  );
}

RoomModel _rotationObstacle() {
  return RoomModel(
    id: 'room-rotation-obstacle',
    name: 'Obstáculo de rotación',
    type: RoomType.pasillo,
    points: [
      ARPoint(x: 1.2, y: 0, z: 2.2),
      ARPoint(x: 1.8, y: 0, z: 2.2),
      ARPoint(x: 1.8, y: 0, z: 2.8),
      ARPoint(x: 1.2, y: 0, z: 2.8),
    ],
    isClosed: true,
  );
}

RoomModel _diamondObstacle() {
  return RoomModel(
    id: 'room-d',
    name: 'Obstáculo geométrico',
    type: RoomType.pasillo,
    points: [
      ARPoint(x: 4.10, y: 0, z: 0.90),
      ARPoint(x: 4.18, y: 0, z: 1.00),
      ARPoint(x: 4.10, y: 0, z: 1.10),
      ARPoint(x: 4.02, y: 0, z: 1.00),
    ],
    isClosed: true,
  );
}

RoomModel _independentRoom({required double offsetX}) {
  return RoomModel(
    id: 'room-c',
    name: 'Ambiente C',
    type: RoomType.dormitorio,
    points: [
      ARPoint(x: offsetX, y: 0, z: 0),
      ARPoint(x: offsetX + 2, y: 0, z: 0),
      ARPoint(x: offsetX + 2, y: 0, z: 2),
      ARPoint(x: offsetX, y: 0, z: 2),
    ],
    isClosed: true,
  );
}

List<RoomModel> _connectedRooms() {
  final sharedA = WallFeature(
    id: 'shared-door',
    type: FeatureType.door,
    start: ARPoint(x: 2, y: 0, z: 0.5),
    end: ARPoint(x: 2, y: 0, z: 1.5),
    connectedRoomId: 'room-b',
    connectionSide: OpeningConnectionSide.right,
  );
  final sharedB = sharedA.copyWith(
    connectedRoomId: 'room-a',
    connectionSide: OpeningConnectionSide.left,
  );

  return [
    RoomModel(
      id: 'room-a',
      name: 'Ambiente A',
      type: RoomType.living,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 2, y: 0, z: 0),
        ARPoint(x: 2, y: 0, z: 2),
        ARPoint(x: 0, y: 0, z: 2),
      ],
      features: [sharedA],
      isClosed: true,
    ),
    RoomModel(
      id: 'room-b',
      name: 'Ambiente B',
      type: RoomType.cocina,
      points: [
        ARPoint(x: 2, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 2),
        ARPoint(x: 2, y: 0, z: 2),
      ],
      features: [sharedB],
      isClosed: true,
    ),
  ];
}

void _expectSameFeatureGeometry(
  WallFeature first,
  WallFeature second,
) {
  expect(first.id, second.id);  expect(first.start.x, closeTo(second.start.x, 0.000001));
  expect(first.start.z, closeTo(second.start.z, 0.000001));
  expect(first.end.x, closeTo(second.end.x, 0.000001));
  expect(first.end.z, closeTo(second.end.z, 0.000001));
}

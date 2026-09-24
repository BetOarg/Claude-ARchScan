import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  group('detección de paredes compartidas', () {
    test('detecta una pared completa entre dos ambientes', () {
      final matches = SharedWallService.detect(
        rooms: [
          _rectangle('room-a', 0, 0, 2, 2),
          _rectangle('room-b', 2, 0, 4, 2),
        ],
      );

      expect(matches, hasLength(1));
      expect(matches.single.firstRoomId, 'room-a');
      expect(matches.single.secondRoomId, 'room-b');
      expect(matches.single.lengthMeters, closeTo(2, 0.000001));
      expect(matches.single.coverage, SharedWallCoverage.complete);
      expect(matches.single.coversFirstWall, isTrue);
      expect(matches.single.coversSecondWall, isTrue);
      expect(matches.single.firstWallCoverage, closeTo(1, 0.000001));
      expect(matches.single.secondWallCoverage, closeTo(1, 0.000001));
    });

    test('detecta solamente el tramo realmente superpuesto', () {
      final matches = SharedWallService.detect(
        rooms: [
          _rectangle('room-a', 0, 0, 2, 3),
          _rectangle('room-b', 2, 1, 4, 2),
        ],
      );

      expect(matches, hasLength(1));
      expect(matches.single.lengthMeters, closeTo(1, 0.000001));
      expect(matches.single.start.z, closeTo(1, 0.000001));
      expect(matches.single.end.z, closeTo(2, 0.000001));
      expect(matches.single.coverage, SharedWallCoverage.partial);
      expect(matches.single.coversFirstWall, isFalse);
      expect(matches.single.coversSecondWall, isTrue);
      expect(matches.single.firstWallCoverage, closeTo(1 / 3, 0.000001));
      expect(matches.single.secondWallCoverage, closeTo(1, 0.000001));
    });

    test('clasifica como parcial cuando sobresale el segundo ambiente', () {
      final matches = SharedWallService.detect(
        rooms: [
          _rectangle('room-a', 0, 1, 2, 2),
          _rectangle('room-b', 2, 0, 4, 3),
        ],
      );

      expect(matches, hasLength(1));
      expect(matches.single.coverage, SharedWallCoverage.partial);
      expect(matches.single.coversFirstWall, isTrue);
      expect(matches.single.coversSecondWall, isFalse);
      expect(matches.single.firstWallCoverage, closeTo(1, 0.000001));
      expect(matches.single.secondWallCoverage, closeTo(1 / 3, 0.000001));
    });

    test('ignora el cierre implícito de un ambiente abierto', () {
      final openRoom = RoomModel(
        id: 'open-room',
        name: 'Ambiente abierto',
        type: RoomType.other,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 2, y: 0, z: 0),
          ARPoint(x: 2, y: 0, z: 2),
        ],
        isClosed: false,
      );
      final diagonalRoom = RoomModel(
        id: 'diagonal-room',
        name: 'Tramo diagonal',
        type: RoomType.other,
        points: [ARPoint(x: 0, y: 0, z: 0), ARPoint(x: 2, y: 0, z: 2)],
        isClosed: false,
      );

      final matches = SharedWallService.detect(rooms: [openRoom, diagonalRoom]);

      expect(matches, isEmpty);
    });

    test('no relaciona paredes separadas fuera de tolerancia', () {
      final matches = SharedWallService.detect(
        rooms: [
          _rectangle('room-a', 0, 0, 2, 2),
          _rectangle('room-b', 2.05, 0, 4.05, 2),
        ],
      );

      expect(matches, isEmpty);
    });
  });
}

RoomModel _rectangle(
  String id,
  double minX,
  double minZ,
  double maxX,
  double maxZ,
) {
  return RoomModel(
    id: id,
    name: id,
    type: RoomType.living,
    points: [
      ARPoint(x: minX, y: 0, z: minZ),
      ARPoint(x: maxX, y: 0, z: minZ),
      ARPoint(x: maxX, y: 0, z: maxZ),
      ARPoint(x: minX, y: 0, z: maxZ),
    ],
    isClosed: true,
  );
}

import 'dart:math' as math;

import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'metric DXF contains walls, room names, openings and dimensions only',
    () {
      final door = WallFeature(
        id: 'door',
        type: FeatureType.door,
        start: ARPoint(x: 0.5, y: 0, z: 0),
        end: ARPoint(x: 1.5, y: 0, z: 0),
      );
      final window = WallFeature(
        id: 'window',
        type: FeatureType.window,
        start: ARPoint(x: 2, y: 0, z: 0.5),
        end: ARPoint(x: 2, y: 0, z: 1.5),
      );
      final room = _room().copyWith(features: [door, window]);
      final dxf = DxfExportBuilder.build([room]);

      expect(dxf, contains('\$INSUNITS\r\n70\r\n6\r\n'));
      expect(dxf, contains('2\r\nWALLS\r\n'));
      expect(dxf, contains('2\r\nDOORS\r\n'));
      expect(dxf, contains('2\r\nWINDOWS\r\n'));
      expect(dxf, contains('2\r\nROOM_NAMES\r\n'));
      expect(dxf, contains('2\r\nMEASUREMENTS\r\n'));
      expect(dxf, contains('Dormitorio'));
    },
  );

  test('dimension geometry is separated from the wall', () {
    final entities = _entities(DxfExportBuilder.build([_room()]));
    final walls = entities
        .where((e) => e[0] == 'LINE' && e[8] == 'WALLS')
        .toList();
    final measurements = entities
        .where((e) => e[0] == 'LINE' && e[8] == 'MEASUREMENTS')
        .toList();

    expect(walls, hasLength(4));
    expect(measurements, hasLength(14));
    // The shortest wall is vertical, so the first dimension line is offset
    // horizontally. Compare its X coordinate with either vertical wall.
    final dimensionX = double.parse(measurements[2][10]!);
    final distanceToNearestVerticalWall = math.min(
      dimensionX.abs(),
      (dimensionX - 3.0).abs(),
    );
    expect(distanceToNearestVerticalWall, greaterThan(0.35));
    // Each dimension now has two arrowheads (four additional line entities).
    expect(measurements.length % 7, 0);
  });

  test('imperial labels use feet and inches', () {
    final dxf = DxfExportBuilder.build([_room()], languageCode: 'en');
    final labels = _entities(dxf)
        .where((e) => e[8] == 'MEASUREMENTS')
        .map((e) => e[1])
        .whereType<String>();
    expect(labels, contains('9 ft 10 1/8 in'));
    expect(labels, contains('6 ft 6 3/4 in'));
  });

  test('shared openings are drawn once and shared walls are deduplicated', () {
    final door = WallFeature(
      id: 'shared-door',
      type: FeatureType.door,
      start: ARPoint(x: 2, y: 0, z: 0.8),
      end: ARPoint(x: 2, y: 0, z: 1.7),
    );
    final a = _room();
    final b = RoomModel(
      id: 'b',
      name: 'B',
      type: RoomType.cocina,
      points: [
        ARPoint(x: 2, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 2),
        ARPoint(x: 2, y: 0, z: 2),
      ],
      features: [door],
      isClosed: true,
    );
    final dxf = DxfExportBuilder.build([
      a.copyWith(features: [door]),
      b,
    ]);
    final entities = _entities(dxf);
    expect(entities.where((e) => e[0] == 'ARC'), hasLength(1));
    final wallLines = entities
        .where((e) => e[0] == 'LINE' && e[8] == 'WALLS')
        .toList();
    expect(wallLines, hasLength(11));
    expect(wallLines.toSet(), hasLength(11));
    expect(
      entities.where((e) => e[0] == 'TEXT' && e[8] == 'ROOM_NAMES'),
      hasLength(2),
    );
  });

  test('preserves model data and rejects invalid coordinates', () {
    final room = _room();
    final before = room.toJson();
    DxfExportBuilder.build([room]);
    expect(room.toJson(), before);
    expect(
      () => DxfExportBuilder.build([
        room.copyWith(points: [ARPoint(x: double.nan, y: 0, z: 0)]),
      ]),
      throwsArgumentError,
    );
  });
}

RoomModel _room() => RoomModel(
  id: 'r',
  name: 'Dormitorio',
  type: RoomType.dormitorio,
  points: [
    ARPoint(x: 0, y: 0, z: 0),
    ARPoint(x: 3, y: 0, z: 0),
    ARPoint(x: 3, y: 0, z: 2),
    ARPoint(x: 0, y: 0, z: 2),
  ],
  isClosed: true,
);

List<Map<int, String>> _entities(String dxf) {
  final lines = dxf.split('\r\n');
  final result = <Map<int, String>>[];
  var inside = false;
  Map<int, String>? current;
  for (var i = 0; i + 1 < lines.length; i += 2) {
    final code = int.parse(lines[i]);
    final value = lines[i + 1];
    if (code == 2 && value == 'ENTITIES') {
      inside = true;
      continue;
    }
    if (!inside) continue;
    if (code == 0) {
      if (current != null) result.add(current);
      if (value == 'ENDSEC') break;
      current = <int, String>{};
    }
    current?[code] = value;
  }
  return result;
}

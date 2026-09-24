import 'dart:math' as math;

import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  test('rectangular plan keeps walls, room name, dimensions and metadata', () {
    final room = _rectangle('rect', 'Living', 3, 2);
    final svg = PlanExportBuilder.buildFloorPlanSvg([
      room,
    ], MeasurementSystem.metric);
    final dxf = DxfExportBuilder.build([room]);

    expect(RegExp(r'<polygon ').allMatches(svg).length, 1);
    expect(svg, contains('>Living<'));
    expect(svg, contains('id="cotas"'));
    expect(svg, contains('data-generator="ARchScan"'));
    expect(svg, contains('data-format="json-base64-v1"'));
    expect(PlanExportBuilder.parseProjectSvg(svg)?.rooms.single.id, 'rect');

    final entities = _entities(dxf);
    expect(
      entities.where((e) => e[0] == 'LINE' && e[8] == 'WALLS'),
      hasLength(4),
    );
    expect(
      entities.where((e) => e[0] == 'TEXT' && e[8] == 'ROOM_NAMES'),
      hasLength(1),
    );
    expect(
      entities.where((e) => e[0] == 'LINE' && e[8] == 'MEASUREMENTS'),
      isNotEmpty,
    );
  });

  test('DXF and SVG preserve the same geometric invariants', () {
    final room = _rectangle('invariant', 'Invariant', 4, 2);
    final svg = PlanExportBuilder.buildFloorPlanSvg([
      room,
    ], MeasurementSystem.metric);
    final dxf = DxfExportBuilder.build([room]);
    final svgPoints = _svgPolygonPoints(svg);
    final dxfSegments = _dxfWallSegments(dxf);

    expect(svgPoints, hasLength(4));
    expect(dxfSegments, hasLength(4));

    final svgLengths = _edgeLengths(svgPoints);
    final dxfLengths = dxfSegments
        .map((segment) => _distance(segment.$1, segment.$2))
        .toList();

    final svgScale = svgLengths.first / dxfLengths.first;
    for (var i = 0; i < svgLengths.length; i++) {
      expect(
        svgLengths[i] / dxfLengths[i],
        closeTo(svgScale, kGeometryEpsilon),
      );
    }

    final svgArea = _signedArea(svgPoints);
    final dxfArea = _signedArea([
      for (final segment in dxfSegments) segment.$1,
    ]);
    expect(
      svgArea.abs() / dxfArea.abs(),
      closeTo(svgScale * svgScale, kGeometryEpsilon),
    );
  });

  test('PDF is generated from the same technical SVG geometry', () async {
    final room = _rectangle('pdf', 'PDF', 3, 2);
    final svg = PlanExportBuilder.buildFloorPlanSvg([
      room,
    ], MeasurementSystem.metric);
    final pdf = PlanExportBuilder.buildPdfDocument(
      [room],
      'PDF',
      MeasurementSystem.metric,
    );
    final bytes = await pdf.save();

    expect(svg, contains('data-generator="ARchScan"'));
    expect(bytes, isNotEmpty);
    expect(svg, contains('<polygon'));
  });

  test(
    'technical SVG auto-fits the complete drawing instead of a fixed viewport',
    () {
      final room = _rectangle('fit', 'Fit', 3, 2);
      final svg = PlanExportBuilder.buildFloorPlanSvg([
        room,
      ], MeasurementSystem.metric);

      final match = RegExp(r'viewBox="([^"]+)"').firstMatch(svg);
      expect(match, isNotNull);
      final viewBox = match!
          .group(1)!
          .split(RegExp(r'\s+'))
          .map(double.parse)
          .toList();

      expect(viewBox, hasLength(4));
      expect(viewBox[2], isNot(900));
      expect(viewBox[3], isNot(600));
      expect(svg, contains('id="cotas"'));
    },
  );

  test(
    'L-shaped plan preserves all perimeter edges and technical dimensions',
    () {
      final room = RoomModel(
        id: 'l',
        name: 'L',
        type: RoomType.living,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 1),
          ARPoint(x: 2, y: 0, z: 1),
          ARPoint(x: 2, y: 0, z: 3),
          ARPoint(x: 0, y: 0, z: 3),
        ],
        isClosed: true,
      );

      final svg = PlanExportBuilder.buildFloorPlanSvg([
        room,
      ], MeasurementSystem.metric);
      final dxf = DxfExportBuilder.build([room]);

      expect(RegExp(r'<polygon ').allMatches(svg).length, 1);
      expect(svg, contains('>L<'));
      final entities = _entities(dxf);
      expect(
        entities.where((e) => e[0] == 'LINE' && e[8] == 'WALLS'),
        hasLength(6),
      );
      expect(
        entities.where((e) => e[0] == 'LINE' && e[8] == 'MEASUREMENTS'),
        isNotEmpty,
      );
    },
  );

  test('two adjacent rooms deduplicate the shared wall and shared opening', () {
    final sharedDoor = WallFeature(
      id: 'shared-door',
      type: FeatureType.door,
      start: ARPoint(x: 3, y: 0, z: 0.7),
      end: ARPoint(x: 3, y: 0, z: 1.6),
    );
    final first = _rectangle('a', 'A', 3, 2).copyWith(features: [sharedDoor]);
    final second = RoomModel(
      id: 'b',
      name: 'B',
      type: RoomType.cocina,
      points: [
        ARPoint(x: 3, y: 0, z: 0),
        ARPoint(x: 5, y: 0, z: 0),
        ARPoint(x: 5, y: 0, z: 2),
        ARPoint(x: 3, y: 0, z: 2),
      ],
      features: [sharedDoor],
      isClosed: true,
    );

    final svg = PlanExportBuilder.buildFloorPlanSvg([
      first,
      second,
    ], MeasurementSystem.metric);
    final dxf = DxfExportBuilder.build([first, second]);

    expect(RegExp(r'<polygon ').allMatches(svg).length, 2);
    expect(svg, contains('>A<'));
    expect(svg, contains('>B<'));

    final dxfEntities = _entities(dxf);
    expect(dxfEntities.where((e) => e[0] == 'ARC'), hasLength(1));
    expect(
      dxfEntities.where((e) => e[0] == 'TEXT' && e[8] == 'ROOM_NAMES'),
      hasLength(2),
    );
    expect(
      dxfEntities.where((e) => e[0] == 'LINE' && e[8] == 'WALLS'),
      hasLength(8),
    );
  });

  test('technical export remains stable for multiple rooms and openings', () {
    final rooms = [
      _rectangle('a', 'A', 3, 2).copyWith(
        features: [
          WallFeature(
            id: 'door-a',
            type: FeatureType.door,
            start: ARPoint(x: 0.8, y: 0, z: 0),
            end: ARPoint(x: 1.6, y: 0, z: 0),
          ),
        ],
      ),
      RoomModel(
        id: 'b',
        name: 'B',
        type: RoomType.living,
        points: [
          ARPoint(x: 4, y: 0, z: 0),
          ARPoint(x: 6, y: 0, z: 0),
          ARPoint(x: 6, y: 0, z: 2),
          ARPoint(x: 4, y: 0, z: 2),
        ],
        features: [
          WallFeature(
            id: 'window-b',
            type: FeatureType.window,
            start: ARPoint(x: 6, y: 0, z: 0.4),
            end: ARPoint(x: 6, y: 0, z: 1.6),
          ),
        ],
        isClosed: true,
      ),
    ];

    final svg = PlanExportBuilder.buildFloorPlanSvg(
      rooms,
      MeasurementSystem.metric,
    );
    final dxf = DxfExportBuilder.build(rooms);

    expect(RegExp(r'<polygon ').allMatches(svg).length, 2);
    expect(RegExp(r'<g data-feature-id="door-a">').allMatches(svg).length, 1);
    expect(RegExp(r'<g data-feature-id="window-b">').allMatches(svg).length, 1);
    expect(svg, contains('>A<'));
    expect(svg, contains('>B<'));
    expect(_entities(dxf).where((e) => e[8] == 'ROOM_NAMES'), hasLength(2));
    expect(_entities(dxf).where((e) => e[8] == 'MEASUREMENTS'), isNotEmpty);
  });
}

RoomModel _rectangle(String id, String name, double width, double height) {
  return RoomModel(
    id: id,
    name: name,
    type: RoomType.living,
    points: [
      ARPoint(x: 0, y: 0, z: 0),
      ARPoint(x: width, y: 0, z: 0),
      ARPoint(x: width, y: 0, z: height),
      ARPoint(x: 0, y: 0, z: height),
    ],
    isClosed: true,
  );
}

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

List<_SvgPoint> _svgPolygonPoints(String svg) {
  final match = RegExp(r'<polygon points="([^"]+)"').firstMatch(svg);
  if (match == null) return <_SvgPoint>[];
  return match.group(1)!.trim().split(RegExp(r'\s+')).map((pair) {
    final values = pair.split(',');
    return _SvgPoint(double.parse(values[0]), double.parse(values[1]));
  }).toList();
}

List<(_SvgPoint, _SvgPoint)> _dxfWallSegments(String dxf) {
  return _entities(dxf)
      .where((entity) => entity[0] == 'LINE' && entity[8] == 'WALLS')
      .map(
        (entity) => (
          _SvgPoint(double.parse(entity[10]!), double.parse(entity[20]!)),
          _SvgPoint(double.parse(entity[11]!), double.parse(entity[21]!)),
        ),
      )
      .toList();
}

List<double> _edgeLengths(List<_SvgPoint> points) {
  return [
    for (var i = 0; i < points.length; i++)
      _distance(points[i], points[(i + 1) % points.length]),
  ];
}

double _distance(_SvgPoint a, _SvgPoint b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  return math.sqrt(dx * dx + dy * dy);
}

double _signedArea(List<_SvgPoint> points) {
  var sum = 0.0;
  for (var i = 0; i < points.length; i++) {
    final next = points[(i + 1) % points.length];
    sum += points[i].x * next.y - next.x * points[i].y;
  }
  return sum / 2;
}

class _SvgPoint {
  final double x;
  final double y;
  const _SvgPoint(this.x, this.y);
}

import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  test('rectangular plan keeps walls, room name, dimensions and metadata', () {
    final room = _rectangle('rect', 'Living', 3, 2);
    final svg = PlanExportBuilder.buildFloorPlanSvg([room], MeasurementSystem.metric);
    final dxf = DxfExportBuilder.build([room]);

    expect(RegExp(r'<polygon ').allMatches(svg).length, 1);
    expect(svg, contains('>Living<'));
    expect(svg, contains('id="cotas"'));
    expect(svg, contains('data-generator="ARchScan"'));
    expect(svg, contains('data-format="json-base64-v1"'));
    expect(PlanExportBuilder.parseProjectSvg(svg)?.rooms.single.id, 'rect');

    final entities = _entities(dxf);
    expect(entities.where((e) => e[0] == 'LINE' && e[8] == 'WALLS'), hasLength(4));
    expect(entities.where((e) => e[0] == 'TEXT' && e[8] == 'ROOM_NAMES'), hasLength(1));
    expect(entities.where((e) => e[0] == 'LINE' && e[8] == 'MEASUREMENTS'), isNotEmpty);
  });

  test('technical SVG auto-fits the complete drawing instead of a fixed viewport', () {
    final room = _rectangle('fit', 'Fit', 3, 2);
    final svg = PlanExportBuilder.buildFloorPlanSvg(
      [room],
      MeasurementSystem.metric,
    );

    final match = RegExp(r'viewBox="([^"]+)"').firstMatch(svg);
    expect(match, isNotNull);
    final viewBox = match!.group(1)!.split(RegExp(r'\\s+')).map(double.parse).toList();

    expect(viewBox, hasLength(4));
    expect(viewBox[2], isNot(900));
    expect(viewBox[3], isNot(600));
    expect(svg, contains('id="cotas"'));
  });

  test('L-shaped plan preserves all perimeter edges and technical dimensions', () {
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

    final svg = PlanExportBuilder.buildFloorPlanSvg([room], MeasurementSystem.metric);
    final dxf = DxfExportBuilder.build([room]);

    expect(RegExp(r'<polygon ').allMatches(svg).length, 1);
    expect(svg, contains('>L<'));
    final entities = _entities(dxf);
    expect(entities.where((e) => e[0] == 'LINE' && e[8] == 'WALLS'), hasLength(6));
    expect(entities.where((e) => e[0] == 'LINE' && e[8] == 'MEASUREMENTS'), isNotEmpty);
  });

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

    final svg = PlanExportBuilder.buildFloorPlanSvg([first, second], MeasurementSystem.metric);
    final dxf = DxfExportBuilder.build([first, second]);

    expect(RegExp(r'<polygon ').allMatches(svg).length, 2);
    expect(svg, contains('>A<'));
    expect(svg, contains('>B<'));

    final dxfEntities = _entities(dxf);
    expect(dxfEntities.where((e) => e[0] == 'ARC'), hasLength(1));
    expect(dxfEntities.where((e) => e[0] == 'TEXT' && e[8] == 'ROOM_NAMES'), hasLength(2));
    expect(dxfEntities.where((e) => e[0] == 'LINE' && e[8] == 'WALLS'), hasLength(8));
  });

  test('technical export remains stable for multiple rooms and openings', () {
    final rooms = [
      _rectangle('a', 'A', 3, 2).copyWith(features: [
        WallFeature(
          id: 'door-a',
          type: FeatureType.door,
          start: ARPoint(x: 0.8, y: 0, z: 0),
          end: ARPoint(x: 1.6, y: 0, z: 0),
        ),
      ]),
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

    final svg = PlanExportBuilder.buildFloorPlanSvg(rooms, MeasurementSystem.metric);
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
